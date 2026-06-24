# تطبيق قاعدة البيانات

## الطريقة الأسهل (نسخ واحد)
1. افتح Supabase → **SQL Editor** → **New query**.
2. الصق محتوى **`APPLY_ALL.sql`** كاملاً → **Run**.
3. فعّل (إن لزم): Database → Extensions → `pgcrypto` (موجود)، ولاحقاً `pg_cron`,`pg_net`,`vault` للمرحلة 3.

## أو ملفاً ملفاً (بالترتيب)
`01_schema.sql` → `02_security_rls.sql` → `03_seed.sql` → `04_auth.sql` → `05_rpc_core.sql`

## الدخول الافتراضي
`admin` / `Admin@123` — **غيّره فوراً بعد أول دخول**.
