# 📊 مؤشر أداء موظفات المبيعات

لوحة مؤشرات أداء لحظية لموظفات المبيعات، تسحب البيانات تلقائياً من **قيود (Qoyod API)**،
وتعرض **نِسب الإنجاز فقط** (دون أي مبالغ مالية) على شاشة عرض عامة، مع لوحة تحكم متكاملة.

## 🏗 المعمارية (نفس ستاك محزم + Edge Functions)
| الطبقة | التقنية |
|---|---|
| الواجهة | Vanilla JS (وحدات IIFE) + HTML/CSS — عربي RTL، Responsive |
| قاعدة البيانات | Supabase (PostgreSQL + RLS + Realtime) |
| المصادقة | جلسات برمز 64-hex + كلمات مرور bcrypt (لا Supabase Auth) |
| تكامل قيود | **Supabase Edge Functions (Deno)** — استدعاء سرّي على الخادم |
| أسرار قيود | **Supabase Vault (pgsodium)** — مشفّرة، تُفكّ على الخادم فقط |
| المزامنة التلقائية | pg_cron + pg_net تستدعي الـ Edge Function |
| النشر | Vercel (نشر تلقائي عند push) |

## 🔒 النموذج الأمني المحوري
- **المبالغ المالية** في جداول محمية (`sales_records`, `performance_logs`) — **لا يصلها anon إطلاقاً**.
- **شاشة العرض العامة** تقرأ `live_display` (VIEW) = **النِّسب فقط** عبر anon.
- **لوحة التحكم**: كل قراءة/كتابة عبر **RPCs بـ SECURITY DEFINER** تتحقّق من رمز الجلسة + الدور.
- **أسرار قيود** عبر Vault — لا نصّ واضح، تُعرض مُقنّعة في اللوحة.
- كل العمليات تُسجَّل في `audit_logs`.

## 👥 الأدوار
| الدور | الصلاحية |
|---|---|
| **Admin** | كامل |
| **Manager** | مشاهدة كل البيانات والتقارير |
| **Team Leader** | الفريق التابع له فقط |
| **Live Display** | عام بلا تسجيل دخول (نِسب فقط) |

## 📁 الهيكل
```
public/            الواجهة (تُنشر على Vercel)
  index.html
  css/styles.css
  js/              وحدات: 00-sync, 01-constants, 02-db, 03-core, 04-pages, 05-app, realtime-service
db/                هجرات SQL (تُطبَّق على Supabase بالترتيب)
  01_schema.sql  02_security_rls.sql  03_seed.sql  04_auth.sql  ...
supabase/functions/qoyod-sync/   Edge Function لمزامنة قيود
docs/
```

## 🚀 الإعداد
1. أنشئ مشروع Supabase جديد، وطبّق ملفات `db/*.sql` بالترتيب.
2. فعّل الإضافات: `pgcrypto`, `pg_cron`, `pg_net`, ووحدة Vault.
3. انشر Edge Function: `supabase functions deploy qoyod-sync` واضبط أسرارها.
4. ضع `SUPABASE_URL` و anon key في `public/js/01-constants.js`.
5. اربط المستودع بـ Vercel (نشر تلقائي).
6. سجّل الدخول بالمدير الافتراضي `admin / Admin@123` ثم **غيّر كلمة المرور فوراً**.

## ⚠️ ملاحظات
- لا تضع أي سرّ في الكود — استخدم Vault / متغيّرات البيئة.
- الافتراضي `Admin@123` للاختبار فقط — غيّره قبل الإنتاج.

---
🤖 تم البناء بمساعدة Claude Code.
