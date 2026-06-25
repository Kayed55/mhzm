/*!
 * مؤشر أداء موظفات المبيعات — الثوابت والإعدادات العامة
 * @module constants
 */
'use strict';

// إعدادات Supabase — املأها بعد إنشاء المشروع الجديد (anon key عام، آمن للواجهة)
const SUPABASE_CONFIG = {
  url:     'https://xcywapkfchvjpkrqqdnd.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhjeXdhcGtmY2h2anBrcnFxZG5kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzMTQ4OTgsImV4cCI6MjA5Nzg5MDg5OH0.oBz5gvk5srr3wY11kpaaME4GtCDSrUmWpb_kpgl6Ulg',
  enableRealtime: true,
  syncIntervalMs: 30000,
};

// اسم النظام الافتراضي (يُحدَّث من الإعدادات لاحقاً)
let SYSTEM_NAME = 'نظام مساند الجودة';

// حالات الأداء الافتراضية (تُحمَّل من settings.status_thresholds وتُعدَّل من اللوحة)
const DEFAULT_STATUS_THRESHOLDS = [
  { label: 'ممتاز',        min: 100, color: '#16a34a' },
  { label: 'جيد جدًا',     min: 85,  color: '#0ea5e9' },
  { label: 'جيد',          min: 70,  color: '#3b82f6' },
  { label: 'يحتاج متابعة', min: 50,  color: '#f59e0b' },
  { label: 'ضعيف',         min: 0,   color: '#ef4444' },
];

// إرجاع حالة/لون حسب النسبة بناءً على الحدود الفعّالة
function statusForPercentage(pct, thresholds) {
  const bands = (thresholds && thresholds.length ? thresholds : DEFAULT_STATUS_THRESHOLDS)
    .slice().sort((a, b) => b.min - a.min);
  const p = Number(pct) || 0;
  for (const b of bands) if (p >= b.min) return b;
  return bands[bands.length - 1];
}

// الأدوار
const ROLES = { ADMIN: 'admin', MANAGER: 'manager', TEAM_LEADER: 'team_leader' };
