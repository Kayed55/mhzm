-- ============================================================================
-- البذور: الصلاحيات + مدير افتراضي + الإعدادات الافتراضية
-- ============================================================================

insert into public.permissions(key, description) values
  ('manage_users','إدارة المستخدمين والأدوار'),
  ('manage_employees','إدارة الموظفات'),
  ('manage_team_leaders','إدارة التيم ليدرز'),
  ('manage_targets','إدارة الأهداف'),
  ('manage_settings','إعدادات النظام'),
  ('manage_qoyod','إعدادات قيود والمزامنة'),
  ('view_reports','عرض التقارير'),
  ('view_all','عرض كل البيانات'),
  ('view_own_team','عرض الفريق التابع فقط')
on conflict (key) do nothing;

-- خريطة الأدوار → الصلاحيات
insert into public.role_permissions(role, permission_key) values
  ('admin','manage_users'),('admin','manage_employees'),('admin','manage_team_leaders'),
  ('admin','manage_targets'),('admin','manage_settings'),('admin','manage_qoyod'),
  ('admin','view_reports'),('admin','view_all'),
  ('manager','view_all'),('manager','view_reports'),
  ('team_leader','view_own_team'),('team_leader','view_reports')
on conflict do nothing;

-- مدير افتراضي (كلمة المرور مجزّأة bcrypt) — غيّرها بعد أول دخول
insert into public.users(username, email, password, full_name, role, is_active, must_change_password)
values ('admin','admin@example.com',
        extensions.crypt('Admin@123', extensions.gen_salt('bf',10)),
        'مدير النظام','admin', true, true)
on conflict (username) do nothing;

-- الإعدادات الافتراضية (الاسم/الألوان/حدود الحالات/الترتيب/فترة التحديث)
insert into public.settings(key, value) values
('system', jsonb_build_object(
  'system_name','مؤشر أداء موظفات المبيعات',
  'logo_url','',
  'refresh_seconds', 20,
  'display_order','monthly_desc',         -- ترتيب شاشة العرض
  'status_thresholds', jsonb_build_array(
    jsonb_build_object('label','ممتاز','min',100,'color','#16a34a'),
    jsonb_build_object('label','جيد جدًا','min',85,'color','#0ea5e9'),
    jsonb_build_object('label','جيد','min',70,'color','#3b82f6'),
    jsonb_build_object('label','يحتاج متابعة','min',50,'color','#f59e0b'),
    jsonb_build_object('label','ضعيف','min',0,'color','#ef4444')
  )
))
on conflict (key) do nothing;
