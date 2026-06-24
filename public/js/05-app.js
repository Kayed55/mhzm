/*!
 * الإقلاع: استعادة الجلسة ثم عرض اللوحة أو تسجيل الدخول
 * @module app
 */
'use strict';

async function boot() {
  if (!window.sb) {
    document.getElementById('app').innerHTML =
      '<div class="center-screen"><div class="center-card"><h2 style="color:#ef4444">غير متصل</h2><p>لم تُضبط إعدادات Supabase في 01-constants.js</p></div></div>';
    return;
  }
  // شاشة العرض المباشر: عامة بلا تسجيل دخول
  if (location.pathname.replace(/\/+$/, '') === '/live') { startLiveDisplay(); return; }
  App.token = getToken();
  if (!App.token) { navigate('login'); return; }
  // محاولة استعادة الجلسة
  try {
    await loadAppData();
    navigate(App.page && App.page !== 'login' ? App.page : 'dashboard');
  } catch (e) {
    clearToken();
    navigate('login');
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
