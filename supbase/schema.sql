-- شغّل هذا الملف كاملاً في Supabase > SQL Editor
create extension if not exists pgcrypto;

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text not null default '',
  role text not null default 'supervisor' check (role in ('supervisor','engineer'))
);

create table projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  lat double precision not null,
  lng double precision not null,
  radius_m double precision not null default 150,
  created_at timestamptz default now()
);

create table project_members (
  project_id uuid references projects on delete cascade,
  user_id uuid references profiles on delete cascade,
  primary key (project_id, user_id)
);

create table inspections (
  id uuid primary key,
  project_id uuid not null references projects,
  supervisor_id uuid not null constraint inspections_supervisor_id_fkey references profiles,
  location_label text not null,
  notes text,
  status text not null default 'draft' check (status in ('draft','submitted','approved','needs_fix')),
  has_defects boolean default false,
  fix_deadline date,
  expected_items int not null,
  submit_lat double precision,
  submit_lng double precision,
  submitted_at timestamptz,
  review_note text,
  reviewed_by uuid references profiles,
  reviewed_at timestamptz,
  created_at timestamptz default now()
);


create table inspection_items (
  id uuid primary key,
  inspection_id uuid not null references inspections on delete cascade,
  item_key text not null,
  title text not null,
  critical boolean not null default false,
  status text not null check (status in ('ok','defect')),
  note text,
  photo_path text,
  captured_at timestamptz,
  lat double precision,
  lng double precision,
  unique (inspection_id, item_key)
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles on delete cascade,
  inspection_id uuid references inspections on delete cascade,
  message text not null,
  read boolean not null default false,
  created_at timestamptz default now()
);

-- ===== دوال مساعدة =====
create function my_role() returns text language sql stable security definer set search_path=public as
$$ select role from profiles where id = auth.uid() $$;

create function is_member(pid uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from project_members where project_id = pid and user_id = auth.uid()) $$;

-- إنشاء profile تلقائياً (الدور من user_metadata.role عند إنشاء المستخدم من لوحة Supabase)
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''),
          case when new.raw_user_meta_data->>'role' = 'engineer' then 'engineer' else 'supervisor' end);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- ===== تحقق السيرفر: النطاق الجغرافي + اكتمال التقرير =====
create function haversine_m(lat1 float8, lng1 float8, lat2 float8, lng2 float8) returns float8 language sql immutable as
$$ select 6371000*2*asin(sqrt(power(sin(radians(lat2-lat1)/2),2) + cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lng2-lng1)/2),2))) $$;

create function validate_submission() returns trigger language plpgsql security definer set search_path=public as $$
declare pr projects; n int; bad int;
begin
  if new.status = 'submitted' and (tg_op='INSERT' or old.status is distinct from 'submitted') then
    select * into pr from projects where id = new.project_id;
    if new.submit_lat is null or new.submit_lng is null
       or haversine_m(new.submit_lat,new.submit_lng,pr.lat,pr.lng) > pr.radius_m + 50 then
      raise exception 'GEOFENCE: خارج نطاق الموقع';
    end if;
    select count(*) into n from inspection_items where inspection_id = new.id;
    if n < new.expected_items then raise exception 'INCOMPLETE: بنود ناقصة'; end if;
    select count(*) into bad from inspection_items
      where inspection_id = new.id and ((critical or status='defect') and photo_path is null);
    if bad > 0 then raise exception 'INCOMPLETE: صور ناقصة'; end if;
    select count(*) into bad from inspection_items where inspection_id = new.id and status='defect' and coalesce(note,'')='';
    if bad > 0 then raise exception 'INCOMPLETE: وصف عيب ناقص'; end if;
    if exists(select 1 from inspection_items where inspection_id=new.id and status='defect') and new.fix_deadline is null then
      raise exception 'INCOMPLETE: مهلة التعديل مطلوبة';
    end if;
  end if;
  return new;
end $$;
create trigger trg_validate before insert or update on inspections for each row execute function validate_submission();

-- ===== إشعارات فورية =====
create function notify_status() returns trigger language plpgsql security definer set search_path=public as $$
declare pname text;
begin
  select name into pname from projects where id = new.project_id;
  if new.status = 'submitted' and old.status is distinct from 'submitted' then
    insert into notifications(user_id, inspection_id, message)
    select pm.user_id, new.id,
      case when new.has_defects then '⚠️ تقرير بعيوب في '||pname||' — '||new.location_label||' (مهلة '||coalesce(new.fix_deadline::text,'-')||')'
           else 'تقرير جديد للمراجعة في '||pname||' — '||new.location_label end
    from project_members pm join profiles p on p.id = pm.user_id where pm.project_id = new.project_id and p.role='engineer';
  elsif new.status in ('approved','needs_fix') and old.status is distinct from new.status then
    insert into notifications(user_id, inspection_id, message)
    values (new.supervisor_id, new.id, case when new.status='approved' then '✅ تم اعتماد: ' else '🔧 مطلوب تعديل: ' end || new.location_label);
  end if;
  return new;
end $$;
create trigger trg_notify after update on inspections for each row execute function notify_status();

-- ===== الصلاحيات (RLS) =====
alter table profiles enable row level security;
alter table projects enable row level security;
alter table project_members enable row level security;
alter table inspections enable row level security;
alter table inspection_items enable row level security;
alter table notifications enable row level security;

create function shares_project(uid uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from project_members a join project_members b on a.project_id=b.project_id
                 where a.user_id = auth.uid() and b.user_id = uid) $$;
create policy p_prof_sel on profiles for select using (auth.uid() = id or shares_project(id));
create policy p_proj_sel on projects for select using (is_member(id));
create policy p_pm_sel on project_members for select using (user_id = auth.uid());

-- المشرف: ينشئ/يعدّل تقاريره وهي مسودة فقط
create policy i_sel on inspections for select using (is_member(project_id));
create policy i_ins on inspections for insert with check (my_role()='supervisor' and supervisor_id=auth.uid() and is_member(project_id));
create policy i_upd_sup on inspections for update using (my_role()='supervisor' and supervisor_id=auth.uid() and status='draft')
  with check (supervisor_id=auth.uid());
-- المهندس: يعتمد أو يطلب تعديل على تقارير مشاريعه فقط
create policy i_upd_eng on inspections for update using (my_role()='engineer' and is_member(project_id) and status in ('submitted','needs_fix'))
  with check (status in ('approved','needs_fix'));

create policy it_sel on inspection_items for select using (exists(select 1 from inspections i where i.id=inspection_id and is_member(i.project_id)));
create policy it_ins on inspection_items for insert with check (exists(select 1 from inspections i where i.id=inspection_id and i.supervisor_id=auth.uid() and i.status='draft'));
create policy it_upd on inspection_items for update using (exists(select 1 from inspections i where i.id=inspection_id and i.supervisor_id=auth.uid() and i.status='draft'));

create policy n_sel on notifications for select using (user_id = auth.uid());
create policy n_upd on notifications for update using (user_id = auth.uid());

-- realtime للإشعارات
alter publication supabase_realtime add table notifications;

-- ===== التخزين =====
insert into storage.buckets(id, name, public) values ('inspection-photos','inspection-photos', false) on conflict do nothing;
create policy ph_ins on storage.objects for insert to authenticated
  with check (bucket_id='inspection-photos' and is_member(((storage.foldername(name))[1])::uuid));
create policy ph_upd on storage.objects for update to authenticated
  using (bucket_id='inspection-photos' and is_member(((storage.foldername(name))[1])::uuid));
create policy ph_sel on storage.objects for select to authenticated
  using (bucket_id='inspection-photos' and is_member(((storage.foldername(name))[1])::uuid));

-- ===== مثال بيانات (عدّل الإحداثيات ثم نفّذ بعد إنشاء المستخدمين) =====
-- insert into projects(name,lat,lng,radius_m) values ('مركز التميز - بلبيس', 30.4200, 31.5600, 150);
-- insert into project_members select (select id from projects limit 1), id from profiles;
