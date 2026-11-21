-- الخطوة الثانية: شغّله بعد إنشاء المستخدمين (المشرف والمهندس) من Authentication > Users
-- عدّل القيم بين علامات التنصيص ثم نفّذ الملف كله مرة واحدة.

-- 1) أنشئ المشروع (إحداثيات الموقع من خرائط جوجل: اضغط مطولاً على الموقع وانسخ الرقمين)
with p as (
  insert into projects(name, lat, lng, radius_m)
  values ('مركز التميز للطاقة المتجددة - بلبيس', 30.4200, 31.5600, 150)   -- <== عدّل
  returning id
)
-- 2) اربط المشرف والمهندس بالمشروع (بالبريد الإلكتروني لكل واحد)
insert into project_members(project_id, user_id)
select p.id, u.id
from p, auth.users u
where u.email in ('supervisor@example.com', 'engineer@example.com');      -- <== عدّل

-- 3) تحقق: لازم يظهر صفّين (مشرف + مهندس) بالأدوار الصحيحة
select pr.full_name, pr.role, au.email
from project_members pm
join profiles pr on pr.id = pm.user_id
join auth.users au on au.id = pm.user_id;
