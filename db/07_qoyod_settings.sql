-- ============================================================================
-- إعدادات قيود: قراءة (مُقنّعة) + حفظ (الأسرار في Vault) — admin فقط
-- ============================================================================
-- الأسرار (client_id, client_secret, api_key) تُخزَّن في Vault؛ لا تُعاد أبداً
-- للواجهة. تُفكّ فقط داخل Edge Function (service_role) عند المزامنة.
-- ============================================================================

-- قراءة الإعدادات (بلا أسرار) + آخر سجلات المزامنة
create or replace function public.get_qoyod_settings(p_session_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s record; c public.qoyod_settings;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  select * into c from public.qoyod_settings where id=1;
  return jsonb_build_object('ok',true,
    'settings', jsonb_build_object(
      'company_id', c.company_id, 'branch_id', c.branch_id, 'base_url', c.base_url,
      'webhook_url', c.webhook_url, 'sync_interval_min', c.sync_interval_min,
      'connection_status', c.connection_status, 'last_sync_at', c.last_sync_at, 'last_error', c.last_error,
      'has_client_id', c.client_id_secret_id is not null,
      'has_client_secret', c.client_secret_secret_id is not null,
      'has_api_key', c.api_key_secret_id is not null),
    'logs', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'started_at',started_at,'finished_at',finished_at,'status',status,
        'records_synced',records_synced,'message',message,'triggered_by',triggered_by) order by id desc)
      from (select * from public.sync_logs order by id desc limit 15) t),'[]'::jsonb));
end; $$;

-- حفظ الإعدادات (غير السرّية مباشرة، والأسرار عبر Vault؛ الفارغ = إبقاء القديم)
create or replace function public.save_qoyod_settings(
  p_session_token text, p_company_id text, p_branch_id text, p_base_url text,
  p_webhook_url text, p_sync_interval_min int,
  p_client_id text default null, p_client_secret text default null, p_api_key text default null
) returns jsonb language plpgsql security definer set search_path to 'public, vault' as $$
declare s record; c public.qoyod_settings; v_id uuid;
begin
  select * into s from public.verify_session(p_session_token);
  if not coalesce(s.is_valid,false) then return jsonb_build_object('ok',false,'message','انتهت الجلسة'); end if;
  if s.role <> 'admin' then return jsonb_build_object('ok',false,'message','هذه العملية للمدير فقط'); end if;
  select * into c from public.qoyod_settings where id=1;

  update public.qoyod_settings set
    company_id = nullif(trim(coalesce(p_company_id,'')),''),
    branch_id  = nullif(trim(coalesce(p_branch_id,'')),''),
    base_url   = coalesce(nullif(trim(coalesce(p_base_url,'')),''), base_url),
    webhook_url= nullif(trim(coalesce(p_webhook_url,'')),''),
    sync_interval_min = coalesce(p_sync_interval_min, sync_interval_min),
    updated_at = now(), updated_by = s.user_id
  where id=1;

  -- الأسرار: أنشئ/حدّث في Vault فقط إن أُرسلت قيمة غير فارغة
  if coalesce(trim(p_client_id),'') <> '' then
    if c.client_id_secret_id is null then
      select vault.create_secret(p_client_id,'qoyod_client_id') into v_id;
      update public.qoyod_settings set client_id_secret_id=v_id where id=1;
    else perform vault.update_secret(c.client_id_secret_id, p_client_id); end if;
  end if;
  if coalesce(trim(p_client_secret),'') <> '' then
    if c.client_secret_secret_id is null then
      select vault.create_secret(p_client_secret,'qoyod_client_secret') into v_id;
      update public.qoyod_settings set client_secret_secret_id=v_id where id=1;
    else perform vault.update_secret(c.client_secret_secret_id, p_client_secret); end if;
  end if;
  if coalesce(trim(p_api_key),'') <> '' then
    if c.api_key_secret_id is null then
      select vault.create_secret(p_api_key,'qoyod_api_key') into v_id;
      update public.qoyod_settings set api_key_secret_id=v_id where id=1;
    else perform vault.update_secret(c.api_key_secret_id, p_api_key); end if;
  end if;

  perform public._audit(s.user_id,s.full_name,s.role,'save_qoyod_settings','qoyod_settings',1,'تحديث إعدادات قيود');
  return jsonb_build_object('ok',true,'message','تم حفظ إعدادات قيود');
end; $$;

revoke all on function public.get_qoyod_settings(text) from public;
revoke all on function public.save_qoyod_settings(text,text,text,text,text,int,text,text,text) from public;
grant execute on function public.get_qoyod_settings(text) to anon;
grant execute on function public.save_qoyod_settings(text,text,text,text,text,int,text,text,text) to anon;
