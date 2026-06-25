// ============================================================================
// Vercel Serverless — مُستقبِل Webhook واتساب (Meta Cloud API)
// GET: تحقّق الـ verify_token | POST: استقبال الرسائل → ingest_message → رصد
// يستخدم SUPABASE_SERVICE_ROLE_KEY من متغيّرات بيئة Vercel (لا يُكشف للواجهة).
// ============================================================================
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://xcywapkfchvjpkrqqdnd.supabase.co';
const SR = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

async function rpc(fn, args) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: SR, Authorization: `Bearer ${SR}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args || {}),
  });
  return r.json();
}

module.exports = async (req, res) => {
  // التحقّق من الـ Webhook (handshake)
  if (req.method === 'GET') {
    const q = req.query || {};
    let verify = '';
    try { const rt = await rpc('meta_runtime'); verify = rt && rt.verify_token; } catch (_) {}
    if (q['hub.mode'] === 'subscribe' && q['hub.verify_token'] && q['hub.verify_token'] === verify) {
      res.status(200).send(q['hub.challenge']); return;
    }
    res.status(403).send('Forbidden'); return;
  }

  if (req.method === 'POST') {
    try {
      const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
      for (const entry of (body.entry || [])) {
        for (const ch of (entry.changes || [])) {
          const val = ch.value || {};
          const names = {};
          (val.contacts || []).forEach(c => { if (c.wa_id) names[c.wa_id] = c.profile && c.profile.name; });
          for (const m of (val.messages || [])) {
            const text = (m.text && m.text.body) || (m.button && m.button.text) ||
                         (m.interactive && JSON.stringify(m.interactive)) || ('[' + (m.type || 'message') + ']');
            await rpc('ingest_message', {
              p_wa_message_id: m.id,
              p_customer_wa: m.from,
              p_customer_name: names[m.from] || null,
              p_direction: 'inbound',
              p_body: text,
              p_sent_at: new Date((parseInt(m.timestamp, 10) || Math.floor(Date.now() / 1000)) * 1000).toISOString(),
              p_employee_id: null,
              p_raw: m,
            });
          }
        }
      }
      res.status(200).send('EVENT_RECEIVED');
    } catch (e) {
      // أعِد 200 دائماً حتى لا يعيد Meta الإرسال بكثافة؛ الخطأ يُسجَّل في لوج Vercel
      console.error('webhook error', e);
      res.status(200).send('EVENT_RECEIVED');
    }
    return;
  }
  res.status(405).end();
};
