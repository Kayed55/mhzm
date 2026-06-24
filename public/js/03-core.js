/*!
 * الأدوات الأساسية: Utils, Toast, Modal, Perms, الجلسة, حالة التطبيق
 * @module core
 */
'use strict';

// حالة التطبيق العامة
const App = {
  token: null,
  me: null,                 // {id, role, name, team_leader_id}
  data: { employees: [], team_leaders: [], targets: [], performance: [], settings: {} },
  page: 'dashboard',
  params: {},
};

// الجلسة (localStorage)
const SESSION_KEY = 'sp_session';
function getToken() { try { return localStorage.getItem(SESSION_KEY); } catch (_) { return null; } }
function setToken(t) { try { localStorage.setItem(SESSION_KEY, t); } catch (_) {} App.token = t; }
function clearToken() { try { localStorage.removeItem(SESSION_KEY); } catch (_) {} App.token = null; App.me = null; }

// أدوات
const Utils = {
  escape(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); },
  pct(v) { return (Math.round((Number(v) || 0) * 10) / 10) + '%'; },
  formatDate(d) { if (!d) return '-'; try { return new Date(d).toLocaleDateString('ar-SA'); } catch (_) { return d; } },
  num(v) { return new Intl.NumberFormat('ar-SA').format(Number(v) || 0); },
};

// الصلاحيات حسب الدور
const Perms = {
  ROLE_PERMS: {
    admin: ['*'],
    manager: ['view_all', 'view_reports'],
    team_leader: ['view_own_team', 'view_reports'],
  },
  can(p) {
    const r = App.me && App.me.role; if (!r) return false;
    const list = Perms.ROLE_PERMS[r] || [];
    return list.indexOf('*') !== -1 || list.indexOf(p) !== -1;
  },
  isAdmin() { return App.me && App.me.role === 'admin'; },
};

// توست
const Toast = {
  _el: null,
  show(msg, type) {
    let c = document.getElementById('toast-wrap');
    if (!c) { c = document.createElement('div'); c.id = 'toast-wrap'; c.style.cssText = 'position:fixed;top:16px;left:50%;transform:translateX(-50%);z-index:10000;display:flex;flex-direction:column;gap:8px'; document.body.appendChild(c); }
    const bg = { success: '#16a34a', error: '#ef4444', warning: '#f59e0b', info: '#0ea5e9' }[type || 'info'];
    const t = document.createElement('div');
    t.style.cssText = `background:${bg};color:#fff;padding:11px 18px;border-radius:8px;box-shadow:0 4px 14px rgba(0,0,0,.2);font-weight:600;font-size:14px;max-width:90vw`;
    t.textContent = msg; c.appendChild(t);
    setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity .3s'; setTimeout(() => t.remove(), 300); }, 3200);
  },
  success(m) { this.show(m, 'success'); }, error(m) { this.show(m, 'error'); },
  warning(m) { this.show(m, 'warning'); }, info(m) { this.show(m, 'info'); },
};

// مودال
const Modal = {
  show(title, bodyHTML, footerHTML) {
    this.close();
    const ov = document.createElement('div');
    ov.id = 'modal-ov';
    ov.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:9000;display:flex;align-items:center;justify-content:center;padding:20px';
    ov.innerHTML = `<div style="background:#fff;border-radius:14px;max-width:560px;width:100%;max-height:90vh;overflow:auto;box-shadow:0 20px 60px rgba(0,0,0,.3)">
      <div style="padding:16px 20px;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center">
        <h3 style="font-size:16px;color:var(--primary)">${title}</h3>
        <button onclick="Modal.close()" style="background:none;border:none;font-size:22px;cursor:pointer;color:var(--muted)">×</button>
      </div>
      <div style="padding:20px">${bodyHTML}</div>
      <div style="padding:14px 20px;border-top:1px solid var(--border);display:flex;gap:8px;justify-content:flex-start">${footerHTML || ''}</div>
    </div>`;
    ov.addEventListener('click', e => { if (e.target === ov) Modal.close(); });
    document.body.appendChild(ov);
  },
  close() { const m = document.getElementById('modal-ov'); if (m) m.remove(); },
};

// تحميل بيانات اللوحة من الخادم (مفلترة حسب الدور)
async function loadAppData() {
  const d = await rpc('get_app_data', { p_session_token: App.token });
  if (!d || !d.ok) { throw new Error((d && d.message) || 'تعذّر تحميل البيانات'); }
  App.me = d.me;
  App.data = {
    employees: d.employees || [], team_leaders: d.team_leaders || [],
    targets: d.targets || [], performance: d.performance || [], settings: d.settings || {},
  };
  if (App.data.settings && App.data.settings.system_name) SYSTEM_NAME = App.data.settings.system_name;
  return App.data;
}

// معالجة انتهاء الجلسة
function handleSessionError(msg) {
  if (/انتهت الجلسة|غير صالح/.test(msg || '')) { clearToken(); Toast.error('انتهت الجلسة — سجّل الدخول'); navigate('login'); return true; }
  return false;
}
