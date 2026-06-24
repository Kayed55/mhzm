// ============================================================================
// Edge Function: qoyod-sync — مزامنة مبيعات قيود (يعمل على الخادم فقط)
// ============================================================================
// لماذا Edge Function؟ استدعاء Qoyod يتطلّب Client Secret الذي لا يجوز أن
// يصل المتصفّح. هنا نقرأ الأسرار من Supabase Vault بـ service_role، نستدعي
// قيود، نخزّن المبيعات (محمية)، ونعيد احتساب الأداء.
//
// الاستدعاء: يدوي (زر "مزامنة الآن" عبر RPC→pg_net) أو مجدول (pg_cron).
// TODO (المرحلة 3): تعبئة منطق Qoyod الفعلي بعد توفّر وثائق الـ API والاعتماد.
// ============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const startedAt = new Date().toISOString();
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // service_role: يتجاوز RLS (خادم فقط)
    );

    // 1) فتح سجل مزامنة
    const { data: logRow } = await supabase
      .from('sync_logs')
      .insert({ status: 'running', triggered_by: 'auto' })
      .select('id').single();

    // 2) قراءة إعدادات قيود + فكّ الأسرار من Vault
    //    const { data: cfg } = await supabase.from('qoyod_settings').select('*').eq('id',1).single();
    //    const clientSecret = await readVaultSecret(supabase, cfg.client_secret_secret_id);
    //    ... المصادقة مع قيود (OAuth2 / API key) حسب وثائقهم ...

    // 3) سحب الفواتير/المبيعات منذ آخر مزامنة → upsert في sales_records (amount محمي)
    // 4) استدعاء recompute_performance() لإعادة احتساب النِّسب واللقطات

    // 5) إغلاق السجل بنجاح
    await supabase.from('sync_logs').update({
      status: 'success', finished_at: new Date().toISOString(), records_synced: 0,
      message: 'هيكل أولي — يُكمَّل في المرحلة 3',
    }).eq('id', logRow?.id);

    await supabase.from('qoyod_settings').update({
      connection_status: 'unknown', last_sync_at: new Date().toISOString(),
    }).eq('id', 1);

    return new Response(JSON.stringify({ ok: true, started_at: startedAt }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    });
  }
});
