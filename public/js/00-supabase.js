/*!
 * تهيئة عميل Supabase + غلاف استدعاء RPC
 * @module supabase
 */
'use strict';

window.sb = null;
try {
  if (window.supabase && SUPABASE_CONFIG.url.indexOf('YOUR_') === -1) {
    window.sb = window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey, {
      auth: { persistSession: false },
      global: { fetch: (u, o) => fetch(u, Object.assign({}, o, { cache: 'no-store' })) },
    });
  }
} catch (e) { console.error('Supabase init failed', e); }

// غلاف موحّد لاستدعاء RPC: يُرجع data أو يرمي رسالة عربية
async function rpc(fn, args) {
  if (!window.sb) throw new Error('النظام غير متصل بقاعدة البيانات');
  const { data, error } = await window.sb.rpc(fn, args || {});
  if (error) throw new Error(error.message || 'خطأ في الخادم');
  return data;
}
