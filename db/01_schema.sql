-- ============================================================================
-- مؤشر أداء موظفات المبيعات — مخطط قاعدة البيانات (Schema)
-- ============================================================================
-- مبدأ أمني محوري:
--   • المبالغ المالية تُخزَّن فقط في جداول محمية (sales_records / performance_logs).
--   • شاشة العرض العامة تقرأ النِّسب فقط عبر VIEW عام (live_display) بلا أي مبلغ.
--   • أسرار قيود تُخزَّن مشفّرة عبر Supabase Vault (لا نصّ واضح).
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- المصادقة والصلاحيات
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id            bigint primary key generated always as identity,
  username      varchar(100) unique not null,
  email         varchar(255) unique,
  password      text not null,                       -- bcrypt hash فقط
  full_name     varchar(255) not null,
  role          varchar(30) not null default 'team_leader'
                  check (role in ('admin','manager','team_leader')),
  is_active     boolean not null default true,
  must_change_password boolean not null default true,
  last_login_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.permissions (
  key         varchar(60) primary key,              -- مثل: manage_employees
  description text
);

create table if not exists public.role_permissions (
  role            varchar(30) not null,
  permission_key  varchar(60) not null references public.permissions(key) on delete cascade,
  primary key (role, permission_key)
);

create table if not exists public.sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      bigint not null references public.users(id) on delete cascade,
  role         varchar(30) not null,
  token        char(64) unique not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  last_used_at timestamptz not null default now()
);
create index if not exists idx_sessions_token on public.sessions(token);

-- ---------------------------------------------------------------------------
-- التيم ليدرز والموظفات
-- ---------------------------------------------------------------------------
create table if not exists public.team_leaders (
  id          bigint primary key generated always as identity,
  full_name   varchar(255) not null,
  user_id     bigint references public.users(id) on delete set null,  -- حساب الدخول (اختياري)
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.employees (
  id              bigint primary key generated always as identity,
  full_name       varchar(255) not null,
  employee_code   varchar(100) unique,                 -- الرقم الوظيفي الداخلي
  qoyod_ref       varchar(150),                        -- مُعرّف الموظفة في قيود (للربط)
  team_leader_id  bigint references public.team_leaders(id) on delete set null,
  show_in_display boolean not null default true,       -- الظهور في شاشة العرض
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_employees_tl on public.employees(team_leader_id);
create index if not exists idx_employees_qoyod on public.employees(qoyod_ref);

-- ---------------------------------------------------------------------------
-- الأهداف (لكل موظفة / تيم ليدر، لكل فترة)
-- ---------------------------------------------------------------------------
create table if not exists public.performance_targets (
  id             bigint primary key generated always as identity,
  scope          varchar(20) not null check (scope in ('employee','team_leader')),
  employee_id    bigint references public.employees(id) on delete cascade,
  team_leader_id bigint references public.team_leaders(id) on delete cascade,
  period_type    varchar(10) not null check (period_type in ('daily','weekly','monthly')),
  target_amount  numeric(14,2) not null check (target_amount >= 0),  -- محمي
  effective_from date not null default current_date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check ( (scope='employee' and employee_id is not null)
       or (scope='team_leader' and team_leader_id is not null) )
);
create index if not exists idx_targets_emp on public.performance_targets(employee_id, period_type);

-- ---------------------------------------------------------------------------
-- مبيعات قيود (محمي — يحوي المبالغ الفعلية، لا يصله anon)
-- ---------------------------------------------------------------------------
create table if not exists public.sales_records (
  id               bigint primary key generated always as identity,
  employee_id      bigint references public.employees(id) on delete cascade,
  qoyod_invoice_id varchar(150),                       -- لمنع التكرار
  amount           numeric(14,2) not null default 0,   -- محمي
  sale_date        date not null,
  raw              jsonb,                              -- استجابة قيود الخام (تدقيق)
  synced_at        timestamptz not null default now(),
  unique (qoyod_invoice_id)
);
create index if not exists idx_sales_emp_date on public.sales_records(employee_id, sale_date);

-- ---------------------------------------------------------------------------
-- لقطات الأداء المحسوبة (المبالغ محمية، النسبة هي المعروضة)
-- ---------------------------------------------------------------------------
create table if not exists public.performance_logs (
  id              bigint primary key generated always as identity,
  scope           varchar(20) not null check (scope in ('employee','team_leader')),
  employee_id     bigint references public.employees(id) on delete cascade,
  team_leader_id  bigint references public.team_leaders(id) on delete cascade,
  period_type     varchar(10) not null check (period_type in ('daily','weekly','monthly')),
  period_date     date not null,                      -- بداية الفترة
  achieved_amount numeric(14,2) not null default 0,   -- محمي
  target_amount   numeric(14,2) not null default 0,   -- محمي
  percentage      numeric(6,2) not null default 0,    -- عام (للعرض)
  status          varchar(30),                        -- ممتاز/جيد جدًا/...
  computed_at     timestamptz not null default now(),
  unique (scope, employee_id, team_leader_id, period_type, period_date)
);
create index if not exists idx_perf_lookup on public.performance_logs(scope, period_type, period_date);

-- ---------------------------------------------------------------------------
-- الإعدادات (صفّ JSONB واحد) + إعدادات قيود (الأسرار عبر Vault)
-- ---------------------------------------------------------------------------
create table if not exists public.settings (
  key         varchar(60) primary key,               -- 'system'
  value       jsonb not null default '{}'::jsonb,     -- الاسم/الشعار/الألوان/الحدود/الترتيب/فترة التحديث
  updated_at  timestamptz not null default now(),
  updated_by  bigint references public.users(id) on delete set null
);


-- سجل المزامنة والأخطاء
create table if not exists public.sync_logs (
  id              bigint primary key generated always as identity,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          varchar(20) not null default 'running'
                    check (status in ('running','success','error','partial')),
  records_synced  int not null default 0,
  message         text,
  triggered_by    varchar(20) not null default 'auto'   -- auto | manual
);
create index if not exists idx_sync_logs_time on public.sync_logs(started_at desc);

-- التدقيق
create table if not exists public.audit_logs (
  id          bigint primary key generated always as identity,
  user_id     bigint references public.users(id) on delete set null,
  user_name   varchar(255),
  role        varchar(30),
  action      varchar(60) not null,
  entity_type varchar(60),
  entity_id   bigint,
  details     text,
  ip_address  varchar(60),
  "timestamp" timestamptz not null default now()
);
create index if not exists idx_audit_time on public.audit_logs("timestamp" desc);

-- ---------------------------------------------------------------------------
-- VIEW عام لشاشة العرض — النِّسب فقط، بلا أي مبلغ مالي
-- ---------------------------------------------------------------------------
create or replace view public.live_display as
select
  e.id                as employee_id,
  e.full_name         as employee_name,
  tl.full_name        as team_leader_name,
  max(case when pl.period_type='daily'   then pl.percentage end) as daily_pct,
  max(case when pl.period_type='weekly'  then pl.percentage end) as weekly_pct,
  max(case when pl.period_type='monthly' then pl.percentage end) as monthly_pct,
  max(case when pl.period_type='monthly' then pl.status end)     as status
from public.employees e
left join public.team_leaders tl on tl.id = e.team_leader_id
left join public.performance_logs pl
  on pl.scope='employee' and pl.employee_id = e.id
  and pl.period_date = (case pl.period_type
                          when 'daily'   then current_date
                          when 'weekly'  then date_trunc('week', current_date)::date
                          when 'monthly' then date_trunc('month', current_date)::date end)
where e.is_active and e.show_in_display
group by e.id, e.full_name, tl.full_name;
