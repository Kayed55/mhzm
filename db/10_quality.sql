-- ============================================================================
-- نظام مساند الجودة — نموذج البيانات + الدوال
-- ============================================================================
-- يُعاد استخدام: users/sessions/employees/team_leaders/settings/audit_logs.
-- جديد: meta_settings, quality_keywords, customers, messages, quality_notes.
-- الأمان: RLS + سحب anon؛ الوصول عبر RPCs مُصادَقة. أسرار Meta في Vault.
-- ============================================================================

-- إعدادات Meta Cloud API (صفّ واحد؛ الأسرار في Vault)
create table if not exists public.meta_settings (
  id                     int primary key default 1 check (id = 1),
  app_id                 text,
  business_id            text,
  waba_id                text,
  phone_number_id        text,
  verify_token           text,
  webhook_url            text,
  access_token_secret_id uuid,   -- Vault
  app_secret_secret_id   uuid,   -- Vault
  connection_status      text not null default 'unknown'
                           check (connection_status in ('connected','disconnected','error','unknown')),
  last_event_at          timestamptz,
  last_error             text,
  updated_at             timestamptz not null default now(),
  updated_by             bigint references public.users(id) on delete set null
);
insert into public.meta_settings(id) values (1) on conflict (id) do nothing;

-- كلمات/أوامر الجودة
create table if not exists public.quality_keywords (
  id         bigint primary key generated always as identity,
  phrase     text not null,
  label      text not null default 'ملاحظة جودة',   -- نوع الملاحظة
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- العملاء (من واتساب)
create table if not exists public.customers (
  id         bigint primary key generated always as identity,
  wa_id      text unique,                 -- رقم/معرّف واتساب
  name       text,
  created_at timestamptz not null default now()
);

-- الرسائل المسحوبة
create table if not exists public.messages (
  id            bigint primary key generated always as identity,
  wa_message_id text unique,              -- معرّف رسالة واتساب (منع التكرار)
  customer_id   bigint references public.customers(id) on delete cascade,
  employee_id   bigint references public.employees(id) on delete set null,  -- الموظف (إن عُرِف)
  direction     text not null default 'inbound' check (direction in ('inbound','outbound')),
  body          text,
  sent_at       timestamptz,
  raw           jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists idx_messages_sent on public.messages(sent_at desc);

-- الملاحظات المرصودة تلقائياً
create table if not exists public.quality_notes (
  id            bigint primary key generated always as identity,
  employee_id   bigint references public.employees(id) on delete set null,
  customer_id   bigint references public.customers(id) on delete set null,
  customer_name text,
  message_id    bigint references public.messages(id) on delete cascade,
  message_text  text,
  message_at    timestamptz,
  keyword_id    bigint references public.quality_keywords(id) on delete set null,
  matched_phrase text,
  label         text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_qnotes_emp on public.quality_notes(employee_id);
create index if not exists idx_qnotes_at on public.quality_notes(message_at desc);
create index if not exists idx_qnotes_label on public.quality_notes(label);

-- RLS + سحب anon عن الجداول الجديدة
do $$ declare t text; begin
  for t in select unnest(array['meta_settings','quality_keywords','customers','messages','quality_notes']) loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- بذور: كلمات جودة افتراضية
insert into public.quality_keywords(phrase,label) values
  ('تم التواصل خارج النظام','تواصل خارج النظام'),
  ('ارسل حسابك','طلب تحويل خارجي'),
  ('تحويل خاص','طلب تحويل خارجي'),
  ('انتظر الرد','تأخير رد'),
  ('تم الإلغاء','إلغاء طلب')
on conflict do nothing;

-- ========================== الدوال ==========================

-- فحص رسالة وإنشاء ملاحظات لأي كلمة جودة مرصودة (يُستدعى عند الاستقبال)
create or replace function public.scan_message(p_message_id bigint)
returns int language plpgsql security definer set search_path to 'public' as $$
declare m public.messages; k record; v_body text; v_cust text; v_n int := 0;
begin
  select * into m from public.messages where id = p_message_id;
  if m.id is null then return 0; end if;
  v_body := ' ' || public.normalize_ar(m.body) || ' ';
  select coalesce(name, wa_id) into v_cust from public.customers where id = m.customer_id;
  for k in select * from public.quality_keywords where is_active loop
    if v_body like '% '||public.normalize_ar(k.phrase)||' %'
       or v_body like '%'||public.normalize_ar(k.phrase)||'%' then
      insert into public.quality_notes(employee_id,customer_id,customer_name,message_id,message_text,message_at,keyword_id,matched_phrase,label)
      values (m.employee_id, m.customer_id, v_cust, m.id, m.body, m.sent_at, k.id, k.phrase, k.label);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end; $$;

-- استقبال رسالة من Webhook (يُستدعى بـ service_role): يخزّن العميل+الرسالة ثم يفحص
create or replace function public.ingest_message(
  p_wa_message_id text, p_customer_wa text, p_customer_name text,
  p_direction text, p_body text, p_sent_at timestamptz, p_employee_id bigint, p_raw jsonb
) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_cid bigint; v_mid bigint; v_notes int;
begin
  insert into public.customers(wa_id,name) values (p_customer_wa, p_customer_name)
  on conflict (wa_id) do update set name=coalesce(excluded.name, public.customers.name)
  returning id into v_cid;
  insert into public.messages(wa_message_id,customer_id,employee_id,direction,body,sent_at,raw)
  values (p_wa_message_id, v_cid, p_employee_id, coalesce(p_direction,'inbound'), p_body, p_sent_at, p_raw)
  on conflict (wa_message_id) do nothing
  returning id into v_mid;
  if v_mid is null then return jsonb_build_object('ok',true,'duplicate',true); end if;
  v_notes := public.scan_message(v_mid);
  update public.meta_settings set last_event_at=now(), connection_status='connected' where id=1;
  return jsonb_build_object('ok',true,'message_id',v_mid,'notes',v_notes);
end; $$;

-- بيانات لوحة الجودة (نظرة عامة + الكلمات + الموظفون للفلاتر)
create or replace function public.get_quality_data(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  return jsonb_build_object('ok',true,
    'me', jsonb_build_object('id',s.user_id,'role',s.role,'name',s.full_name),
    'settings', (select value from public.settings where key='system'),
    'employees', coalesce((select jsonb_agg(jsonb_build_object('id',id,'full_name',full_name) order by full_name) from public.employees where is_active),'[]'::jsonb),
    'keywords', coalesce((select jsonb_agg(to_jsonb(k) order by k.id) from public.quality_keywords k),'[]'::jsonb),
    'stats', jsonb_build_object(
      'total', (select count(*) from public.quality_notes),
      'today', (select count(*) from public.quality_notes where message_at::date = current_date),
      'by_label', coalesce((select jsonb_object_agg(label, c) from (select coalesce(label,'-') label, count(*) c from public.quality_notes group by 1 order by 2 desc limit 8) t),'{}'::jsonb)
    ));
end; $$;

-- إدارة الكلمات
create or replace function public.upsert_keyword(p_session_token text, p_id bigint, p_phrase text, p_label text, p_is_active boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record; v_id bigint;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  if coalesce(trim(p_phrase),'')='' then return jsonb_build_object('ok',false,'message','العبارة مطلوبة'); end if;
  if p_id is null then
    insert into public.quality_keywords(phrase,label,is_active) values (trim(p_phrase),coalesce(nullif(trim(p_label),''),'ملاحظة جودة'),coalesce(p_is_active,true)) returning id into v_id;
  else
    update public.quality_keywords set phrase=trim(p_phrase), label=coalesce(nullif(trim(p_label),''),'ملاحظة جودة'), is_active=coalesce(p_is_active,true) where id=p_id returning id into v_id;
    if v_id is null then return jsonb_build_object('ok',false,'message','غير موجود'); end if;
  end if;
  perform public._audit(s.user_id,s.full_name,s.role,'upsert_keyword','keyword',v_id,p_phrase);
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function public.delete_keyword(p_session_token text, p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  delete from public.quality_keywords where id=p_id;
  perform public._audit(s.user_id,s.full_name,s.role,'delete_keyword','keyword',p_id,'حذف كلمة');
  return jsonb_build_object('ok',true);
end; $$;

-- قائمة الملاحظات مع فلترة وبحث
create or replace function public.get_quality_notes(
  p_session_token text, p_employee_id bigint default null, p_label text default null,
  p_from date default null, p_to date default null, p_search text default null
) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  return jsonb_build_object('ok',true,'items', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',n.id,'employee', e.full_name,'customer',n.customer_name,'text',n.message_text,
      'at',n.message_at,'label',n.label,'phrase',n.matched_phrase) order by n.message_at desc nulls last)
    from (select * from public.quality_notes n
          where (p_employee_id is null or n.employee_id=p_employee_id)
            and (p_label is null or n.label=p_label)
            and (p_from is null or n.message_at::date >= p_from)
            and (p_to is null or n.message_at::date <= p_to)
            and (p_search is null or n.message_text ilike '%'||p_search||'%' or n.customer_name ilike '%'||p_search||'%')
          order by n.message_at desc nulls last limit 500) n
    left join public.employees e on e.id=n.employee_id),'[]'::jsonb));
end; $$;

-- تقرير: تجميع حسب الموظف + النوع
create or replace function public.quality_report(p_session_token text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  return jsonb_build_object('ok',true,
    'by_employee', coalesce((select jsonb_agg(jsonb_build_object('employee',emp,'count',c) order by c desc) from (
        select coalesce(e.full_name,'غير محدد') emp, count(*) c from public.quality_notes n
        left join public.employees e on e.id=n.employee_id
        where (p_from is null or n.message_at::date>=p_from) and (p_to is null or n.message_at::date<=p_to)
        group by 1) t),'[]'::jsonb),
    'by_label', coalesce((select jsonb_agg(jsonb_build_object('label',lbl,'count',c) order by c desc) from (
        select coalesce(label,'-') lbl, count(*) c from public.quality_notes n
        where (p_from is null or n.message_at::date>=p_from) and (p_to is null or n.message_at::date<=p_to)
        group by 1) t),'[]'::jsonb));
end; $$;

-- إعدادات Meta: قراءة (بلا أسرار)
create or replace function public.get_meta_settings(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record; c public.meta_settings;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  select * into c from public.meta_settings where id=1;
  return jsonb_build_object('ok',true,'settings', jsonb_build_object(
    'app_id',c.app_id,'business_id',c.business_id,'waba_id',c.waba_id,'phone_number_id',c.phone_number_id,
    'verify_token',c.verify_token,'webhook_url',c.webhook_url,'connection_status',c.connection_status,
    'last_event_at',c.last_event_at,'last_error',c.last_error,
    'has_access_token', c.access_token_secret_id is not null,
    'has_app_secret', c.app_secret_secret_id is not null));
end; $$;

-- إعدادات Meta: حفظ (الأسرار في Vault؛ الفارغ=إبقاء)
create or replace function public.save_meta_settings(
  p_session_token text, p_app_id text, p_business_id text, p_waba_id text, p_phone_number_id text,
  p_verify_token text, p_webhook_url text, p_access_token text default null, p_app_secret text default null
) returns jsonb language plpgsql security definer set search_path to 'public, vault' as $$
declare s record; c public.meta_settings; v_id uuid;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  select * into c from public.meta_settings where id=1;
  update public.meta_settings set
    app_id=nullif(trim(coalesce(p_app_id,'')),''), business_id=nullif(trim(coalesce(p_business_id,'')),''),
    waba_id=nullif(trim(coalesce(p_waba_id,'')),''), phone_number_id=nullif(trim(coalesce(p_phone_number_id,'')),''),
    verify_token=nullif(trim(coalesce(p_verify_token,'')),''), webhook_url=nullif(trim(coalesce(p_webhook_url,'')),''),
    updated_at=now(), updated_by=s.user_id where id=1;
  if coalesce(trim(p_access_token),'')<>'' then
    if c.access_token_secret_id is null then select vault.create_secret(p_access_token,'meta_access_token') into v_id; update public.meta_settings set access_token_secret_id=v_id where id=1;
    else perform vault.update_secret(c.access_token_secret_id, p_access_token); end if;
  end if;
  if coalesce(trim(p_app_secret),'')<>'' then
    if c.app_secret_secret_id is null then select vault.create_secret(p_app_secret,'meta_app_secret') into v_id; update public.meta_settings set app_secret_secret_id=v_id where id=1;
    else perform vault.update_secret(c.app_secret_secret_id, p_app_secret); end if;
  end if;
  perform public._audit(s.user_id,s.full_name,s.role,'save_meta_settings','meta_settings',1,'تحديث إعدادات Meta');
  return jsonb_build_object('ok',true,'message','تم حفظ إعدادات الربط');
end; $$;

-- المنح (anon ينفّذ الدوال المُصادَقة؛ ingest/scan لا تُمنح لـ anon — تُستدعى بـ service_role)
do $$ declare f text; begin
  for f in select unnest(array[
    'get_quality_data(text)','upsert_keyword(text,bigint,text,text,boolean)','delete_keyword(text,bigint)',
    'get_quality_notes(text,bigint,text,date,date,text)','quality_report(text,date,date)',
    'get_meta_settings(text)','save_meta_settings(text,text,text,text,text,text,text,text,text)']) loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon', f);
  end loop;
end $$;
