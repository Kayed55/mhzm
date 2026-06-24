-- ============================================================
-- APPLY_ALL — الصق كاملاً في Supabase SQL Editor (بالترتيب)
-- ============================================================

-- ======================== db/01_schema.sql ========================
-- ============================================================================
-- مؤشر أداء موظفات المبيعات — مخطط قاعدة البيانات (Schema)
-- ============================================================================
-- مبدأ أمني محوري:
--   • المبالغ المالية تُخزَّن فقط في جداول محمية (sales_records / performance_logs).
--   • شاشة العرض العامة تقرأ النِّسب فقط عبر VIEW عام (live_display) بلا أي مبلغ.
--   • أسرار قيود تُخزَّن مشفّرة عبر Supabase Vault (لا نصّ واضح).
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- المصادقة والصلاحيات
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id            bigint primary key generated always as identity,
  username      varchar(100) unique not null,
  email         varchar(255) unique,
  password      text not null,                       -- bcrypt hash فقط
  full_name     varchar(255) not null,
  role          varchar(30) not null default 'team_leader'
                  check (role in ('admin','manager','team_leader')),
  is_active     boolean not null default true,
  must_change_password boolean not null default true,
  last_login_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.permissions (
  key         varchar(60) primary key,              -- مثل: manage_employees
  description text
);

create table if not exists public.role_permissions (
  role            varchar(30) not null,
  permission_key  varchar(60) not null references public.permissions(key) on delete cascade,
  primary key (role, permission_key)
);

create table if not exists public.sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      bigint not null references public.users(id) on delete cascade,
  role         varchar(30) not null,
  token        char(64) unique not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  last_used_at timestamptz not null default now()
);
create index if not exists idx_sessions_token on public.sessions(token);

-- ---------------------------------------------------------------------------
-- التيم ليدرز والموظفات
-- ---------------------------------------------------------------------------
create table if not exists public.team_leaders (
  id          bigint primary key generated always as identity,
  full_name   varchar(255) not null,
  user_id     bigint references public.users(id) on delete set null,  -- حساب الدخول (اختياري)
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.employees (
  id              bigint primary key generated always as identity,
  full_name       varchar(255) not null,
  employee_code   varchar(100) unique,                 -- الرقم الوظيفي الداخلي
  qoyod_ref       varchar(150),                        -- مُعرّف الموظفة في قيود (للربط)
  team_leader_id  bigint references public.team_leaders(id) on delete set null,
  show_in_display boolean not null default true,       -- الظهور في شاشة العرض
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_employees_tl on public.employees(team_leader_id);
create index if not exists idx_employees_qoyod on public.employees(qoyod_ref);

-- ---------------------------------------------------------------------------
-- الأهداف (لكل موظفة / تيم ليدر، لكل فترة)
-- ---------------------------------------------------------------------------
create table if not exists public.performance_targets (
  id             bigint primary key generated always as identity,
  scope          varchar(20) not null check (scope in ('employee','team_leader')),
  employee_id    bigint references public.employees(id) on delete cascade,
  team_leader_id bigint references public.team_leaders(id) on delete cascade,
  period_type    varchar(10) not null check (period_type in ('daily','weekly','monthly')),
  target_amount  numeric(14,2) not null check (target_amount >= 0),  -- محمي
  effective_from date not null default current_date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check ( (scope='employee' and employee_id is not null)
       or (scope='team_leader' and team_leader_id is not null) )
);
create index if not exists idx_targets_emp on public.performance_targets(employee_id, period_type);

-- ---------------------------------------------------------------------------
-- مبيعات قيود (محمي — يحوي المبالغ الفعلية، لا يصله anon)
-- ---------------------------------------------------------------------------
create table if not exists public.sales_records (
  id               bigint primary key generated always as identity,
  employee_id      bigint references public.employees(id) on delete cascade,
  qoyod_invoice_id varchar(150),                       -- لمنع التكرار
  amount           numeric(14,2) not null default 0,   -- محمي
  sale_date        date not null,
  raw              jsonb,                              -- استجابة قيود الخام (تدقيق)
  synced_at        timestamptz not null default now(),
  unique (qoyod_invoice_id)
);
create index if not exists idx_sales_emp_date on public.sales_records(employee_id, sale_date);

-- ---------------------------------------------------------------------------
-- لقطات الأداء المحسوبة (المبالغ محمية، النسبة هي المعروضة)
-- ---------------------------------------------------------------------------
create table if not exists public.performance_logs (
  id              bigint primary key generated always as identity,
  scope           varchar(20) not null check (scope in ('employee','team_leader')),
  employee_id     bigint references public.employees(id) on delete cascade,
  team_leader_id  bigint references public.team_leaders(id) on delete cascade,
  period_type     varchar(10) not null check (period_type in ('daily','weekly','monthly')),
  period_date     date not null,                      -- بداية الفترة
  achieved_amount numeric(14,2) not null default 0,   -- محمي
  target_amount   numeric(14,2) not null default 0,   -- محمي
  percentage      numeric(6,2) not null default 0,    -- عام (للعرض)
  status          varchar(30),                        -- ممتاز/جيد جدًا/...
  computed_at     timestamptz not null default now(),
  unique (scope, employee_id, team_leader_id, period_type, period_date)
);
create index if not exists idx_perf_lookup on public.performance_logs(scope, period_type, period_date);

-- ---------------------------------------------------------------------------
-- الإعدادات (صفّ JSONB واحد) + إعدادات قيود (الأسرار عبر Vault)
-- ---------------------------------------------------------------------------
create table if not exists public.settings (
  key         varchar(60) primary key,               -- 'system'
  value       jsonb not null default '{}'::jsonb,     -- الاسم/الشعار/الألوان/الحدود/الترتيب/فترة التحديث
  updated_at  timestamptz not null default now(),
  updated_by  bigint references public.users(id) on delete set null
);


-- سجل المزامنة والأخطاء
create table if not exists public.sync_logs (
  id              bigint primary key generated always as identity,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          varchar(20) not null default 'running'
                    check (status in ('running','success','error','partial')),
  records_synced  int not null default 0,
  message         text,
  triggered_by    varchar(20) not null default 'auto'   -- auto | manual
);
create index if not exists idx_sync_logs_time on public.sync_logs(started_at desc);

-- التدقيق
create table if not exists public.audit_logs (
  id          bigint primary key generated always as identity,
  user_id     bigint references public.users(id) on delete set null,
  user_name   varchar(255),
  role        varchar(30),
  action      varchar(60) not null,
  entity_type varchar(60),
  entity_id   bigint,
  details     text,
  ip_address  varchar(60),
  "timestamp" timestamptz not null default now()
);
create index if not exists idx_audit_time on public.audit_logs("timestamp" desc);

-- ---------------------------------------------------------------------------
-- VIEW عام لشاشة العرض — النِّسب فقط، بلا أي مبلغ مالي
-- ---------------------------------------------------------------------------
create or replace view public.live_display as
select
  e.id                as employee_id,
  e.full_name         as employee_name,
  tl.full_name        as team_leader_name,
  max(case when pl.period_type='daily'   then pl.percentage end) as daily_pct,
  max(case when pl.period_type='weekly'  then pl.percentage end) as weekly_pct,
  max(case when pl.period_type='monthly' then pl.percentage end) as monthly_pct,
  max(case when pl.period_type='monthly' then pl.status end)     as status
from public.employees e
left join public.team_leaders tl on tl.id = e.team_leader_id
left join public.performance_logs pl
  on pl.scope='employee' and pl.employee_id = e.id
  and pl.period_date = (case pl.period_type
                          when 'daily'   then current_date
                          when 'weekly'  then date_trunc('week', current_date)::date
                          when 'monthly' then date_trunc('month', current_date)::date end)
where e.is_active and e.show_in_display
group by e.id, e.full_name, tl.full_name;

-- ======================== db/02_security_rls.sql ========================
-- ============================================================================
-- الأمان: RLS + الصلاحيات (نموذج أصفر-ثقة من البداية)
-- ============================================================================
-- • anon (عام): يقرأ live_display فقط (نِسب) — لا يصل لأي جدول فيه مبالغ.
-- • لوحة التحكم: كل قراءة/كتابة عبر RPCs بـ SECURITY DEFINER تتحقّق من
--   رمز الجلسة + الدور (anon لا يقرأ الجداول مباشرة).
-- • Edge Functions تستخدم service_role (تتجاوز RLS) لمزامنة قيود.
-- ============================================================================

-- تفعيل RLS على كل الجداول (رفض افتراضي — لا سياسات لـ anon)
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- سحب كل وصول مباشر عن anon/authenticated من الجداول (الوصول عبر RPC/Vault فقط)
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- شاشة العرض العامة: anon يقرأ النِّسب فقط عبر الـ VIEW (يعمل بصلاحيات المالك)
grant select on public.live_display to anon;

-- ملاحظة: كل دوال RPC (تسجيل الدخول، قراءة اللوحة، الإدارة) تُمنح
-- execute لـ anon داخل ملفات الدوال نفسها (db/04_rpc_*.sql)، وكلها
-- SECURITY DEFINER + verify_session داخلها.

-- ======================== db/03_seed.sql ========================
-- ============================================================================
-- البذور: الصلاحيات + مدير افتراضي + الإعدادات الافتراضية
-- ============================================================================

insert into public.permissions(key, description) values
  ('manage_users','إدارة المستخدمين والأدوار'),
  ('manage_employees','إدارة الموظفات'),
  ('manage_team_leaders','إدارة التيم ليدرز'),
  ('manage_targets','إدارة الأهداف'),
  ('manage_settings','إعدادات النظام'),
  ('manage_qoyod','إعدادات قيود والمزامنة'),
  ('view_reports','عرض التقارير'),
  ('view_all','عرض كل البيانات'),
  ('view_own_team','عرض الفريق التابع فقط')
on conflict (key) do nothing;

-- خريطة الأدوار → الصلاحيات
insert into public.role_permissions(role, permission_key) values
  ('admin','manage_users'),('admin','manage_employees'),('admin','manage_team_leaders'),
  ('admin','manage_targets'),('admin','manage_settings'),('admin','manage_qoyod'),
  ('admin','view_reports'),('admin','view_all'),
  ('manager','view_all'),('manager','view_reports'),
  ('team_leader','view_own_team'),('team_leader','view_reports')
on conflict do nothing;

-- مدير افتراضي (كلمة المرور مجزّأة bcrypt) — غيّرها بعد أول دخول
insert into public.users(username, email, password, full_name, role, is_active, must_change_password)
values ('admin','admin@example.com',
        extensions.crypt('Admin@123', extensions.gen_salt('bf',10)),
        'مدير النظام','admin', true, true)
on conflict (username) do nothing;

-- الإعدادات الافتراضية (الاسم/الألوان/حدود الحالات/الترتيب/فترة التحديث)
insert into public.settings(key, value) values
('system', jsonb_build_object(
  'system_name','مؤشر أداء موظفات المبيعات',
  'logo_url','',
  'refresh_seconds', 20,
  'display_order','monthly_desc',         -- ترتيب شاشة العرض
  'status_thresholds', jsonb_build_array(
    jsonb_build_object('label','ممتاز','min',100,'color','#16a34a'),
    jsonb_build_object('label','جيد جدًا','min',85,'color','#0ea5e9'),
    jsonb_build_object('label','جيد','min',70,'color','#3b82f6'),
    jsonb_build_object('label','يحتاج متابعة','min',50,'color','#f59e0b'),
    jsonb_build_object('label','ضعيف','min',0,'color','#ef4444')
  )
))
on conflict (key) do nothing;

-- ======================== db/04_auth.sql ========================
-- ============================================================================
-- المصادقة: verify_session (تُستخدم داخل كل RPC) + verify_login + logout
-- ============================================================================
-- نموذج الجلسات: رمز 64-hex، صلاحية 7 أيام. الهوية تُشتقّ من الرمز على الخادم.
-- كلمات المرور bcrypt (extensions.crypt). pgcrypto في schema extensions.
-- ============================================================================

-- التحقّق من رمز الجلسة → يُرجع صلاحيتها + هوية المستخدم ودوره
create or replace function public.verify_session(p_token text)
returns table(is_valid boolean, user_id bigint, role text, full_name text)
language plpgsql security definer set search_path to 'public'
as $$
declare s public.sessions; u public.users;
begin
  if p_token is null or length(p_token) < 32 then
    return query select false, null::bigint, null::text, null::text; return;
  end if;
  select * into s from public.sessions where token = p_token and expires_at > now();
  if s.id is null then return query select false, null::bigint, null::text, null::text; return; end if;
  select * into u from public.users where id = s.user_id and is_active;
  if u.id is null then return query select false, null::bigint, null::text, null::text; return; end if;
  update public.sessions set last_used_at = now() where id = s.id;
  return query select true, u.id, u.role::text, u.full_name::text;
end; $$;

-- تسجيل الدخول: تحقّق bcrypt → إنشاء جلسة → إرجاع الرمز + الهوية
create or replace function public.login(p_username text, p_password text)
returns table(ok boolean, token text, user_id bigint, role text, full_name text, must_change_password boolean, message text)
language plpgsql security definer set search_path to 'public'
as $$
declare u public.users; v_token text;
begin
  if coalesce(trim(p_username),'')='' or coalesce(p_password,'')='' then
    return query select false,null::text,null::bigint,null::text,null::text,null::boolean,'اسم المستخدم وكلمة المرور مطلوبان'::text; return;
  end if;
  select * into u from public.users
   where (lower(username)=lower(trim(p_username)) or lower(email)=lower(trim(p_username))) and is_active
   limit 1;
  if u.id is null or u.password is null or u.password <> extensions.crypt(p_password, u.password) then
    return query select false,null::text,null::bigint,null::text,null::text,null::boolean,'بيانات الدخول غير صحيحة'::text; return;
  end if;
  v_token := encode(extensions.gen_random_bytes(32),'hex');
  insert into public.sessions(user_id, role, token, expires_at)
  values (u.id, u.role, v_token, now() + interval '7 days');
  update public.users set last_login_at = now() where id = u.id;
  insert into public.audit_logs(user_id,user_name,role,action,entity_type,entity_id,details)
  values (u.id, u.full_name, u.role, 'login','user',u.id,'تسجيل دخول');
  return query select true, v_token, u.id, u.role::text, u.full_name::text, u.must_change_password, 'تم تسجيل الدخول'::text;
end; $$;

-- تسجيل الخروج (إبطال الجلسة)
create or replace function public.logout(p_token text)
returns boolean language plpgsql security definer set search_path to 'public'
as $$
begin
  delete from public.sessions where token = p_token;
  return true;
end; $$;

-- المنح: anon ينفّذ دوال المصادقة فقط
revoke all on function public.verify_session(text) from public;
revoke all on function public.login(text,text) from public;
revoke all on function public.logout(text) from public;
grant execute on function public.login(text,text) to anon;
grant execute on function public.logout(text) to anon;
-- verify_session تُستدعى داخلياً من الدوال الأخرى (لا تُمنح لـ anon مباشرة)

-- ======================== db/05_rpc_core.sql ========================
-- ============================================================================
-- دوال لوحة التحكم (RPCs) — قراءة + CRUD، كلها SECURITY DEFINER + verify_session
-- ============================================================================
-- anon يصل الجداول فقط عبر هذه الدوال (لا قراءة مباشرة). الدور يُشتقّ من الرمز.
-- ============================================================================

-- مساعد داخلي: تدقيق
create or replace function public._audit(p_uid bigint, p_name text, p_role text, p_action text, p_etype text, p_eid bigint, p_details text)
returns void language sql security definer set search_path to 'public' as $$
  insert into public.audit_logs(user_id,user_name,role,action,entity_type,entity_id,details)
  values (p_uid,p_name,p_role,p_action,p_etype,p_eid,p_details);
$$;

-- ---------------------------------------------------------------------------
-- قراءة بيانات اللوحة (مفلترة حسب الدور)
-- ---------------------------------------------------------------------------
create or replace function public.get_app_data(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record; v_tl_id bigint; result jsonb;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;

  -- team_leader: يرى فريقه فقط
  if s.role = 'team_leader' then
    select id into v_tl_id from public.team_leaders where user_id = s.user_id limit 1;
  end if;

  result := jsonb_build_object(
    'ok', true,
    'me', jsonb_build_object('id',s.user_id,'role',s.role,'name',s.full_name,'team_leader_id',v_tl_id),
    'settings', (select value from public.settings where key='system'),
    'team_leaders', coalesce((select jsonb_agg(to_jsonb(t) order by t.full_name)
        from public.team_leaders t
        where s.role in ('admin','manager') or t.id = v_tl_id), '[]'::jsonb),
    'employees', coalesce((select jsonb_agg(to_jsonb(e) order by e.full_name)
        from public.employees e
        where s.role in ('admin','manager') or e.team_leader_id = v_tl_id), '[]'::jsonb),
    'targets', coalesce((select jsonb_agg(to_jsonb(pt))
        from public.performance_targets pt
        where s.role in ('admin','manager')
           or pt.employee_id in (select id from public.employees where team_leader_id = v_tl_id)
           or pt.team_leader_id = v_tl_id), '[]'::jsonb),
    'performance', coalesce((select jsonb_agg(jsonb_build_object(
          'scope',pl.scope,'employee_id',pl.employee_id,'team_leader_id',pl.team_leader_id,
          'period_type',pl.period_type,'period_date',pl.period_date,'percentage',pl.percentage,'status',pl.status))
        from public.performance_logs pl
        where s.role in ('admin','manager')
           or pl.employee_id in (select id from public.employees where team_leader_id = v_tl_id)
           or pl.team_leader_id = v_tl_id), '[]'::jsonb)
  );
  return result;
end; $$;

-- ---------------------------------------------------------------------------
-- الموظفات: إضافة/تعديل + حذف
-- ---------------------------------------------------------------------------
create or replace function public.upsert_employee(
  p_session_token text, p_id bigint, p_full_name text, p_employee_code text default null,
  p_qoyod_ref text default null, p_team_leader_id bigint default null,
  p_show_in_display boolean default true, p_is_active boolean default true
) returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record; v_id bigint;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  if coalesce(trim(p_full_name),'')='' then return jsonb_build_object('ok',false,'message','الاسم مطلوب'); end if;

  if p_id is null then
    insert into public.employees(full_name,employee_code,qoyod_ref,team_leader_id,show_in_display,is_active)
    values (p_full_name,nullif(p_employee_code,''),nullif(p_qoyod_ref,''),p_team_leader_id,p_show_in_display,p_is_active)
    returning id into v_id;
    perform public._audit(s.user_id,s.full_name,s.role,'create_employee','employee',v_id,'إضافة موظفة: '||p_full_name);
  else
    update public.employees set full_name=p_full_name, employee_code=nullif(p_employee_code,''),
      qoyod_ref=nullif(p_qoyod_ref,''), team_leader_id=p_team_leader_id,
      show_in_display=p_show_in_display, is_active=p_is_active, updated_at=now()
    where id=p_id returning id into v_id;
    if v_id is null then return jsonb_build_object('ok',false,'message','الموظفة غير موجودة'); end if;
    perform public._audit(s.user_id,s.full_name,s.role,'update_employee','employee',v_id,'تعديل موظفة: '||p_full_name);
  end if;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function public.delete_employee(p_session_token text, p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  delete from public.employees where id=p_id;
  perform public._audit(s.user_id,s.full_name,s.role,'delete_employee','employee',p_id,'حذف موظفة #'||p_id);
  return jsonb_build_object('ok',true);
end; $$;

-- ---------------------------------------------------------------------------
-- التيم ليدرز: إضافة/تعديل + حذف
-- ---------------------------------------------------------------------------
create or replace function public.upsert_team_leader(
  p_session_token text, p_id bigint, p_full_name text, p_user_id bigint default null, p_is_active boolean default true
) returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record; v_id bigint;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  if coalesce(trim(p_full_name),'')='' then return jsonb_build_object('ok',false,'message','الاسم مطلوب'); end if;
  if p_id is null then
    insert into public.team_leaders(full_name,user_id,is_active) values (p_full_name,p_user_id,p_is_active) returning id into v_id;
    perform public._audit(s.user_id,s.full_name,s.role,'create_team_leader','team_leader',v_id,'إضافة تيم ليدر: '||p_full_name);
  else
    update public.team_leaders set full_name=p_full_name, user_id=p_user_id, is_active=p_is_active, updated_at=now()
    where id=p_id returning id into v_id;
    if v_id is null then return jsonb_build_object('ok',false,'message','غير موجود'); end if;
    perform public._audit(s.user_id,s.full_name,s.role,'update_team_leader','team_leader',v_id,'تعديل تيم ليدر: '||p_full_name);
  end if;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function public.delete_team_leader(p_session_token text, p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  delete from public.team_leaders where id=p_id;
  perform public._audit(s.user_id,s.full_name,s.role,'delete_team_leader','team_leader',p_id,'حذف تيم ليدر #'||p_id);
  return jsonb_build_object('ok',true);
end; $$;

-- ---------------------------------------------------------------------------
-- الأهداف: ضبط هدف (employee/team_leader, period)
-- ---------------------------------------------------------------------------
create or replace function public.set_target(
  p_session_token text, p_scope text, p_employee_id bigint, p_team_leader_id bigint,
  p_period_type text, p_target_amount numeric
) returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record; v_id bigint;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  if p_scope not in ('employee','team_leader') then return jsonb_build_object('ok',false,'message','نطاق غير صالح'); end if;
  if p_period_type not in ('daily','weekly','monthly') then return jsonb_build_object('ok',false,'message','فترة غير صالحة'); end if;
  if coalesce(p_target_amount,-1) < 0 then return jsonb_build_object('ok',false,'message','الهدف يجب أن يكون رقماً موجباً'); end if;

  -- استبدال هدف الفترة الحالي لنفس النطاق (تبسيط: هدف واحد فعّال لكل فترة)
  delete from public.performance_targets
   where period_type=p_period_type and scope=p_scope
     and employee_id is not distinct from p_employee_id
     and team_leader_id is not distinct from p_team_leader_id;
  insert into public.performance_targets(scope,employee_id,team_leader_id,period_type,target_amount)
  values (p_scope,p_employee_id,p_team_leader_id,p_period_type,p_target_amount) returning id into v_id;
  perform public._audit(s.user_id,s.full_name,s.role,'set_target','target',v_id,p_scope||'/'||p_period_type||'='||p_target_amount);
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

-- ---------------------------------------------------------------------------
-- الإعدادات: تحديث الإعدادات العامة (JSONB)
-- ---------------------------------------------------------------------------
create or replace function public.update_settings(p_session_token text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  if p_value is null or jsonb_typeof(p_value) <> 'object' then return jsonb_build_object('ok',false,'message','بنية غير صالحة'); end if;
  insert into public.settings(key,value,updated_at,updated_by) values ('system',p_value,now(),s.user_id)
  on conflict (key) do update set value=excluded.value, updated_at=now(), updated_by=s.user_id;
  perform public._audit(s.user_id,s.full_name,s.role,'update_settings','settings',null,'تحديث الإعدادات');
  return jsonb_build_object('ok',true);
end; $$;

-- المنح: anon ينفّذ هذه الدوال (التحقّق داخلها)
do $$ declare f text; begin
  for f in select unnest(array[
    'get_app_data(text)','upsert_employee(text,bigint,text,text,text,bigint,boolean,boolean)',
    'delete_employee(text,bigint)','upsert_team_leader(text,bigint,text,bigint,boolean)',
    'delete_team_leader(text,bigint)','set_target(text,text,bigint,bigint,text,numeric)',
    'update_settings(text,jsonb)']) loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon', f);
  end loop;
end $$;

-- ======================== db/06_users_live.sql ========================
-- ============================================================================
-- إدارة المستخدمين + تغيير كلمة المرور + إعدادات عامة لشاشة العرض
-- ============================================================================

-- إعدادات عامة آمنة لشاشة العرض (بلا أسرار) — anon
create or replace function public.get_public_settings()
returns jsonb language sql security definer set search_path to 'public' stable as $$
  select jsonb_build_object(
    'system_name', coalesce(value->>'system_name','مؤشر أداء موظفات المبيعات'),
    'logo_url',    coalesce(value->>'logo_url',''),
    'refresh_seconds', coalesce((value->>'refresh_seconds')::int, 20),
    'status_thresholds', coalesce(value->'status_thresholds','[]'::jsonb)
  ) from public.settings where key='system';
$$;

-- قائمة المستخدمين (بلا كلمة المرور) — admin
create or replace function public.get_users(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  return jsonb_build_object('ok',true,'users', coalesce((select jsonb_agg(jsonb_build_object(
     'id',id,'username',username,'email',email,'full_name',full_name,'role',role,
     'is_active',is_active,'last_login_at',last_login_at) order by id) from public.users),'[]'::jsonb));
end; $$;

-- إضافة/تعديل مستخدم — admin (الدور: admin/manager/team_leader)
create or replace function public.upsert_user(
  p_session_token text, p_id bigint, p_username text, p_email text, p_full_name text,
  p_role text, p_is_active boolean default true, p_password text default null
) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record; v_id bigint;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  if coalesce(trim(p_username),'')='' or coalesce(trim(p_full_name),'')='' then return jsonb_build_object('ok',false,'message','الاسم واسم المستخدم مطلوبان'); end if;
  if p_role not in ('admin','manager','team_leader') then return jsonb_build_object('ok',false,'message','دور غير صالح'); end if;

  if p_id is null then
    if coalesce(p_password,'')='' then return jsonb_build_object('ok',false,'message','كلمة المرور مطلوبة للمستخدم الجديد'); end if;
    if exists(select 1 from public.users where lower(username)=lower(p_username)) then return jsonb_build_object('ok',false,'message','اسم المستخدم مستخدم مسبقاً'); end if;
    insert into public.users(username,email,password,full_name,role,is_active,must_change_password)
    values (p_username, nullif(p_email,''), extensions.crypt(p_password, extensions.gen_salt('bf',10)), p_full_name, p_role, p_is_active, true)
    returning id into v_id;
    perform public._audit(s.user_id,s.full_name,s.role,'create_user','user',v_id,'إنشاء مستخدم: '||p_username||' ('||p_role||')');
  else
    update public.users set username=p_username, email=nullif(p_email,''), full_name=p_full_name,
      role=p_role, is_active=p_is_active,
      password=case when coalesce(p_password,'')<>'' then extensions.crypt(p_password, extensions.gen_salt('bf',10)) else password end,
      updated_at=now()
    where id=p_id returning id into v_id;
    if v_id is null then return jsonb_build_object('ok',false,'message','المستخدم غير موجود'); end if;
    perform public._audit(s.user_id,s.full_name,s.role,'update_user','user',v_id,'تعديل مستخدم: '||p_username);
  end if;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

-- حذف مستخدم — admin (لا يحذف نفسه ولا آخر admin)
create or replace function public.delete_user(p_session_token text, p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record; v_role text; v_admins int;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  if p_id = s.user_id then return jsonb_build_object('ok',false,'message','لا يمكنك حذف حسابك'); end if;
  select role into v_role from public.users where id=p_id;
  if v_role = 'admin' then
    select count(*) into v_admins from public.users where role='admin' and is_active;
    if v_admins <= 1 then return jsonb_build_object('ok',false,'message','لا يمكن حذف آخر مدير'); end if;
  end if;
  delete from public.users where id=p_id;
  perform public._audit(s.user_id,s.full_name,s.role,'delete_user','user',p_id,'حذف مستخدم #'||p_id);
  return jsonb_build_object('ok',true);
end; $$;

-- تغيير كلمة المرور الشخصية — أي مستخدم
create or replace function public.change_my_password(p_session_token text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record; u public.users;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if coalesce(p_new,'')='' or length(p_new) < 6 then return jsonb_build_object('ok',false,'message','كلمة المرور الجديدة 6 أحرف على الأقل'); end if;
  select * into u from public.users where id=s.user_id;
  if u.password <> extensions.crypt(p_old, u.password) then return jsonb_build_object('ok',false,'message','كلمة المرور الحالية غير صحيحة'); end if;
  update public.users set password=extensions.crypt(p_new, extensions.gen_salt('bf',10)), must_change_password=false, updated_at=now() where id=s.user_id;
  perform public._audit(s.user_id,s.full_name,s.role,'change_password','user',s.user_id,'تغيير كلمة المرور');
  return jsonb_build_object('ok',true,'message','تم تغيير كلمة المرور');
end; $$;

-- المنح
do $$ declare f text; begin
  for f in select unnest(array[
    'get_public_settings()','get_users(text)',
    'upsert_user(text,bigint,text,text,text,text,boolean,text)',
    'delete_user(text,bigint)','change_my_password(text,text,text)']) loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon', f);
  end loop;
end $$;

-- ======================== db/08_matching_performance.sql ========================
-- ============================================================================
-- مطابقة أسماء الموظفات + احتساب الأداء (عام، مستقل عن مصدر البيانات)
-- ============================================================================
-- يُغذّى sales_records من مصدر الربط (يُحدَّد لاحقاً). هذه الدوال تحوّل المبيعات
-- إلى نِسب أداء وتطابق الأسماء بمرونة.
-- ============================================================================

-- تطبيع عربي للمطابقة: إزالة HTML/التشكيل/"ال" التعريف/توحيد الألف والهاء والياء + ضغط الفراغات
create or replace function public.normalize_ar(t text)
returns text language sql immutable as $$
  with a as (select lower(regexp_replace(regexp_replace(coalesce(t,''),'<[^>]+>',' ','g'),'&nbsp;',' ','g')) s),
  b as (select regexp_replace(
      replace(replace(replace(replace(replace(replace(replace(replace(
        (select s from a),'أ','ا'),'إ','ا'),'آ','ا'),'ٱ','ا'),'ة','ه'),'ى','ي'),'ؤ','و'),'ئ','ي')
      ,'[ًٌٍَُِّْـ]','','g') s),
  c as (select regexp_replace((select s from b),'(^|\s)ال','\1','g') s)
  select trim(regexp_replace((select s from c),'\s+',' ','g'));
$$;

-- مطابقة تلقائية بالاسم المسجّل للموظفة (qoyod_ref إن وُجد، وإلا full_name):
-- تطابق إن ظهر الاسمان الأول والأخير ككلمتين داخل النصّ.
create or replace function public.match_employee_from_notes(p_notes text)
returns bigint language plpgsql stable as $$
declare v_n text; e record; v_first text; v_last text; v_toks text[];
begin
  v_n := ' ' || public.normalize_ar(p_notes) || ' ';
  if length(trim(v_n)) <= 1 then return null; end if;
  for e in select id, coalesce(nullif(trim(qoyod_ref),''), full_name) as nm
           from public.employees where is_active and coalesce(nullif(trim(qoyod_ref),''), full_name) is not null loop
    v_toks := array(select t from unnest(string_to_array(public.normalize_ar(e.nm),' ')) t where length(t)>=2);
    if array_length(v_toks,1) is null then continue; end if;
    v_first := v_toks[1]; v_last := v_toks[array_upper(v_toks,1)];
    if v_n like '% '||v_first||' %' and v_n like '% '||v_last||' %' then
      return e.id;
    end if;
  end loop;
  return null;
end; $$;

-- حالة الأداء حسب حدود الإعدادات
create or replace function public.status_label(p_pct numeric)
returns text language sql stable as $$
  select coalesce((
    select b->>'label' from jsonb_array_elements(
      (select coalesce(value->'status_thresholds','[]'::jsonb) from public.settings where key='system')) b
    where p_pct >= (b->>'min')::numeric order by (b->>'min')::numeric desc limit 1
  ),'—');
$$;

-- احتساب الأداء: يجمع المبيعات في performance_logs (موظفات + تيم ليدرز) للفترات الحالية
create or replace function public.recompute_performance()
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_day date := current_date;
        v_week date := date_trunc('week', current_date)::date;
        v_month date := date_trunc('month', current_date)::date;
begin
  insert into public.performance_logs(scope,employee_id,team_leader_id,period_type,period_date,achieved_amount,target_amount,percentage,status,computed_at)
  select 'employee', e.id, null, p.ptype, p.pdate,
         coalesce(sa.amt,0), coalesce(t.target_amount,0),
         case when coalesce(t.target_amount,0)>0 then round(coalesce(sa.amt,0)/t.target_amount*100,2) else 0 end,
         status_label(case when coalesce(t.target_amount,0)>0 then coalesce(sa.amt,0)/t.target_amount*100 else 0 end),
         now()
  from public.employees e
  cross join (values ('daily'::text,v_day),('weekly',v_week),('monthly',v_month)) p(ptype,pdate)
  left join lateral (
     select sum(amount) amt from public.sales_records s
     where s.employee_id=e.id and s.sale_date >= p.pdate
       and s.sale_date < (case p.ptype when 'daily' then p.pdate+1 when 'weekly' then p.pdate+7 else (p.pdate+interval '1 month')::date end)
  ) sa on true
  left join public.performance_targets t on t.scope='employee' and t.employee_id=e.id and t.period_type=p.ptype
  where e.is_active
  on conflict (scope,employee_id,team_leader_id,period_type,period_date)
  do update set achieved_amount=excluded.achieved_amount, target_amount=excluded.target_amount,
                percentage=excluded.percentage, status=excluded.status, computed_at=now();

  insert into public.performance_logs(scope,employee_id,team_leader_id,period_type,period_date,achieved_amount,target_amount,percentage,status,computed_at)
  select 'team_leader', null, tl.id, p.ptype, p.pdate,
         coalesce(sa.amt,0), coalesce(t.target_amount,0),
         case when coalesce(t.target_amount,0)>0 then round(coalesce(sa.amt,0)/t.target_amount*100,2) else 0 end,
         status_label(case when coalesce(t.target_amount,0)>0 then coalesce(sa.amt,0)/t.target_amount*100 else 0 end),
         now()
  from public.team_leaders tl
  cross join (values ('daily'::text,v_day),('weekly',v_week),('monthly',v_month)) p(ptype,pdate)
  left join lateral (
     select sum(s.amount) amt from public.sales_records s join public.employees e on e.id=s.employee_id
     where e.team_leader_id=tl.id and s.sale_date >= p.pdate
       and s.sale_date < (case p.ptype when 'daily' then p.pdate+1 when 'weekly' then p.pdate+7 else (p.pdate+interval '1 month')::date end)
  ) sa on true
  left join public.performance_targets t on t.scope='team_leader' and t.team_leader_id=tl.id and t.period_type=p.ptype
  where tl.is_active
  on conflict (scope,employee_id,team_leader_id,period_type,period_date)
  do update set achieved_amount=excluded.achieved_amount, target_amount=excluded.target_amount,
                percentage=excluded.percentage, status=excluded.status, computed_at=now();
end; $$;

-- ======================== db/09_review.sql ========================
-- ============================================================================
-- "يحتاج مراجعة": عرض المبيعات غير المطابقة + إسنادها يدوياً لموظفة
-- ============================================================================

create or replace function public.get_unmatched(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role not in ('admin','manager') then return jsonb_build_object('ok',false,'message','ليس لديك صلاحية'); end if;
  return jsonb_build_object('ok',true,
    'count', (select count(*) from public.sales_records where employee_id is null),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'amount',amount,'sale_date',sale_date,
        'reference',raw->>'reference','notes',raw->>'notes') order by sale_date desc)
      from (select * from public.sales_records where employee_id is null order by sale_date desc limit 200) t),'[]'::jsonb));
end; $$;

create or replace function public.assign_sale(p_session_token text, p_sale_id bigint, p_employee_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  update public.sales_records set employee_id=p_employee_id where id=p_sale_id;
  perform public._audit(s.user_id,s.full_name,s.role,'assign_sale','sales_record',p_sale_id,'إسناد مبيعة لموظفة #'||p_employee_id);
  perform public.recompute_performance();
  return jsonb_build_object('ok',true);
end; $$;

revoke all on function public.get_unmatched(text) from public;
revoke all on function public.assign_sale(text,bigint,bigint) from public;
grant execute on function public.get_unmatched(text) to anon;
grant execute on function public.assign_sale(text,bigint,bigint) to anon;
