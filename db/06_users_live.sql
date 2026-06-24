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
