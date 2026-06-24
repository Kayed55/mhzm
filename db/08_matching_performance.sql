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
