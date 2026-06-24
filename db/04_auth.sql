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
