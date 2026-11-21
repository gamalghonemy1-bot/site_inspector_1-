# متابعة مشرفي الكهرباء (Flutter + Supabase)

## الخطوات
1. Supabase: أنشئ مشروعاً ← SQL Editor ← الصق `supabase/schema.sql` ونفّذه.
2. Authentication > Users > Add user: أنشئ حساب المشرف مع User Metadata: {"role":"supervisor","full_name":"الاسم"}
   وحساب المهندس: {"role":"engineer","full_name":"الاسم"}.
3. أضف مشروعاً في جدول projects (lat/lng/radius_m) واربط المستخدمين في project_members.
4. GitHub: ارفع هذا المجلد كـ repo ← Settings > Secrets > Actions: أضف SUPABASE_URL و SUPABASE_ANON_KEY.
5. Actions > Build APK > Run workflow ← حمّل الـ APK من Artifacts وثبّته.
