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
