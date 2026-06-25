// ============================================================================
// Vercel Serverless — تبادل كود Embedded Signup بتوكن وصول وحفظ الربط
// POST { code, waba_id, phone_number_id } → يبادل الكود → يخزّن التوكن (Vault)
// عبر store_meta_connection + يشترك الـ WABA في الـ Webhook.
// ============================================================================
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://xcywapkfchvjpkrqqdnd.supabase.co';
const SR = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const GRAPH = 'https://graph.facebook.com/v21.0';

async function rpc(fn, args) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: SR, Authorization: `Bearer ${SR}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args || {}),
  });
  return r.json();
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).end(); return; }
  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const { code, waba_id, phone_number_id } = body;
    if (!code) { res.status(400).json({ ok: false, message: 'الكود مفقود' }); return; }

    const rt = await rpc('meta_runtime');
    if (!rt || !rt.app_id || !rt.app_secret) {
      res.status(400).json({ ok: false, message: 'App ID أو App Secret غير مضبوطين في الإعدادات' }); return;
    }

    // تبادل الكود بتوكن وصول
    const u = `${GRAPH}/oauth/access_token?client_id=${encodeURIComponent(rt.app_id)}` +
              `&client_secret=${encodeURIComponent(rt.app_secret)}&code=${encodeURIComponent(code)}`;
    const tok = await (await fetch(u)).json();
    if (!tok.access_token) { res.status(400).json({ ok: false, message: 'فشل تبادل الكود', detail: tok.error || tok }); return; }

    // اشتراك الـ WABA في تطبيقنا (لتدفّق الـ Webhook)
    if (waba_id) {
      try { await fetch(`${GRAPH}/${waba_id}/subscribed_apps`, { method: 'POST', headers: { Authorization: `Bearer ${tok.access_token}` } }); } catch (_) {}
    }

    await rpc('store_meta_connection', {
      p_access_token: tok.access_token, p_phone_number_id: phone_number_id || null,
      p_waba_id: waba_id || null, p_business_id: null,
    });
    res.status(200).json({ ok: true, message: 'تم ربط واتساب بنجاح' });
  } catch (e) {
    res.status(500).json({ ok: false, message: String(e) });
  }
};
