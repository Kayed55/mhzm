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
