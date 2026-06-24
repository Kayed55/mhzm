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
