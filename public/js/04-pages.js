/*!
 * صفحات التطبيق: تسجيل الدخول، الشِّل، اللوحة، الموظفات، التيم ليدرز، الأهداف، الإعدادات
 * @module pages
 */
'use strict';

const MENU = [
  { key: 'dashboard',    label: 'لوحة المؤشرات', icon: '📊', roles: ['admin', 'manager', 'team_leader'] },
  { key: 'employees',    label: 'الموظفات',      icon: '👥', roles: ['admin'] },
  { key: 'team_leaders', label: 'التيم ليدرز',   icon: '🧑‍💼', roles: ['admin'] },
  { key: 'users',        label: 'المستخدمون',     icon: '🛡️', roles: ['admin'] },
  { key: 'targets',      label: 'الأهداف',        icon: '🎯', roles: ['admin'] },
  { key: 'reports',      label: 'التقارير',       icon: '📑', roles: ['admin', 'manager', 'team_leader'] },
  { key: 'review',       label: 'يحتاج مراجعة',   icon: '⚠️', roles: ['admin', 'manager'] },
  { key: 'settings',     label: 'الإعدادات',      icon: '⚙️', roles: ['admin'] },
];

function navigate(page, params) {
  App.page = page; App.params = params || {};
  render();
}

function render() {
  const app = document.getElementById('app');
  if (!App.me || App.page === 'login') { app.innerHTML = renderLogin(); bindLogin(); return; }
  const visible = MENU.filter(m => m.roles.indexOf(App.me.role) !== -1);
  const nav = visible.map(m => `<a href="#" class="sp-nav ${App.page === m.key ? 'active' : ''}" data-go="${m.key}"
       style="display:flex;align-items:center;gap:10px;padding:12px 18px;color:#fff;text-decoration:none;${App.page === m.key ? 'background:rgba(255,255,255,.15);font-weight:700' : 'opacity:.85'}">
       <span>${m.icon}</span><span>${m.label}</span></a>`).join('');
  app.innerHTML = `
  <div class="app">
    <aside class="sidebar" id="sp-sidebar">
      <div style="padding:20px 18px;border-bottom:1px solid rgba(255,255,255,.15)">
        <div style="font-weight:800;font-size:16px">📊 ${Utils.escape(SYSTEM_NAME)}</div>
      </div>
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
  bindShell();
  bindPage();
}

function roleLabel(r) { return { admin: 'مدير', manager: 'مشرف', team_leader: 'تيم ليدر' }[r] || r; }

function renderPage() {
  switch (App.page) {
    case 'dashboard': return renderDashboard();
    case 'employees': return renderEmployees();
    case 'team_leaders': return renderTeamLeaders();
    case 'targets': return renderTargets();
    case 'users': return renderUsers();
    case 'settings': return renderSettings();
    case 'review': return renderReview();
    case 'reports': return '<div class="card"><div class="card-body">📑 التقارير — تُبنى في المرحلة 5.</div></div>';
    default: return '<div class="card"><div class="card-body">الصفحة غير موجودة</div></div>';
  }
}

// ===== تسجيل الدخول =====
function renderLogin() {
  return `<div class="center-screen"><div class="center-card">
    <h1 style="color:var(--primary);font-size:22px;margin-bottom:6px">📊 ${Utils.escape(SYSTEM_NAME)}</h1>
    <p style="color:var(--muted);margin-bottom:20px">تسجيل الدخول إلى لوحة التحكم</p>
    <form id="login-form" style="text-align:right">
      <div class="form-group"><label class="form-label">اسم المستخدم أو البريد</label><input class="form-control" id="lg-user" required></div>
      <div class="form-group"><label class="form-label">كلمة المرور</label><input type="password" class="form-control" id="lg-pass" required></div>
      <button class="btn btn-primary" type="submit" style="width:100%;justify-content:center">دخول</button>
    </form>
    <p style="margin-top:16px"><a href="#" data-go-live style="font-size:13px">عرض شاشة الأداء المباشر ←</a></p>
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
      setToken(row.token);
      await loadAppData();
      if (row.must_change_password) Toast.warning('يُنصح بتغيير كلمة المرور الافتراضية');
      navigate('dashboard');
    } catch (err) { Toast.error(err.message); btn.disabled = false; btn.textContent = 'دخول'; }
  });
  const live = document.querySelector('[data-go-live]');
  if (live) live.addEventListener('click', e => { e.preventDefault(); window.location.href = '/live'; });
}

// ===== اللوحة =====
function renderDashboard() {
  const emps = App.data.employees.filter(e => e.is_active);
  const perfFor = (empId, period) => {
    const p = App.data.performance.find(x => x.scope === 'employee' && x.employee_id === empId && x.period_type === period);
    return p ? Number(p.percentage) : null;
  };
  const thresholds = (App.data.settings && App.data.settings.status_thresholds) || DEFAULT_STATUS_THRESHOLDS;
  const avg = (period) => { const vals = emps.map(e => perfFor(e.id, period)).filter(v => v != null); return vals.length ? Math.round(vals.reduce((a, b) => a + b, 0) / vals.length) : 0; };

  const rows = emps.map(e => {
    const tl = App.data.team_leaders.find(t => t.id === e.team_leader_id);
    const m = perfFor(e.id, 'monthly');
    const st = m != null ? statusForPercentage(m, thresholds) : null;
    return `<tr>
      <td>${Utils.escape(e.full_name)}</td>
      <td>${Utils.escape(tl ? tl.full_name : '-')}</td>
      <td>${perfFor(e.id, 'daily') != null ? Utils.pct(perfFor(e.id, 'daily')) : '—'}</td>
      <td>${perfFor(e.id, 'weekly') != null ? Utils.pct(perfFor(e.id, 'weekly')) : '—'}</td>
      <td><strong>${m != null ? Utils.pct(m) : '—'}</strong></td>
      <td>${st ? `<span class="badge" style="background:${st.color}">${st.label}</span>` : '—'}</td>
    </tr>`;
  }).join('') || '<tr><td colspan="6" style="text-align:center;padding:24px;color:var(--muted)">لا توجد موظفات بعد — أضِفهن من صفحة "الموظفات"</td></tr>';

  return `
  <div class="stats-grid">
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">عدد الموظفات</div><div style="font-size:28px;font-weight:800">${emps.length}</div></div>
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">متوسط اليومي</div><div style="font-size:28px;font-weight:800;color:var(--info)">${Utils.pct(avg('daily'))}</div></div>
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">متوسط الأسبوعي</div><div style="font-size:28px;font-weight:800;color:var(--warning)">${Utils.pct(avg('weekly'))}</div></div>
    <div class="stat-card"><div style="font-size:13px;color:var(--muted)">متوسط الشهري</div><div style="font-size:28px;font-weight:800;color:var(--success)">${Utils.pct(avg('monthly'))}</div></div>
  </div>
  <div class="card">
    <div class="card-header"><div class="card-title">📊 أداء الموظفات (نِسب الإنجاز)</div></div>
    <table class="table">
      <thead><tr><th>الموظفة</th><th>التيم ليدر</th><th>يومي</th><th>أسبوعي</th><th>شهري</th><th>الحالة</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>
  ${App.data.performance.length === 0 ? '<div class="alert alert-info">لا توجد بيانات أداء بعد — ستظهر بعد ربط قيود ومزامنة المبيعات (المرحلة 3).</div>' : ''}`;
}

// ===== الموظفات =====
function renderEmployees() {
  const rows = App.data.employees.map(e => {
    const tl = App.data.team_leaders.find(t => t.id === e.team_leader_id);
    return `<tr>
      <td>${Utils.escape(e.full_name)}</td>
      <td>${Utils.escape(e.employee_code || '-')}</td>
      <td>${Utils.escape(e.qoyod_ref || '-')}</td>
      <td>${Utils.escape(tl ? tl.full_name : '-')}</td>
      <td>${e.show_in_display ? '✅' : '🚫'}</td>
      <td>${e.is_active ? '<span class="badge" style="background:var(--success)">نشطة</span>' : '<span class="badge" style="background:var(--muted)">موقوفة</span>'}</td>
      <td><button class="btn btn-sm btn-warning" data-emp-edit="${e.id}">تعديل</button>
          <button class="btn btn-sm btn-danger" data-emp-del="${e.id}">حذف</button></td>
    </tr>`;
  }).join('') || '<tr><td colspan="7" style="text-align:center;padding:24px;color:var(--muted)">لا توجد موظفات</td></tr>';
  return `
  <div style="display:flex;justify-content:space-between;margin-bottom:14px">
    <h2 style="font-size:18px">👥 الموظفات (${App.data.employees.length})</h2>
    <button class="btn btn-primary" id="emp-add">➕ إضافة موظفة</button>
  </div>
  <div class="card"><table class="table">
    <thead><tr><th>الاسم</th><th>الرقم</th><th>اسم بديل للمطابقة</th><th>التيم ليدر</th><th>العرض</th><th>الحالة</th><th></th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}
function employeeModal(emp) {
  const tlOpts = App.data.team_leaders.map(t => `<option value="${t.id}" ${emp && emp.team_leader_id === t.id ? 'selected' : ''}>${Utils.escape(t.full_name)}</option>`).join('');
  Modal.show(emp ? 'تعديل موظفة' : 'إضافة موظفة', `
    <div class="form-group"><label class="form-label">الاسم *</label><input class="form-control" id="em-name" value="${emp ? Utils.escape(emp.full_name) : ''}"></div>
    <div class="form-group"><label class="form-label">الرقم الوظيفي</label><input class="form-control" id="em-code" value="${emp ? Utils.escape(emp.employee_code || '') : ''}"></div>
    <div class="form-group"><label class="form-label">اسم بديل للمطابقة (اختياري)</label><input class="form-control" id="em-qoyod" value="${emp ? Utils.escape(emp.qoyod_ref || '') : ''}" placeholder="إن كان اسمها يُكتب بصيغة مختلفة في المصدر"></div>
    <div class="form-group"><label class="form-label">التيم ليدر</label><select class="form-control" id="em-tl"><option value="">— بلا —</option>${tlOpts}</select></div>
    <div class="form-group"><label><input type="checkbox" id="em-show" ${!emp || emp.show_in_display ? 'checked' : ''}> الظهور في شاشة العرض</label></div>
    <div class="form-group"><label><input type="checkbox" id="em-active" ${!emp || emp.is_active ? 'checked' : ''}> نشطة</label></div>`,
    `<button class="btn btn-primary" id="em-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('em-save').addEventListener('click', async () => {
    const name = document.getElementById('em-name').value.trim();
    if (!name) { Toast.error('الاسم مطلوب'); return; }
    try {
      const d = await rpc('upsert_employee', {
        p_session_token: App.token, p_id: emp ? emp.id : null, p_full_name: name,
        p_employee_code: document.getElementById('em-code').value.trim(),
        p_qoyod_ref: document.getElementById('em-qoyod').value.trim(),
        p_team_leader_id: document.getElementById('em-tl').value ? parseInt(document.getElementById('em-tl').value) : null,
        p_show_in_display: document.getElementById('em-show').checked,
        p_is_active: document.getElementById('em-active').checked,
      });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم الحفظ'); await refresh();
    } catch (e) { Toast.error(e.message); }
  });
}

// ===== التيم ليدرز =====
function renderTeamLeaders() {
  const rows = App.data.team_leaders.map(t => {
    const count = App.data.employees.filter(e => e.team_leader_id === t.id).length;
    return `<tr><td>${Utils.escape(t.full_name)}</td><td>${count} موظفة</td>
      <td>${t.is_active ? '<span class="badge" style="background:var(--success)">نشط</span>' : '<span class="badge" style="background:var(--muted)">موقوف</span>'}</td>
      <td><button class="btn btn-sm btn-warning" data-tl-edit="${t.id}">تعديل</button>
          <button class="btn btn-sm btn-danger" data-tl-del="${t.id}">حذف</button></td></tr>`;
  }).join('') || '<tr><td colspan="4" style="text-align:center;padding:24px;color:var(--muted)">لا يوجد تيم ليدرز</td></tr>';
  return `
  <div style="display:flex;justify-content:space-between;margin-bottom:14px">
    <h2 style="font-size:18px">🧑‍💼 التيم ليدرز (${App.data.team_leaders.length})</h2>
    <button class="btn btn-primary" id="tl-add">➕ إضافة</button>
  </div>
  <div class="card"><table class="table"><thead><tr><th>الاسم</th><th>الموظفات</th><th>الحالة</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}
function tlModal(tl) {
  Modal.show(tl ? 'تعديل تيم ليدر' : 'إضافة تيم ليدر', `
    <div class="form-group"><label class="form-label">الاسم *</label><input class="form-control" id="tl-name" value="${tl ? Utils.escape(tl.full_name) : ''}"></div>
    <div class="form-group"><label><input type="checkbox" id="tl-active" ${!tl || tl.is_active ? 'checked' : ''}> نشط</label></div>`,
    `<button class="btn btn-primary" id="tl-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('tl-save').addEventListener('click', async () => {
    const name = document.getElementById('tl-name').value.trim();
    if (!name) { Toast.error('الاسم مطلوب'); return; }
    try {
      const d = await rpc('upsert_team_leader', { p_session_token: App.token, p_id: tl ? tl.id : null, p_full_name: name, p_user_id: null, p_is_active: document.getElementById('tl-active').checked });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم الحفظ'); await refresh();
    } catch (e) { Toast.error(e.message); }
  });
}

// ===== الأهداف =====
function renderTargets() {
  const targetFor = (empId, period) => { const t = App.data.targets.find(x => x.scope === 'employee' && x.employee_id === empId && x.period_type === period); return t ? Number(t.target_amount) : null; };
  const rows = App.data.employees.map(e => `<tr>
      <td>${Utils.escape(e.full_name)}</td>
      <td>${targetFor(e.id, 'daily') != null ? Utils.num(targetFor(e.id, 'daily')) : '—'}</td>
      <td>${targetFor(e.id, 'weekly') != null ? Utils.num(targetFor(e.id, 'weekly')) : '—'}</td>
      <td>${targetFor(e.id, 'monthly') != null ? Utils.num(targetFor(e.id, 'monthly')) : '—'}</td>
      <td><button class="btn btn-sm btn-primary" data-tg-edit="${e.id}">تحديد الأهداف</button></td>
    </tr>`).join('') || '<tr><td colspan="5" style="text-align:center;padding:24px;color:var(--muted)">أضِف موظفات أولاً</td></tr>';
  return `<h2 style="font-size:18px;margin-bottom:14px">🎯 أهداف الموظفات</h2>
  <div class="alert alert-info">الأهداف بالريال (للحساب الداخلي فقط) — شاشة العرض تُظهر النِّسب فقط.</div>
  <div class="card"><table class="table"><thead><tr><th>الموظفة</th><th>يومي</th><th>أسبوعي</th><th>شهري</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}
function targetModal(emp) {
  const tf = (period) => { const t = App.data.targets.find(x => x.scope === 'employee' && x.employee_id === emp.id && x.period_type === period); return t ? t.target_amount : ''; };
  Modal.show(`أهداف: ${Utils.escape(emp.full_name)}`, `
    <div class="form-group"><label class="form-label">الهدف اليومي</label><input type="number" min="0" class="form-control" id="tg-daily" value="${tf('daily')}"></div>
    <div class="form-group"><label class="form-label">الهدف الأسبوعي</label><input type="number" min="0" class="form-control" id="tg-weekly" value="${tf('weekly')}"></div>
    <div class="form-group"><label class="form-label">الهدف الشهري</label><input type="number" min="0" class="form-control" id="tg-monthly" value="${tf('monthly')}"></div>`,
    `<button class="btn btn-primary" id="tg-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('tg-save').addEventListener('click', async () => {
    try {
      for (const period of ['daily', 'weekly', 'monthly']) {
        const v = document.getElementById('tg-' + period).value;
        if (v === '' ) continue;
        const d = await rpc('set_target', { p_session_token: App.token, p_scope: 'employee', p_employee_id: emp.id, p_team_leader_id: null, p_period_type: period, p_target_amount: parseFloat(v) });
        if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      }
      Modal.close(); Toast.success('تم حفظ الأهداف'); await refresh();
    } catch (e) { Toast.error(e.message); }
  });
}

// ===== الإعدادات =====
function renderSettings() {
  const s = App.data.settings || {};
  return `<h2 style="font-size:18px;margin-bottom:14px">⚙️ إعدادات النظام</h2>
  <div class="card"><div class="card-body">
    <div class="form-group"><label class="form-label">اسم النظام</label><input class="form-control" id="st-name" value="${Utils.escape(s.system_name || '')}"></div>
    <div class="form-group"><label class="form-label">رابط الشعار</label><input class="form-control" id="st-logo" value="${Utils.escape(s.logo_url || '')}"></div>
    <div class="form-group"><label class="form-label">مدة تحديث شاشة العرض (ثانية)</label><input type="number" min="5" class="form-control" id="st-refresh" value="${s.refresh_seconds || 20}"></div>
    <button class="btn btn-primary" id="st-save">حفظ الإعدادات</button>
  </div></div>
  <div class="alert alert-info">حدود الحالات والألوان تُدار ضمن الإعدادات لاحقاً.</div>`;
}

// ===== ربط الأحداث =====
function bindShell() {
  document.querySelectorAll('[data-go]').forEach(a => a.addEventListener('click', e => { e.preventDefault(); navigate(a.dataset.go); }));
  const lo = document.getElementById('sp-logout');
  if (lo) lo.addEventListener('click', async () => { try { await rpc('logout', { p_token: App.token }); } catch (_) {} clearToken(); navigate('login'); });
  const pw = document.getElementById('sp-passwd');
  if (pw) pw.addEventListener('click', changePasswordModal);
  const burger = document.getElementById('sp-burger');
  if (burger) { burger.style.display = window.innerWidth <= 768 ? 'inline-flex' : 'none'; burger.addEventListener('click', () => document.getElementById('sp-sidebar').classList.toggle('open')); }
}
function bindPage() {
  const add = id => document.getElementById(id);
  if (add('emp-add')) add('emp-add').addEventListener('click', () => employeeModal(null));
  document.querySelectorAll('[data-emp-edit]').forEach(b => b.addEventListener('click', () => employeeModal(App.data.employees.find(e => e.id == b.dataset.empEdit))));
  document.querySelectorAll('[data-emp-del]').forEach(b => b.addEventListener('click', () => confirmDelete('employee', b.dataset.empDel)));
  if (add('tl-add')) add('tl-add').addEventListener('click', () => tlModal(null));
  document.querySelectorAll('[data-tl-edit]').forEach(b => b.addEventListener('click', () => tlModal(App.data.team_leaders.find(t => t.id == b.dataset.tlEdit))));
  document.querySelectorAll('[data-tl-del]').forEach(b => b.addEventListener('click', () => confirmDelete('team_leader', b.dataset.tlDel)));
  document.querySelectorAll('[data-tg-edit]').forEach(b => b.addEventListener('click', () => targetModal(App.data.employees.find(e => e.id == b.dataset.tgEdit))));
  if (add('st-save')) add('st-save').addEventListener('click', saveSettings);
  if (add('usr-add')) add('usr-add').addEventListener('click', () => userModal(null));
  document.querySelectorAll('[data-usr-edit]').forEach(b => b.addEventListener('click', () => userModal((App._users || []).find(u => u.id == b.dataset.usrEdit))));
  document.querySelectorAll('[data-usr-del]').forEach(b => b.addEventListener('click', () => deleteUser(b.dataset.usrDel)));
  document.querySelectorAll('[data-assign]').forEach(sel => sel.addEventListener('change', () => assignSale(sel.dataset.assign, sel.value)));
}
async function assignSale(saleId, empId) {
  if (!empId) return;
  try { const d = await rpc('assign_sale', { p_session_token: App.token, p_sale_id: parseInt(saleId), p_employee_id: parseInt(empId) });
    if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
    Toast.success('تم الإسناد'); App._review = null; render();
  } catch (e) { Toast.error(e.message); }
}
function confirmDelete(kind, id) {
  if (!confirm('هل أنت متأكد من الحذف؟')) return;
  const fn = kind === 'employee' ? 'delete_employee' : 'delete_team_leader';
  rpc(fn, { p_session_token: App.token, p_id: parseInt(id) }).then(async d => {
    if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
    Toast.success('تم الحذف'); await refresh();
  }).catch(e => Toast.error(e.message));
}
async function saveSettings() {
  const cur = App.data.settings || {};
  const next = Object.assign({}, cur, {
    system_name: document.getElementById('st-name').value.trim(),
    logo_url: document.getElementById('st-logo').value.trim(),
    refresh_seconds: parseInt(document.getElementById('st-refresh').value) || 20,
  });
  try {
    const d = await rpc('update_settings', { p_session_token: App.token, p_value: next });
    if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
    Toast.success('تم الحفظ'); await refresh();
  } catch (e) { Toast.error(e.message); }
}

// إعادة تحميل البيانات ثم إعادة الرسم
async function refresh() { try { await loadAppData(); render(); } catch (e) { if (!handleSessionError(e.message)) Toast.error(e.message); } }

// ===== المستخدمون (admin) =====
function renderUsers() {
  if (!App._users) {
    rpc('get_users', { p_session_token: App.token }).then(d => {
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      App._users = d.users || []; if (App.page === 'users') render();
    }).catch(e => Toast.error(e.message));
    return '<div class="card"><div class="card-body">⏳ جارٍ التحميل…</div></div>';
  }
  const rows = App._users.map(u => `<tr>
      <td>${Utils.escape(u.full_name)}</td>
      <td>${Utils.escape(u.username)}</td>
      <td>${roleLabel(u.role)}</td>
      <td>${u.is_active ? '<span class="badge" style="background:var(--success)">نشط</span>' : '<span class="badge" style="background:var(--muted)">موقوف</span>'}</td>
      <td>${u.last_login_at ? Utils.formatDate(u.last_login_at) : '—'}</td>
      <td><button class="btn btn-sm btn-warning" data-usr-edit="${u.id}">تعديل</button>
          ${u.id !== App.me.id ? `<button class="btn btn-sm btn-danger" data-usr-del="${u.id}">حذف</button>` : ''}</td>
    </tr>`).join('') || '<tr><td colspan="6" style="text-align:center;padding:24px;color:var(--muted)">لا يوجد مستخدمون</td></tr>';
  return `<div style="display:flex;justify-content:space-between;margin-bottom:14px">
      <h2 style="font-size:18px">🛡️ المستخدمون (${App._users.length})</h2>
      <button class="btn btn-primary" id="usr-add">➕ إضافة مستخدم</button></div>
    <div class="card"><table class="table">
      <thead><tr><th>الاسم</th><th>المستخدم</th><th>الدور</th><th>الحالة</th><th>آخر دخول</th><th></th></tr></thead>
      <tbody>${rows}</tbody></table></div>`;
}
function userModal(u) {
  const roles = [['admin', 'مدير'], ['manager', 'مشرف'], ['team_leader', 'تيم ليدر']]
    .map(([v, l]) => `<option value="${v}" ${u && u.role === v ? 'selected' : ''}>${l}</option>`).join('');
  Modal.show(u ? 'تعديل مستخدم' : 'إضافة مستخدم', `
    <div class="form-group"><label class="form-label">الاسم *</label><input class="form-control" id="us-name" value="${u ? Utils.escape(u.full_name) : ''}"></div>
    <div class="form-group"><label class="form-label">اسم المستخدم *</label><input class="form-control" id="us-username" value="${u ? Utils.escape(u.username) : ''}"></div>
    <div class="form-group"><label class="form-label">البريد</label><input class="form-control" id="us-email" value="${u ? Utils.escape(u.email || '') : ''}"></div>
    <div class="form-group"><label class="form-label">الدور *</label><select class="form-control" id="us-role">${roles}</select></div>
    <div class="form-group"><label class="form-label">${u ? 'كلمة مرور جديدة (اتركها فارغة للإبقاء)' : 'كلمة المرور *'}</label><input type="text" class="form-control" id="us-pass" placeholder="${u ? '••••••' : '6 أحرف على الأقل'}"></div>
    <div class="form-group"><label><input type="checkbox" id="us-active" ${!u || u.is_active ? 'checked' : ''}> نشط</label></div>`,
    `<button class="btn btn-primary" id="us-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('us-save').addEventListener('click', async () => {
    const name = document.getElementById('us-name').value.trim();
    const username = document.getElementById('us-username').value.trim();
    if (!name || !username) { Toast.error('الاسم واسم المستخدم مطلوبان'); return; }
    try {
      const d = await rpc('upsert_user', {
        p_session_token: App.token, p_id: u ? u.id : null, p_username: username,
        p_email: document.getElementById('us-email').value.trim(), p_full_name: name,
        p_role: document.getElementById('us-role').value, p_is_active: document.getElementById('us-active').checked,
        p_password: document.getElementById('us-pass').value || null,
      });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم الحفظ'); App._users = null; render();
    } catch (e) { Toast.error(e.message); }
  });
}
function deleteUser(id) {
  if (!confirm('هل أنت متأكد من حذف المستخدم؟')) return;
  rpc('delete_user', { p_session_token: App.token, p_id: parseInt(id) }).then(d => {
    if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
    Toast.success('تم الحذف'); App._users = null; render();
  }).catch(e => Toast.error(e.message));
}

// ===== يحتاج مراجعة (مبيعات غير مطابقة) =====
function renderReview() {
  if (!App._review) {
    rpc('get_unmatched', { p_session_token: App.token }).then(d => {
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      App._review = d; if (App.page === 'review') render();
    }).catch(e => Toast.error(e.message));
    return '<div class="card"><div class="card-body">⏳ جارٍ التحميل…</div></div>';
  }
  const items = App._review.items || [];
  const empOpts = App.data.employees.filter(e => e.is_active).map(e => `<option value="${e.id}">${Utils.escape(e.full_name)}</option>`).join('');
  const stripHtml = s => String(s || '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').trim();
  const canAssign = Perms.isAdmin();
  const rows = items.map(it => `<tr>
      <td>${Utils.formatDate(it.sale_date)}</td>
      <td>${Utils.escape(it.reference || '-')}</td>
      <td style="font-size:12px;color:var(--muted);max-width:280px">${Utils.escape(stripHtml(it.notes) || '—')}</td>
      <td>${canAssign ? `<select class="form-control" data-assign="${it.id}" style="padding:5px"><option value="">— أسنِد لموظفة —</option>${empOpts}</select>` : '—'}</td>
    </tr>`).join('') || '<tr><td colspan="4" style="text-align:center;padding:24px;color:var(--success)">✅ لا توجد مبيعات تحتاج مراجعة</td></tr>';
  return `<h2 style="font-size:18px;margin-bottom:6px">⚠️ يحتاج مراجعة (${App._review.count})</h2>
  <div class="alert alert-info">مبيعات لم يُطابَق اسم الموظفة فيها (أو بلا اسم). أسنِدها يدوياً حتى لا يضيع أي مبلغ. <strong>المبالغ مخفية حفاظاً على السرّية — تُعرض النِّسب فقط في اللوحة.</strong></div>
  <div class="card"><table class="table">
    <thead><tr><th>التاريخ</th><th>رقم العرض</th><th>المعلومات الإضافية (notes)</th><th>الإسناد</th></tr></thead>
    <tbody>${rows}</tbody></table></div>
  ${items.length >= 200 ? '<div class="alert alert-info">يُعرض أول 200 — أسنِد البعض لتظهر البقية.</div>' : ''}`;
}

// ===== تغيير كلمة المرور =====
function changePasswordModal() {
  Modal.show('تغيير كلمة المرور', `
    <div class="form-group"><label class="form-label">كلمة المرور الحالية</label><input type="password" class="form-control" id="cp-old"></div>
    <div class="form-group"><label class="form-label">كلمة المرور الجديدة</label><input type="password" class="form-control" id="cp-new" placeholder="6 أحرف على الأقل"></div>
    <div class="form-group"><label class="form-label">تأكيد الجديدة</label><input type="password" class="form-control" id="cp-new2"></div>`,
    `<button class="btn btn-primary" id="cp-save">حفظ</button><button class="btn btn-secondary" onclick="Modal.close()">إلغاء</button>`);
  document.getElementById('cp-save').addEventListener('click', async () => {
    const o = document.getElementById('cp-old').value, n = document.getElementById('cp-new').value, n2 = document.getElementById('cp-new2').value;
    if (n !== n2) { Toast.error('كلمتا المرور غير متطابقتين'); return; }
    try {
      const d = await rpc('change_my_password', { p_session_token: App.token, p_old: o, p_new: n });
      if (!d.ok) { if (!handleSessionError(d.message)) Toast.error(d.message); return; }
      Modal.close(); Toast.success('تم تغيير كلمة المرور');
    } catch (e) { Toast.error(e.message); }
  });
}

// ===== شاشة العرض المباشر (عامة، بلا تسجيل دخول) =====
let LIVE_CFG = null, LIVE_TIMER = null;
async function startLiveDisplay() {
  try { LIVE_CFG = await rpc('get_public_settings'); } catch (_) { LIVE_CFG = { system_name: SYSTEM_NAME, refresh_seconds: 20, status_thresholds: DEFAULT_STATUS_THRESHOLDS }; }
  await renderLiveDisplay();
  if (LIVE_TIMER) clearInterval(LIVE_TIMER);
  LIVE_TIMER = setInterval(renderLiveDisplay, (LIVE_CFG.refresh_seconds || 20) * 1000);
}
async function renderLiveDisplay() {
  let rows = [];
  try { const { data } = await window.sb.from('live_display').select('*'); rows = data || []; } catch (_) {}
  const th = (LIVE_CFG && LIVE_CFG.status_thresholds && LIVE_CFG.status_thresholds.length) ? LIVE_CFG.status_thresholds : DEFAULT_STATUS_THRESHOLDS;
  const colorFor = (pct) => statusForPercentage(pct, th).color;
  const cards = rows.map(r => {
    const m = r.monthly_pct == null ? null : Number(r.monthly_pct);
    const col = m == null ? '#94a3b8' : colorFor(m);
    return `<div class="live-card" style="border-top-color:${col}">
      <div style="font-size:18px;font-weight:800;margin-bottom:2px">${Utils.escape(r.employee_name)}</div>
      <div style="font-size:13px;color:var(--muted);margin-bottom:10px">${Utils.escape(r.team_leader_name || '-')}</div>
      <div class="live-pct" style="color:${col}">${m == null ? '—' : Utils.pct(m)}</div>
      <div style="display:flex;gap:14px;margin-top:10px;font-size:13px;color:var(--muted)">
        <span>يومي: <strong>${r.daily_pct == null ? '—' : Utils.pct(r.daily_pct)}</strong></span>
        <span>أسبوعي: <strong>${r.weekly_pct == null ? '—' : Utils.pct(r.weekly_pct)}</strong></span>
      </div>
      ${r.status ? `<div style="margin-top:8px"><span class="badge" style="background:${col}">${Utils.escape(r.status)}</span></div>` : ''}
    </div>`;
  }).join('') || '<div style="grid-column:1/-1;text-align:center;color:#fff;padding:40px">لا توجد بيانات للعرض بعد</div>';
  document.getElementById('app').innerHTML = `
    <div style="min-height:100vh;background:linear-gradient(135deg,#044376,#06579F)">
      <div style="padding:20px 28px;display:flex;align-items:center;justify-content:space-between;color:#fff">
        <h1 style="font-size:24px;font-weight:800">📊 ${Utils.escape((LIVE_CFG && LIVE_CFG.system_name) || SYSTEM_NAME)}</h1>
        <div style="font-size:14px;opacity:.85">${new Date().toLocaleString('ar-SA')}</div>
      </div>
      <div class="live-grid">${cards}</div>
    </div>`;
}
