-- ============================================================================
-- دوال تشغيل Meta (تُستدعى من دوال Vercel بـ service_role فقط — ليست لـ anon)
-- ============================================================================

-- قراءة بيانات التشغيل (تشمل الأسرار المفكوكة) — service_role فقط
create or replace function public.meta_runtime()
returns jsonb language plpgsql security definer set search_path to 'public, vault' as $$
declare c public.meta_settings;
begin
  select * into c from public.meta_settings where id=1;
  return jsonb_build_object(
    'app_id', c.app_id, 'config_id', c.config_id, 'verify_token', c.verify_token,
    'phone_number_id', c.phone_number_id, 'waba_id', c.waba_id,
    'access_token', (select decrypted_secret from vault.decrypted_secrets where name='meta_access_token'),
    'app_secret',   (select decrypted_secret from vault.decrypted_secrets where name='meta_app_secret'));
end; $$;

-- تخزين توكن/معرّفات الربط بعد نجاح Embedded Signup — service_role فقط
create or replace function public.store_meta_connection(
  p_access_token text, p_phone_number_id text, p_waba_id text, p_business_id text
) returns jsonb language plpgsql security definer set search_path to 'public, vault' as $$
declare c public.meta_settings; v_id uuid;
begin
  select * into c from public.meta_settings where id=1;
  if coalesce(trim(p_access_token),'')<>'' then
    if c.access_token_secret_id is null then select vault.create_secret(p_access_token,'meta_access_token_'||floor(extract(epoch from now()))) into v_id; update public.meta_settings set access_token_secret_id=v_id where id=1;
    else perform vault.update_secret(c.access_token_secret_id, p_access_token); end if;
  end if;
  update public.meta_settings set
    phone_number_id = coalesce(nullif(trim(coalesce(p_phone_number_id,'')),''), phone_number_id),
    waba_id        = coalesce(nullif(trim(coalesce(p_waba_id,'')),''), waba_id),
    business_id    = coalesce(nullif(trim(coalesce(p_business_id,'')),''), business_id),
    connection_status='connected', last_error=null, updated_at=now()
  where id=1;
  return jsonb_build_object('ok',true);
end; $$;

revoke all on function public.meta_runtime() from public;
revoke all on function public.store_meta_connection(text,text,text,text) from public;
grant execute on function public.meta_runtime() to service_role;
grant execute on function public.store_meta_connection(text,text,text,text) to service_role;
grant execute on function public.ingest_message(text,text,text,text,text,timestamptz,bigint,jsonb) to service_role;
