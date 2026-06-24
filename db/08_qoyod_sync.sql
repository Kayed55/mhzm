-- ============================================================================
-- محرّك مزامنة قيود (داخل القاعدة عبر امتداد http) + تطبيع/مطابقة + احتساب الأداء
-- ============================================================================
-- المصدر: عروض الأسعار legacy.qoyod.com/api/2.0/quotes (API-KEY من Vault).
-- المبلغ=total_amount، التاريخ=issue_date، اسم الموظفة من notes (نصّ حرّ).
-- المطابقة متسامحة (تطبيع عربي). غير المطابق → employee_id=null (يحتاج مراجعة).
-- ============================================================================

create extension if not exists http with schema extensions;

-- تطبيع عربي للمطابقة: إزالة HTML/التشكيل/"ال" التعريف/توحيد الألف والهاء والياء + ضغط الفراغات
create or replace function public.normalize_ar(t text)
returns text language sql immutable as $$
  with a as (select lower(regexp_replace(regexp_replace(coalesce(t,''),'<[^>]+>',' ','g'),'&nbsp;',' ','g')) s),
  b as (select regexp_replace(
      replace(replace(replace(replace(replace(replace(replace(replace(
        (select s from a),'أ','ا'),'إ','ا'),'آ','ا'),'ٱ','ا'),'ة','ه'),'ى','ي'),'ؤ','و'),'ئ','ي')
      ,'[ًٌٍَُِّْـ]','','g') s),
  c as (select regexp_replace((select s from b),'(^|\s)ال','\1','g') s)  -- إزالة "ال" التعريف بداية كل كلمة
  select trim(regexp_replace((select s from c),'\s+',' ','g'));
$$;

-- مطابقة موظفة من نصّ notes: تطابق إن ظهر الاسمان (الأول والأخير من qoyod_ref) كلمتين في النصّ
create or replace function public.match_employee_from_notes(p_notes text)
returns bigint language plpgsql stable as $$
declare v_n text; e record; v_first text; v_last text; v_toks text[];
begin
  v_n := ' ' || public.normalize_ar(p_notes) || ' ';
  if length(trim(v_n)) = 0 then return null; end if;
  for e in select id, qoyod_ref from public.employees where is_active and coalesce(trim(qoyod_ref),'')<>'' loop
    v_toks := string_to_array(public.normalize_ar(e.qoyod_ref),' ');
    v_toks := array(select t from unnest(v_toks) t where length(t)>=2);
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

-- احتساب الأداء: يجمع المبيعات المطابقة في performance_logs (موظفات + تيم ليدرز) للفترات الحالية
create or replace function public.recompute_performance()
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_day date := current_date;
        v_week date := date_trunc('week', current_date)::date;
        v_month date := date_trunc('month', current_date)::date;
begin
  -- موظفات
  insert into public.performance_logs(scope,employee_id,team_leader_id,period_type,period_date,achieved_amount,target_amount,percentage,status,computed_at)
  select 'employee', e.id, null, p.ptype, p.pdate,
         coalesce(sa.amt,0),
         coalesce(t.target_amount,0),
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

  -- تيم ليدرز (مجموع موظفاتهم مقابل هدف التيم ليدر)
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

-- اختبار الاتصال بقيود
create or replace function public.test_qoyod(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public, extensions, vault' as $$
declare s record; v_key text; v_resp extensions.http_response;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name='qoyod_api_key';
  if v_key is null then return jsonb_build_object('ok',false,'message','لم يُحفظ API Key'); end if;
  begin
    select * into v_resp from extensions.http((
      'GET','https://legacy.qoyod.com/api/2.0/quotes?page=1',
      array[extensions.http_header('API-KEY',v_key), extensions.http_header('Accept','application/json')],
      null,null)::extensions.http_request);
  exception when others then
    update public.qoyod_settings set connection_status='error', last_error=sqlerrm where id=1;
    return jsonb_build_object('ok',false,'message','فشل الاتصال: '||sqlerrm);
  end;
  if v_resp.status = 200 then
    update public.qoyod_settings set connection_status='connected', last_error=null where id=1;
    return jsonb_build_object('ok',true,'message','الاتصال ناجح ✓','count', jsonb_array_length((v_resp.content::jsonb)->'quote'));
  else
    update public.qoyod_settings set connection_status='error', last_error='HTTP '||v_resp.status where id=1;
    return jsonb_build_object('ok',false,'message','HTTP '||v_resp.status);
  end if;
end; $$;

-- المزامنة: تسحب العروض منذ تاريخ، تخزّنها (مطابِقة)، تعيد الاحتساب
create or replace function public.sync_qoyod(p_session_token text, p_since date default null)
returns jsonb language plpgsql security definer set search_path to 'public, extensions, vault' as $$
declare s record; v_key text; v_since date; v_page int := 1; v_resp extensions.http_response;
        v_arr jsonb; v_q jsonb; v_cnt int := 0; v_total int := 0; v_log_id bigint; v_url text;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','للمدير فقط'); end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name='qoyod_api_key';
  if v_key is null then return jsonb_build_object('ok',false,'message','لم يُحفظ API Key'); end if;

  v_since := coalesce(p_since, (select last_sync_at::date from public.qoyod_settings where id=1), current_date - 30);
  insert into public.sync_logs(status,triggered_by) values ('running','manual') returning id into v_log_id;

  loop
    v_url := 'https://legacy.qoyod.com/api/2.0/quotes?q%5Bissue_date_gteq%5D='||v_since||'&page='||v_page;
    begin
      select * into v_resp from extensions.http((
        'GET', v_url,
        array[extensions.http_header('API-KEY',v_key), extensions.http_header('Accept','application/json')],
        null,null)::extensions.http_request);
    exception when others then
      update public.sync_logs set status='error', finished_at=now(), message='HTTP خطأ: '||sqlerrm, records_synced=v_total where id=v_log_id;
      update public.qoyod_settings set connection_status='error', last_error=sqlerrm where id=1;
      return jsonb_build_object('ok',false,'message','فشل أثناء السحب: '||sqlerrm);
    end;
    if v_resp.status <> 200 then
      update public.sync_logs set status='error', finished_at=now(), message='HTTP '||v_resp.status, records_synced=v_total where id=v_log_id;
      return jsonb_build_object('ok',false,'message','HTTP '||v_resp.status);
    end if;
    v_arr := (v_resp.content::jsonb)->'quote';
    v_cnt := coalesce(jsonb_array_length(v_arr),0);
    exit when v_cnt = 0;

    for v_q in select * from jsonb_array_elements(v_arr) loop
      insert into public.sales_records(employee_id, qoyod_invoice_id, amount, sale_date, raw, synced_at)
      values (
        public.match_employee_from_notes(v_q->>'notes'),
        'QTE-'||(v_q->>'id'),
        coalesce((v_q->>'total_amount')::numeric,0),
        (v_q->>'issue_date')::date,
        jsonb_build_object('id',v_q->>'id','reference',v_q->>'reference','notes',v_q->>'notes','status',v_q->>'status'),
        now())
      on conflict (qoyod_invoice_id) do update set
        employee_id=public.match_employee_from_notes(excluded.raw->>'notes'),
        amount=excluded.amount, sale_date=excluded.sale_date, raw=excluded.raw, synced_at=now();
      v_total := v_total + 1;
    end loop;

    exit when v_cnt < 100;          -- آخر صفحة
    v_page := v_page + 1;
    exit when v_page > 60;          -- سقف أمان (6000 عرض/تشغيل)
  end loop;

  perform public.recompute_performance();
  update public.qoyod_settings set connection_status='connected', last_sync_at=now(), last_error=null where id=1;
  update public.sync_logs set status='success', finished_at=now(), records_synced=v_total,
    message='تمت مزامنة '||v_total||' عرض منذ '||v_since where id=v_log_id;
  return jsonb_build_object('ok',true,'message','تمت مزامنة '||v_total||' عرض','records',v_total,
    'unmatched',(select count(*) from public.sales_records where employee_id is null));
end; $$;

revoke all on function public.test_qoyod(text) from public;
revoke all on function public.sync_qoyod(text,date) from public;
grant execute on function public.test_qoyod(text) to anon;
grant execute on function public.sync_qoyod(text,date) to anon;
