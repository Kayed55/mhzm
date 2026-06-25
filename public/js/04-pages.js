/*!
 * نظام مساند الجودة — صفحات التطبيق
 * @module pages
 */
'use strict';

const MENU = [
  { key: 'dashboard', label: 'نظرة عامة',          icon: '📊', roles: ['admin', 'manager', 'team_leader'] },
  { key: 'notes',     label: 'الملاحظات المرصودة', icon: '📝', roles: ['admin', 'manager', 'team_leader'] },
  { key: 'reports',   label: 'تقارير الجودة',      icon: '📑', roles: ['admin', 'manager', 'team_leader'] },
  { key: 'keywords',  label: 'كلمات الجودة',       icon: '�key', roles: ['admin'] },
  { key: 'employees', label: 'الموظفون',           icon: '👥', roles: ['admin'] },
  { key: 'users',     label: 'المستخدمون',         icon: '🛡️', roles: ['admin'] },
  { key: 'meta',      label: 'إعدادات الربط (Meta)', icon: '🔌', roles: ['admin'] },
  { key: 'settings',  label: 'الإعدادات',          icon: '⚙️', roles: ['admin'] },
];

function navigate(page, params) { App.page = page; App.params = params || {}; render(); }

function render() {
  const app = document.getElementById('app');
  if (!App.me || App.page === 'login') { app.innerHTML = renderLogin(); bindLogin(); return; }
  const visible = MENU.filter(m => m.roles.indexOf(App.me.role) !== -1);
  const nav = visible.map(m => `<a href="#" data-go="${m.key}"
       style="display:flex;align-items:center;gap:10px;padding:12px 18px;color:#fff;text-decoration:none;${App.page === m.key ? 'background:rgba(255,255,255,.15);font-weight:700' : 'opacity:.85'}">
       <span>${m.icon.replace('�key','🔑')}</span><span>${m.label}</span></a>`).join('');
  app.innerHTML = `
  <div class="app">
    <aside class="sidebar" id="sp-sidebar">
      <div style="padding:20px 18px;border-bottom:1px solid rgba(255,255,255,.15)"><div style="font-weight:800;font-size:15px">🛡️ ${Utils.escape(SYSTEM_NAME)}</div></div>
      <nav style="padding:10px 0">${nav}</nav>
      <div style="position:absolute;bottom:0;width:260px;padding:14px 18px;border-top:1px solid rgba(255,255,255,.15)">
        <div style="font-size:13px;opacity:.85;margin-bottom:8px">${Utils.escape(App.me.name)} — ${roleLabel(App.me.role)}</div>
        <button class="btn btn-sm btn-secondary" id="sp-passwd" style="margin-bottom:6px">🔑 كلمة المرور</button>
        <button class="btn btn-sm btn-secondary" id="sp-logout">تسجيل الخروج</button>
      </div>
    </aside>
    <div class="main">
      <div class="topbar">
        <button class="btn btn-sm btn-secondary" id="sp-burger" style="display:none">☰</button>
        <div style="font-weight:700">${(MENU.find(m => m.key === App.page) || {}).label || ''}</div>
        <div style="margin-inline-start:auto;font-size:13px;color:var(--muted)">${new Date().toLocaleDateString('ar-SA')}</div>
      </div>
      <div class="content" id="sp-content"></div>
    </div>
  </div>`;
  document.getElementById('sp-content').innerHTML = renderPage();
  bindShell(); bindPage();
}

function roleLabel(r) { return { admin: 'مدير', manager: 'مشرف', team_leader: 'مشرف فريق' }[r] || r; }

function renderPage() {
  switch (App.page) {
    case 'dashboard': return renderDashboard();
    case 'notes': return renderNotes();
    case 'reports': return renderReports();
    case 'keywords': return renderKeywords();
    case 'employees': return renderEmployees();
    case 'users': return renderUsers();
    case 'meta': return renderMeta();
    case 'settings': return renderSettings();
    default: return '<div class="card"><div class="card-body">الصفحة غير موجودة</div></div>';
  }
}

// ===== تسجيل الدخول =====
function renderLogin() {
  return `<div class="center-screen"><div class="center-card">
    <h1 style="color:var(--primary);font-size:21px;margin-bottom:6px">🛡️ ${Utils.escape(SYSTEM_NAME)}</h1>
    <p style="color:var(--muted);margin-bottom:20px">تسجيل الدخول</p>
    <form id="login-form" style="text-align:right">
      <div class="form-group"><label class="form-label">اسم المستخدم أو البريد</label><input class="form-control" id="lg-user" required></div>
      <div class="form-group"><label class="form-label">كلمة المرور</label><input type="password" class="form-control" id="lg-pass" required></div>
      <button class="btn btn-primary" type="submit" style="width:100%;justify-content:center">دخول</button>
    </form>
  </div></div>`;
}
function bindLogin() {
  const f = document.getElementById('login-form');
  if (f) f.addEventListener('submit', async e => {
    e.preventDefault();
    const btn = f.querySelector('button'); btn.disabled = true; btn.textContent = 'جارٍ الدخول...';
    try {
      const d = await rpc('login', { p_username: document.getElementById('lg-user').value.trim(), p_password: document.getElementById('lg-pass').value });
      const row = Array.isArray(d) ? d[0] : d;
      if (!row || !row.ok) { Toast.error((row && row.message) || 'فشل الدخول'); btn.disabled = false; btn.textContent = 'دخول'; return; }
      setToken(row.token); await loadAppData();
      if (row.must_change_password) Toast.warning('يُنصح بتغيير كلمة المرور الافتراضية');
      navigate('dashboard');
    } catch (err) { Toast.error(err.message); btn.disabled = false; btn.textContent = 'دخول'; }
  });
}

// ===== نظرة عامة =====
function renderDashboard() {
  const s = App.data.stats || {};
  const byLabel = s.by_label || {};
  const labelCards = Object.keys(byLabel).map(k => `<div class="stat-card"><div style="font-size:13px;color:var(--muted)">${Utils.escape(k)}</div><div style="font-size:26px;font-weight:800;color:var(--warning)">${byLabel[k]}</div></div>`).join('');
  return `
  <div class="stats-grid">
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">إجمالي الملاحظات</div><div style="font-size:30px;font-weight:800;color:var(--primary)">${s.total || 0}</div></div>
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">ملاحظات اليوم</div><div style="font-size:30px;font-weight:800;color:var(--danger)">${s.today || 0}</div></div>
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">الموظفون</div><div style="font-size:30px;font-weight:800">${App.data.employees.length}</div></div>
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">كلمات الجودة</div><div style="font-size:30px;font-weight:800">${App.data.keywords.length}</div></div>
  </div>
  ${labelCards ? `<div class="card"><div class="card-header"><div class="card-title">الملاحظات حسب النوع</div></div><div class="card-body"><div class="stats-grid">${labelCards}</div></div></div>` : ''}
  <div class="alert alert-info">تُرصد الملاحظات تلقائياً عند ورود رسائل تحوي كلمات الجودة (بعد ربط Meta Cloud API من صفحة "إعدادات الربط").</div>`;
}

// ===== الملاحظات المرصودة (فلترة + بحث) =====
function renderNotes() {
  if (!App._notes) { loadNotes(); return '<div class="card"><div class="card-body">⏳ جارٍ التحميل…</div></div>'; }
  const items = App._notes.items || [];
  const empOpts = App.data.employees.map(e => `<option value="${e.id}">${Utils.escape(e.full_name)}</option>`).join('');
  const labels = [...new Set(App.data.keywords.map(k => k.label))].map(l => `<option value="${Utils.escape(l)}">${Utils.escape(l)}</option>`).join('');
  const rows = items.map(n => `<tr>
      <td>${n.at ? new Date(n.at).toLocaleString('ar-SA') : '—'}</td>
      <td>${Utils.escape(n.employee || 'غير محدد')}</td>
      <td>${Utils.escape(n.customer || '-')}</td>
      <td><span class="badge" style="background:var(--warning)">${Utils.escape(n.label || '-')}</span><div style="font-size:11px;color:var(--muted)">${Utils.escape(n.phrase || '')}</div></td>
      <td style="max-width:320px;font-size:13px">${Utils.escape(n.text || '')}</td>
    </tr>`).join('') || '<tr><td colspan="5" style="text-align:center;padding:24px;color:var(--muted)">لا توجد ملاحظات مطابقة</td></tr>';
  return `<h2 style="font-size:18px;margin-bottom:12px">📝 الملاحظات المرصودة (${items.length})</h2>
  <div class="card"><div class="card-body">
    <div class="grid grid-4">
      <div class="form-group"><label class="form-label">الموظف</label><select class="form-control" id="nf-emp"><option value="">الكل</option>${empOpts}</select></div>
      <div class="form-group"><label class="form-label">نوع الملاحظة</label><select class="form-control" id="nf-label"><option value="">الكل</option>${labels}</select></div>
      <div class="form-group"><label class="form-label">من تاريخ</label><input type="date" class="form-control" id="nf-from"></div>
      <div class="form-group"><label class="form-label">إلى تاريخ</label><input type="date" class="form-control" id="nf-to"></div>
    </div>
    <div style="display:flex;gap:8px"><input class="form-control" id="nf-search" placeholder="بحث في النص أو اسم العميل..." style="flex:1"><button class="btn btn-primary" id="nf-go">🔍 بحث</button></div>
  </div></div>
  <div class="card"><table class="table">
    <thead><tr><th>التاريخ/الوقت</th><th>الموظف</th><th>العميل</th><th>النوع/العبارة</th><th>نص الرسالة</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}
function loadNotes(filters) {
  rpc('get_quality_notes', Object.assign({ p_session_token: App.token }, filters || {})).then(d => {
    if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
    App._notes = d; if (App.page === 'notes') render();
  }).catch(e => Toast.error(e.message));
}

// ===== تقارير الجودة =====
function renderReports() {
  if (!App._report) { rpc('quality_report', { p_session_token: App.token }).then(d => { if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } App._report = d; if (App.page === 'reports') render(); }).catch(e => Toast.error(e.message)); return '<div class="card"><div class="card-body">⏳ جارٍ التحميل…</div></div>'; }
  const be = App._report.by_employee || [], bl = App._report.by_label || [];
  const eRows = be.map(r => `<tr><td>${Utils.escape(r.employee)}</td><td><strong>${r.count}</strong></td></tr>`).join('') || '<tr><td colspan="2" style="text-align:center;padding:18px;color:var(--muted)">لا بيانات</td></tr>';
  const lRows = bl.map(r => `<tr><td>${Utils.escape(r.label)}</td><td><strong>${r.count}</strong></td></tr>`).join('') || '<tr><td colspan="2" style="text-align:center;padding:18px;color:var(--muted)">لا بيانات</td></tr>';
  return `<h2 style="font-size:18px;margin-bottom:12px">📑 تقارير الجودة</h2>
  <div class="grid grid-2">
    <div class="card"><div class="card-header"><div class="card-title">حسب الموظف</div></div><table class="table"><thead><tr><th>الموظف</th><th>عدد الملاحظات</th></tr></thead><tbody>${eRows}</tbody></table></div>
    <div class="card"><div class="card-header"><div class="card-title">حسب نوع الملاحظة</div></div><table class="table"><thead><tr><th>النوع</th><th>التكرار</th></tr></thead><tbody>${lRows}</tbody></table></div>
  </div>`;
}

// ===== كلمات الجودة =====
function renderKeywords() {
  const rows = App.data.keywords.map(k => `<tr>
      <td>${Utils.escape(k.phrase)}</td>
      <td><span class="badge" style="background:var(--info)">${Utils.escape(k.label)}</span></td>
      <td>${k.is_active ? '✅ مفعّلة' : '🚫 موقوفة'}</td>
      <td><button class="btn btn-sm btn-warning" data-kw-edit="${k.id}">تعديل</button>
          <button class="btn btn-sm btn-danger" data-kw-del="${k.id}">حذف</button></td>
    </tr>`).join('') || '<tr><td colspan="4" style="text-align:center;padding:24px;color:var(--muted)">لا توجد كلمات</td></tr>';
  return `<div style="display:flex;justify-content:space-between;margin-bottom:14px">
      <h2 style="font-size:18px">🔑 كلمات/أوامر الجودة (${App.data.keywords.length})</h2>
      <button class="btn btn-primary" id="kw-add">➕ إضافة كلمة</button></div>
    <div class="alert alert-info">عند ورود رسالة تحوي أيّاً من هذه العبارات تُسجَّل ملاحظة جودة تلقائياً.</div>
    <div class="card"><table class="table"><thead><tr><th>العبارة</th><th>نوع الملاحظة</th><th>الحالة</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}
function keywordModal(k) {
  Modal.show(k ? 'تعديل كلمة' : 'إضافة كلمة', `
    <div class="form-group"><label class="form-label">العبارة *</label><input class="form-control" id="kw-phrase" value="${k ? Utils.escape(k.phrase) : ''}" placeholder="مثال: ارسل حسابك"></div>
    <div class="form-group"><label class="form-label">نوع الملاحظة</label><input class="form-control" id="kw-label" value="${k ? Utils.escape(k.label) : ''}" placeholder="مثال: طلب تحويل خارجي"></div>
    <div class="form-group"><label><input type="checkbox" id="kw-active" ${!k || k.is_active ? 'checked' : ''}> مفعّلة</label></div>`,
    `<button class="btn btn-primary" id="kw-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('kw-save').addEventListener('click', async () => {
    const phrase = document.getElementById('kw-phrase').value.trim();
    if (!phrase) { Toast.error('العبارة مطلوبة'); return; }
    try {
      const d = await rpc('upsert_keyword', { p_session_token: App.token, p_id: k ? k.id : null, p_phrase: phrase, p_label: document.getElementById('kw-label').value.trim(), p_is_active: document.getElementById('kw-active').checked });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم الحفظ'); await refresh();
    } catch (e) { Toast.error(e.message); }
  });
}

// ===== الموظفون =====
function renderEmployees() {
  const rows = App.data.employees.map(e => `<tr>
      <td>${Utils.escape(e.full_name)}</td>
      <td><button class="btn btn-sm btn-warning" data-emp-edit="${e.id}">تعديل</button>
          <button class="btn btn-sm btn-danger" data-emp-del="${e.id}">حذف</button></td>
    </tr>`).join('') || '<tr><td colspan="2" style="text-align:center;padding:24px;color:var(--muted)">لا يوجد موظفون</td></tr>';
  return `<div style="display:flex;justify-content:space-between;margin-bottom:14px">
      <h2 style="font-size:18px">👥 الموظفون (${App.data.employees.length})</h2>
      <button class="btn btn-primary" id="emp-add">➕ إضافة موظف</button></div>
    <div class="card"><table class="table"><thead><tr><th>الاسم</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}
function employeeModal(emp) {
  Modal.show(emp ? 'تعديل موظف' : 'إضافة موظف', `
    <div class="form-group"><label class="form-label">الاسم الكامل *</label><input class="form-control" id="em-name" value="${emp ? Utils.escape(emp.full_name) : ''}" placeholder="الاسم كما يظهر في المحادثات"></div>`,
    `<button class="btn btn-primary" id="em-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('em-save').addEventListener('click', async () => {
    const name = document.getElementById('em-name').value.trim();
    if (!name) { Toast.error('الاسم مطلوب'); return; }
    try {
      const d = await rpc('upsert_employee', { p_session_token: App.token, p_id: emp ? emp.id : null, p_full_name: name, p_employee_code: null, p_qoyod_ref: null, p_team_leader_id: null, p_show_in_display: true, p_is_active: true });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم الحفظ'); await refresh();
    } catch (e) { Toast.error(e.message); }
  });
}

// ===== المستخدمون =====
function renderUsers() {
  if (!App._users) { rpc('get_users', { p_session_token: App.token }).then(d => { if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } App._users = d.users || []; if (App.page === 'users') render(); }).catch(e => Toast.error(e.message)); return '<div class="card"><div class="card-body">⏳ جارٍ التحميل…</div></div>'; }
  const rows = App._users.map(u => `<tr>
      <td>${Utils.escape(u.full_name)}</td><td>${Utils.escape(u.username)}</td><td>${roleLabel(u.role)}</td>
      <td>${u.is_active ? '<span class="badge" style="background:var(--success)">نشط</span>' : '<span class="badge" style="background:var(--muted)">موقوف</span>'}</td>
      <td><button class="btn btn-sm btn-warning" data-usr-edit="${u.id}">تعديل</button>${u.id !== App.me.id ? `<button class="btn btn-sm btn-danger" data-usr-del="${u.id}">حذف</button>` : ''}</td>
    </tr>`).join('') || '<tr><td colspan="5" style="text-align:center;padding:24px;color:var(--muted)">لا يوجد مستخدمون</td></tr>';
  return `<div style="display:flex;justify-content:space-between;margin-bottom:14px"><h2 style="font-size:18px">🛡️ المستخدمون (${App._users.length})</h2><button class="btn btn-primary" id="usr-add">➕ إضافة مستخدم</button></div>
    <div class="card"><table class="table"><thead><tr><th>الاسم</th><th>المستخدم</th><th>الدور</th><th>الحالة</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}
function userModal(u) {
  const roles = [['admin', 'مدير'], ['manager', 'مشرف'], ['team_leader', 'مشرف فريق']].map(([v, l]) => `<option value="${v}" ${u && u.role === v ? 'selected' : ''}>${l}</option>`).join('');
  Modal.show(u ? 'تعديل مستخدم' : 'إضافة مستخدم', `
    <div class="form-group"><label class="form-label">الاسم *</label><input class="form-control" id="us-name" value="${u ? Utils.escape(u.full_name) : ''}"></div>
    <div class="form-group"><label class="form-label">اسم المستخدم *</label><input class="form-control" id="us-username" value="${u ? Utils.escape(u.username) : ''}"></div>
    <div class="form-group"><label class="form-label">البريد</label><input class="form-control" id="us-email" value="${u ? Utils.escape(u.email || '') : ''}"></div>
    <div class="form-group"><label class="form-label">الدور *</label><select class="form-control" id="us-role">${roles}</select></div>
    <div class="form-group"><label class="form-label">${u ? 'كلمة مرور جديدة (فارغة = إبقاء)' : 'كلمة المرور *'}</label><input type="text" class="form-control" id="us-pass"></div>
    <div class="form-group"><label><input type="checkbox" id="us-active" ${!u || u.is_active ? 'checked' : ''}> نشط</label></div>`,
    `<button class="btn btn-primary" id="us-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('us-save').addEventListener('click', async () => {
    const name = document.getElementById('us-name').value.trim(), username = document.getElementById('us-username').value.trim();
    if (!name || !username) { Toast.error('الاسم واسم المستخدم مطلوبان'); return; }
    try {
      const d = await rpc('upsert_user', { p_session_token: App.token, p_id: u ? u.id : null, p_username: username, p_email: document.getElementById('us-email').value.trim(), p_full_name: name, p_role: document.getElementById('us-role').value, p_is_active: document.getElementById('us-active').checked, p_password: document.getElementById('us-pass').value || null });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم الحفظ'); App._users = null; render();
    } catch (e) { Toast.error(e.message); }
  });
}
function deleteUser(id) {
  if (!confirm('حذف المستخدم؟')) return;
  rpc('delete_user', { p_session_token: App.token, p_id: parseInt(id) }).then(d => { if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } Toast.success('تم الحذف'); App._users = null; render(); }).catch(e => Toast.error(e.message));
}

// ===== إعدادات الربط مع Meta =====
function renderMeta() {
  if (!App._meta) { rpc('get_meta_settings', { p_session_token: App.token }).then(d => { if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } App._meta = d; if (App.page === 'meta') render(); }).catch(e => Toast.error(e.message)); return '<div class="card"><div class="card-body">⏳ جارٍ التحميل…</div></div>'; }
  const s = App._meta.settings || {};
  const statusBadge = { connected: '<span class="badge" style="background:var(--success)">متصل</span>', error: '<span class="badge" style="background:var(--danger)">خطأ</span>', disconnected: '<span class="badge" style="background:var(--muted)">غير متصل</span>', unknown: '<span class="badge" style="background:var(--warning)">غير معروف</span>' }[s.connection_status || 'unknown'];
  const secret = (id, label, has) => `<div class="form-group"><label class="form-label">${label}${has ? ' <span style="color:var(--success);font-size:11px">(محفوظ ✓)</span>' : ''}</label><input type="password" class="form-control" id="${id}" placeholder="${has ? 'محفوظ — فارغ للإبقاء' : ''}" autocomplete="new-password"></div>`;
  return `<h2 style="font-size:18px;margin-bottom:12px">🔌 إعدادات الربط — Meta Cloud API</h2>
  <div class="alert alert-info">الأسرار (Access Token / App Secret) تُخزَّن مشفّرة في Vault ولا تُعرض. <strong>Webhook يستقبل الرسائل لحظياً.</strong></div>
  <div class="card"><div class="card-header"><div class="card-title">حالة الربط</div><div>${statusBadge}</div></div>
    <div class="card-body" style="font-size:14px">آخر حدث: <strong>${s.last_event_at ? new Date(s.last_event_at).toLocaleString('ar-SA') : '—'}</strong>${s.last_error ? ` · <span style="color:var(--danger)">${Utils.escape(s.last_error)}</span>` : ''}</div></div>
  <div class="card"><div class="card-header"><div class="card-title">بيانات الربط</div></div><div class="card-body">
    <div class="grid grid-2">
      <div class="form-group"><label class="form-label">App ID</label><input class="form-control" id="mt-app" value="${Utils.escape(s.app_id || '')}"></div>
      <div class="form-group"><label class="form-label">Business ID</label><input class="form-control" id="mt-biz" value="${Utils.escape(s.business_id || '')}"></div>
      <div class="form-group"><label class="form-label">WhatsApp Business Account ID (WABA)</label><input class="form-control" id="mt-waba" value="${Utils.escape(s.waba_id || '')}"></div>
      <div class="form-group"><label class="form-label">Phone Number ID</label><input class="form-control" id="mt-phone" value="${Utils.escape(s.phone_number_id || '')}"></div>
      <div class="form-group"><label class="form-label">Verify Token (للـ Webhook)</label><input class="form-control" id="mt-verify" value="${Utils.escape(s.verify_token || '')}"></div>
      <div class="form-group"><label class="form-label">Webhook URL</label><input class="form-control" id="mt-webhook" value="${Utils.escape(s.webhook_url || '')}" placeholder="https://mhzm.vercel.app/api/meta-webhook"></div>
      ${secret('mt-token', 'Access Token', s.has_access_token)}
      ${secret('mt-secret', 'App Secret', s.has_app_secret)}
    </div>
    <button class="btn btn-primary" id="mt-save">💾 حفظ إعدادات الربط</button>
  </div></div>
  <div class="alert alert-info">سأكمل تدفّق Embedded Signup ومُستقبِل الـ Webhook بعد تزويدك بكود Meta وحسم تعريف الموظف.</div>`;
}
async function saveMeta() {
  try {
    const d = await rpc('save_meta_settings', {
      p_session_token: App.token,
      p_app_id: document.getElementById('mt-app').value.trim(), p_business_id: document.getElementById('mt-biz').value.trim(),
      p_waba_id: document.getElementById('mt-waba').value.trim(), p_phone_number_id: document.getElementById('mt-phone').value.trim(),
      p_verify_token: document.getElementById('mt-verify').value.trim(), p_webhook_url: document.getElementById('mt-webhook').value.trim(),
      p_access_token: document.getElementById('mt-token').value || null, p_app_secret: document.getElementById('mt-secret').value || null,
    });
    if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
    Toast.success('تم الحفظ'); App._meta = null; render();
  } catch (e) { Toast.error(e.message); }
}

// ===== الإعدادات =====
function renderSettings() {
  const s = App.data.settings || {};
  return `<h2 style="font-size:18px;margin-bottom:12px">⚙️ إعدادات النظام</h2>
  <div class="card"><div class="card-body">
    <div class="form-group"><label class="form-label">اسم النظام</label><input class="form-control" id="st-name" value="${Utils.escape(s.system_name || '')}"></div>
    <div class="form-group"><label class="form-label">رابط الشعار</label><input class="form-control" id="st-logo" value="${Utils.escape(s.logo_url || '')}"></div>
    <button class="btn btn-primary" id="st-save">حفظ</button>
  </div></div>`;
}
async function saveSettings() {
  const next = Object.assign({}, App.data.settings || {}, { system_name: document.getElementById('st-name').value.trim(), logo_url: document.getElementById('st-logo').value.trim() });
  try { const d = await rpc('update_settings', { p_session_token: App.token, p_value: next }); if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } Toast.success('تم الحفظ'); await refresh(); } catch (e) { Toast.error(e.message); }
}

// ===== تغيير كلمة المرور =====
function changePasswordModal() {
  Modal.show('تغيير كلمة المرور', `
    <div class="form-group"><label class="form-label">الحالية</label><input type="password" class="form-control" id="cp-old"></div>
    <div class="form-group"><label class="form-label">الجديدة (6 أحرف+)</label><input type="password" class="form-control" id="cp-new"></div>
    <div class="form-group"><label class="form-label">تأكيد الجديدة</label><input type="password" class="form-control" id="cp-new2"></div>`,
    `<button class="btn btn-primary" id="cp-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('cp-save').addEventListener('click', async () => {
    const o = document.getElementById('cp-old').value, n = document.getElementById('cp-new').value, n2 = document.getElementById('cp-new2').value;
    if (n !== n2) { Toast.error('غير متطابقتين'); return; }
    try { const d = await rpc('change_my_password', { p_session_token: App.token, p_old: o, p_new: n }); if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } Modal.close(); Toast.success('تم التغيير'); } catch (e) { Toast.error(e.message); }
  });
}

// ===== ربط الأحداث =====
function bindShell() {
  document.querySelectorAll('[data-go]').forEach(a => a.addEventListener('click', e => { e.preventDefault(); navigate(a.dataset.go); }));
  const lo = document.getElementById('sp-logout'); if (lo) lo.addEventListener('click', async () => { try { await rpc('logout', { p_token: App.token }); } catch (_) {} clearToken(); navigate('login'); });
  const pw = document.getElementById('sp-passwd'); if (pw) pw.addEventListener('click', changePasswordModal);
  const burger = document.getElementById('sp-burger'); if (burger) { burger.style.display = window.innerWidth <= 768 ? 'inline-flex' : 'none'; burger.addEventListener('click', () => document.getElementById('sp-sidebar').classList.toggle('open')); }
}
function bindPage() {
  const g = id => document.getElementById(id);
  if (g('kw-add')) g('kw-add').addEventListener('click', () => keywordModal(null));
  document.querySelectorAll('[data-kw-edit]').forEach(b => b.addEventListener('click', () => keywordModal(App.data.keywords.find(k => k.id == b.dataset.kwEdit))));
  document.querySelectorAll('[data-kw-del]').forEach(b => b.addEventListener('click', () => { if (confirm('حذف الكلمة؟')) rpc('delete_keyword', { p_session_token: App.token, p_id: parseInt(b.dataset.kwDel) }).then(async d => { if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } Toast.success('تم الحذف'); await refresh(); }).catch(e => Toast.error(e.message)); }));
  if (g('emp-add')) g('emp-add').addEventListener('click', () => employeeModal(null));
  document.querySelectorAll('[data-emp-edit]').forEach(b => b.addEventListener('click', () => employeeModal(App.data.employees.find(e => e.id == b.dataset.empEdit))));
  document.querySelectorAll('[data-emp-del]').forEach(b => b.addEventListener('click', () => { if (confirm('حذف الموظف؟')) rpc('delete_employee', { p_session_token: App.token, p_id: parseInt(b.dataset.empDel) }).then(async d => { if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; } Toast.success('تم الحذف'); await refresh(); }).catch(e => Toast.error(e.message)); }));
  if (g('usr-add')) g('usr-add').addEventListener('click', () => userModal(null));
  document.querySelectorAll('[data-usr-edit]').forEach(b => b.addEventListener('click', () => userModal((App._users || []).find(u => u.id == b.dataset.usrEdit))));
  document.querySelectorAll('[data-usr-del]').forEach(b => b.addEventListener('click', () => deleteUser(b.dataset.usrDel)));
  if (g('mt-save')) g('mt-save').addEventListener('click', saveMeta);
  if (g('st-save')) g('st-save').addEventListener('click', saveSettings);
  if (g('nf-go')) g('nf-go').addEventListener('click', () => { App._notes = null; loadNotes({ p_employee_id: g('nf-emp').value ? parseInt(g('nf-emp').value) : null, p_label: g('nf-label').value || null, p_from: g('nf-from').value || null, p_to: g('nf-to').value || null, p_search: g('nf-search').value.trim() || null }); });
}

async function refresh() { try { await loadAppData(); render(); } catch (e) { if (!handleSessionError(e.message)) Toast.error(e.message); } }
