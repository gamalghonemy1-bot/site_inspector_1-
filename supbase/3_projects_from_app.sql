-- شغّله مرة واحدة في SQL Editor (بعد 1_schema.sql): يسمح للمهندس بإنشاء المشاريع وربط المشرفين من التطبيق

create or replace function create_project(p_name text, p_lat float8, p_lng float8, p_radius float8)
returns uuid language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
  if my_role() is distinct from 'engineer' then raise exception 'NOT_ALLOWED'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'اسم المشروع مطلوب'; end if;
  insert into projects(name, lat, lng, radius_m) values (trim(p_name), p_lat, p_lng, greatest(p_radius, 30)) returning id into pid;
  insert into project_members(project_id, user_id) values (pid, auth.uid());
  return pid;
end $$;

create or replace function update_project(p_project uuid, p_name text, p_lat float8, p_lng float8, p_radius float8)
returns void language plpgsql security definer set search_path=public as $$
begin
  if my_role() is distinct from 'engineer' or not is_member(p_project) then raise exception 'NOT_ALLOWED'; end if;
  update projects set name = trim(p_name), lat = p_lat, lng = p_lng, radius_m = greatest(p_radius, 30) where id = p_project;
end $$;

create or replace function add_member(p_project uuid, p_email text)
returns text language plpgsql security definer set search_path=public as $$
declare uid uuid; nm text;
begin
  if my_role() is distinct from 'engineer' or not is_member(p_project) then raise exception 'NOT_ALLOWED'; end if;
  select u.id, pr.full_name into uid, nm from auth.users u join profiles pr on pr.id = u.id where lower(u.email) = lower(trim(p_email));
  if uid is null then raise exception 'لا يوجد مستخدم بهذا البريد'; end if;
  insert into project_members(project_id, user_id) values (p_project, uid) on conflict do nothing;
  return nm;
end $$;

create or replace function remove_member(p_project uuid, p_user uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if my_role() is distinct from 'engineer' or not is_member(p_project) then raise exception 'NOT_ALLOWED'; end if;
  if p_user = auth.uid() then raise exception 'لا يمكنك إزالة نفسك'; end if;
  delete from project_members where project_id = p_project and user_id = p_user;
end $$;

create or replace function list_members(p_project uuid)
returns table(user_id uuid, full_name text, email text, role text)
language plpgsql security definer set search_path=public as $$
begin
  if not is_member(p_project) then raise exception 'NOT_ALLOWED'; end if;
  return query select pr.id, pr.full_name, u.email::text, pr.role
    from project_members pm join profiles pr on pr.id = pm.user_id join auth.users u on u.id = pm.user_id
    where pm.project_id = p_project order by pr.role, pr.full_name;
end $$;

revoke all on function create_project(text,float8,float8,float8), update_project(uuid,text,float8,float8,float8),
  add_member(uuid,text), remove_member(uuid,uuid), list_members(uuid) from public, anon;
grant execute on function create_project(text,float8,float8,float8), update_project(uuid,text,float8,float8,float8),
  add_member(uuid,text), remove_member(uuid,uuid), list_members(uuid) to authenticated;
