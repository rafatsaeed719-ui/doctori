-- =====================================================================
-- دكتوري — 0018: المراكز الطبية (عيادة فيها أكتر من دكتور وأكتر من تخصص)
-- * centers: the place (name, address, location, logo) with an owner (a doctor, or a manager account).
-- * center_members: owner / manager / reception staff and the doctors working there.
--   Each doctor has a share % of income (optionally per service kind); the rest is the center's.
-- * Each doctor gets a clinic row at the center (clinics.center_id) → bookings, hours and queue work as usual,
--   and center staff can run them for every doctor in the center.
-- * Income recorded at the center is the doctor's income row tagged with center_id; center expenses are separate.
--   Reports: per doctor (income, doctor share, center share, cases) and the center total net.
-- =====================================================================

create table public.centers (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (length(trim(name)) between 2 and 120),
  owner_id       uuid not null references public.profiles(id) on delete restrict,
  phone          text check (phone is null or length(phone) <= 30),
  address        text check (address is null or length(address) <= 300),
  governorate_id int references public.governorates(id),
  city_id        int references public.cities(id),
  area           text check (area is null or length(area) <= 120),
  lat            double precision check (lat is null or lat between -90 and 90),
  lng            double precision check (lng is null or lng between -180 and 180),
  logo_url       text check (logo_url is null or length(logo_url) <= 500),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
drop trigger if exists centers_touch on public.centers;
create trigger centers_touch before update on public.centers for each row execute function public.touch_updated_at();

create table public.center_members (
  center_id     uuid not null references public.centers(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  role          text not null check (role in ('owner', 'manager', 'reception', 'doctor')),
  status        text not null default 'active' check (status in ('invited', 'active', 'left')),
  share_percent numeric(5,2) check (share_percent is null or share_percent between 0 and 100),
  share_by_kind jsonb not null default '{}'::jsonb check (jsonb_typeof(share_by_kind) = 'object'),
  can_finance   boolean not null default false,
  clinic_id     uuid references public.clinics(id) on delete set null,
  invited_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (center_id, user_id, role)
);
create index if not exists idx_center_members_user on public.center_members (user_id);

alter table public.clinics add column if not exists center_id uuid references public.centers(id) on delete set null;
alter table public.doctor_income add column if not exists center_id uuid references public.centers(id) on delete set null;
create index if not exists idx_doctor_income_center on public.doctor_income (center_id, paid_on);

create table public.center_expenses (
  id         uuid primary key default gen_random_uuid(),
  center_id  uuid not null references public.centers(id) on delete cascade,
  category   text not null check (category in ('rent', 'salaries', 'supplies', 'utilities', 'equipment',
                                               'maintenance', 'lab', 'marketing', 'transport', 'other')),
  amount     numeric(12,2) not null check (amount > 0 and amount < 10000000),
  spent_on   date not null,
  reason     text check (reason is null or length(reason) <= 300),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_center_expenses_day on public.center_expenses (center_id, spent_on);

-- ---------------------------------------------------------------------
-- Who may do what
-- ---------------------------------------------------------------------
-- Staff of a center: owner/manager always; reception per flags. p_need: 'staff' | 'finance' | 'admin'
create or replace function public.center_can(p_center uuid, p_need text default 'staff') returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or exists (
    select 1 from center_members m join profiles p on p.id = m.user_id
    where m.center_id = p_center and m.user_id = auth.uid() and m.status = 'active' and not p.is_suspended
      and m.role in ('owner', 'manager', 'reception')
      and case p_need
            when 'staff' then true
            when 'finance' then m.role in ('owner', 'manager') or m.can_finance
            when 'admin' then m.role in ('owner', 'manager')
            when 'owner' then m.role = 'owner'
            else false end);
$$;

-- Center staff run bookings, patients and new patient accounts for every doctor working in their center.
create or replace function public.acts_for(p_doctor uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select (auth.uid() = p_doctor and exists (select 1 from profiles p where p.id = p_doctor and not p.is_suspended))
      or exists (
        select 1 from doctor_assistants a join profiles p on p.id = a.assistant_id
        where a.doctor_id = p_doctor and a.assistant_id = auth.uid() and not p.is_suspended
          and case p_perm
                when 'bookings' then a.can_bookings
                when 'patients' then a.can_patients
                when 'add_patients' then a.can_add_patients
                when 'medical' then a.can_medical
                when 'finance' then a.can_finance
                when 'any' then true
                else false end)
      or (p_perm in ('bookings', 'patients', 'add_patients', 'any') and exists (
        select 1 from center_members s
        join center_members d on d.center_id = s.center_id and d.user_id = p_doctor and d.role = 'doctor' and d.status = 'active'
        join profiles sp on sp.id = s.user_id and not sp.is_suspended
        join centers c on c.id = s.center_id and c.is_active
        where s.user_id = auth.uid() and s.status = 'active' and s.role in ('owner', 'manager', 'reception')));
$$;

alter table public.centers enable row level security;
alter table public.center_members enable row level security;
alter table public.center_expenses enable row level security;
create policy centers_read on public.centers for select using (true);
create policy center_members_read on public.center_members for select using (user_id = auth.uid() or public.center_can(center_id));
create policy center_expenses_read on public.center_expenses for select using (public.center_can(center_id, 'finance'));
revoke all on public.centers, public.center_members, public.center_expenses from anon;
grant select on public.centers, public.center_members, public.center_expenses to authenticated;

-- Staff manage the hours of the doctors' center clinics.
drop policy if exists hours_center_write on public.clinic_hours;
create policy hours_center_write on public.clinic_hours for all
  using (exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id and c.center_id is not null
                 and public.center_can(c.center_id, 'admin')))
  with check (exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id and c.center_id is not null
                      and public.center_can(c.center_id, 'admin')));

-- ---------------------------------------------------------------------
-- Creating a center and its people
-- ---------------------------------------------------------------------
create or replace function public._center_doctor_clinic(p_center uuid, p_doctor uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare c centers; v_id uuid;
begin
  select * into c from centers where id = p_center;
  select id into v_id from clinics where doctor_id = p_doctor and center_id = p_center limit 1;
  if v_id is null then
    insert into clinics (doctor_id, name, address, governorate_id, city_id, area, lat, lng, phone, center_id)
    values (p_doctor, c.name, coalesce(c.address, c.name), c.governorate_id, c.city_id, c.area, c.lat, c.lng, c.phone, p_center)
    returning id into v_id;
  else
    update clinics set is_active = true where id = v_id;
  end if;
  update center_members set clinic_id = v_id where center_id = p_center and user_id = p_doctor and role = 'doctor';
  return v_id;
end $$;

-- A verified doctor opens a center (and works in it). The admin can open one for any account.
create or replace function public.create_center(p_name text, p_phone text default null, p_address text default null,
  p_governorate int default null, p_city int default null, p_area text default null,
  p_lat double precision default null, p_lng double precision default null, p_owner uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_owner uuid := coalesce(p_owner, auth.uid()); v_id uuid; v_is_doc boolean;
begin
  if p_owner is not null and p_owner <> auth.uid() and not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  v_is_doc := exists (select 1 from doctors where id = v_owner and status = 'verified');
  if not is_admin() and not v_is_doc then raise exception 'doctor account is not active' using errcode = '42501'; end if;
  if not is_admin() and (select count(*) from centers where owner_id = v_owner) >= 3 then
    raise exception 'center limit reached' using errcode = 'P0001';
  end if;
  insert into centers (name, owner_id, phone, address, governorate_id, city_id, area, lat, lng)
  values (trim(p_name), v_owner, nullif(trim(p_phone), ''), nullif(trim(p_address), ''), p_governorate, p_city,
          nullif(trim(p_area), ''), p_lat, p_lng)
  returning id into v_id;
  insert into center_members (center_id, user_id, role, invited_by) values (v_id, v_owner, 'owner', auth.uid());
  if v_is_doc then
    insert into center_members (center_id, user_id, role, share_percent, invited_by) values (v_id, v_owner, 'doctor', 100, auth.uid());
    perform _center_doctor_clinic(v_id, v_owner);
  end if;
  perform write_audit('center.created', 'centers', v_id::text, jsonb_build_object('owner', v_owner));
  return v_id;
end $$;

-- Admin: a center whose owner is not a doctor — creates the manager's phone login.
create or replace function public.admin_create_center(p_name text, p_owner_name text, p_owner_phone text, p_password text,
  p_address text default null, p_governorate int default null, p_city int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_phone text; v_user uuid; v_center uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  v_phone := normalize_eg_phone(p_owner_phone);
  v_user := _create_auth_user(phone_login_email(v_phone), p_password,
              jsonb_build_object('full_name', trim(p_owner_name), 'role', 'patient', 'locale', 'ar'));
  perform set_config('doctori.trusted', '1', true);
  update profiles set role = 'assistant', phone = v_phone, login_kind = 'phone', created_by = auth.uid() where id = v_user;
  perform set_config('doctori.trusted', '', true);
  delete from patients where id = v_user;
  v_center := create_center(p_name, v_phone, p_address, p_governorate, p_city, null, null, null, v_user);
  return jsonb_build_object('center_id', v_center, 'user_id', v_user, 'phone', v_phone);
end $$;

create or replace function public.update_center(p_center uuid, p_name text, p_phone text, p_address text,
  p_governorate int default null, p_city int default null, p_area text default null,
  p_lat double precision default null, p_lng double precision default null, p_logo_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  update centers set name = trim(p_name), phone = nullif(trim(p_phone), ''), address = nullif(trim(p_address), ''),
         governorate_id = p_governorate, city_id = p_city, area = nullif(trim(p_area), ''), lat = p_lat, lng = p_lng,
         logo_url = nullif(trim(p_logo_url), '')
   where id = p_center;
  update clinics set name = trim(p_name), address = coalesce(nullif(trim(p_address), ''), trim(p_name)),
         governorate_id = p_governorate, city_id = p_city, area = nullif(trim(p_area), ''), lat = p_lat, lng = p_lng,
         phone = nullif(trim(p_phone), '')
   where center_id = p_center;
end $$;

-- Invite a doctor by mobile or email (they accept from their app), with their share of income.
create or replace function public.center_invite_doctor(p_center uuid, p_login text, p_share numeric default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_login text := lower(trim(coalesce(p_login, ''))); v_phone text;
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_login like '%@%' then
    select p.id into v_doc from profiles p join doctors d on d.id = p.id where lower(p.email) = v_login;
  else
    begin v_phone := normalize_eg_phone(v_login); exception when others then v_phone := null; end;
    select p.id into v_doc from profiles p join doctors d on d.id = p.id
     where v_phone is not null and (p.phone = v_phone or lower(p.email) = 'p' || v_phone || '@phone.doctori.app') limit 1;
  end if;
  if v_doc is null then raise exception 'doctor not found' using errcode = 'P0001'; end if;
  insert into center_members (center_id, user_id, role, status, share_percent, invited_by)
  values (p_center, v_doc, 'doctor', 'invited', coalesce(p_share, 50), auth.uid())
  on conflict (center_id, user_id, role) do update
    set status = case when center_members.status = 'active' then 'active' else 'invited' end,
        share_percent = excluded.share_percent;
  perform _notify(v_doc, 'center', 'دعوة للانضمام لمركز طبي 🏥',
                  (select name from centers where id = p_center) || ' — نسبتك ' || coalesce(p_share, 50) || '٪',
                  jsonb_build_object('center_id', p_center));
  return jsonb_build_object('doctor_id', v_doc, 'name', (select full_name from profiles where id = v_doc));
end $$;

create or replace function public.center_respond_invite(p_center uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from center_members where center_id = p_center and user_id = auth.uid()
                 and role = 'doctor' and status = 'invited') then
    raise exception 'no invitation' using errcode = 'P0001';
  end if;
  if p_accept then
    update center_members set status = 'active' where center_id = p_center and user_id = auth.uid() and role = 'doctor';
    perform _center_doctor_clinic(p_center, auth.uid());
  else
    delete from center_members where center_id = p_center and user_id = auth.uid() and role = 'doctor';
  end if;
  perform _notify((select owner_id from centers where id = p_center), 'center',
                  case when p_accept then 'دكتور انضم للمركز ✓' else 'دكتور اعتذر عن الانضمام' end,
                  (select full_name from profiles where id = auth.uid()), jsonb_build_object('center_id', p_center));
end $$;

create or replace function public.center_set_share(p_center uuid, p_doctor uuid, p_share numeric, p_by_kind jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  update center_members set share_percent = p_share, share_by_kind = coalesce(p_by_kind, '{}'::jsonb)
   where center_id = p_center and user_id = p_doctor and role = 'doctor';
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('center.share_changed', 'centers', p_center::text, jsonb_build_object('doctor', p_doctor, 'share', p_share));
end $$;

-- Owner removes a doctor (or a doctor leaves): their center clinic stops taking bookings.
create or replace function public.center_remove_doctor(p_center uuid, p_doctor uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (center_can(p_center, 'admin') or auth.uid() = p_doctor) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_doctor = (select owner_id from centers where id = p_center) and auth.uid() = p_doctor then
    raise exception 'owner cannot leave' using errcode = 'P0001';
  end if;
  update center_members set status = 'left' where center_id = p_center and user_id = p_doctor and role = 'doctor';
  update clinics set is_active = false where center_id = p_center and doctor_id = p_doctor;
end $$;

-- Reception / manager accounts (phone + password, like assistants).
create or replace function public.center_add_staff(p_center uuid, p_full_name text, p_phone text, p_password text,
                                                   p_role text default 'reception', p_can_finance boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_phone text; v_id uuid;
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_role not in ('reception', 'manager') then raise exception 'invalid role' using errcode = 'P0001'; end if;
  if (select count(*) from center_members where center_id = p_center and role in ('reception', 'manager')) >= 20 then
    raise exception 'staff limit reached' using errcode = 'P0001';
  end if;
  v_phone := normalize_eg_phone(p_phone);
  v_id := _create_auth_user(phone_login_email(v_phone), p_password,
            jsonb_build_object('full_name', trim(p_full_name), 'role', 'patient', 'locale', 'ar'));
  perform set_config('doctori.trusted', '1', true);
  update profiles set role = 'assistant', phone = v_phone, login_kind = 'phone', created_by = auth.uid() where id = v_id;
  perform set_config('doctori.trusted', '', true);
  delete from patients where id = v_id;
  insert into center_members (center_id, user_id, role, can_finance, invited_by)
  values (p_center, v_id, p_role, coalesce(p_can_finance, false) or p_role = 'manager', auth.uid());
  return jsonb_build_object('user_id', v_id, 'phone', v_phone);
end $$;

create or replace function public.center_update_staff(p_center uuid, p_user uuid, p_can_finance boolean, p_active boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  update center_members set can_finance = coalesce(p_can_finance, false), status = case when p_active then 'active' else 'left' end
   where center_id = p_center and user_id = p_user and role in ('reception', 'manager');
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $$;

create or replace function public.center_reset_staff_password(p_center uuid, p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin')
     or not exists (select 1 from center_members where center_id = p_center and user_id = p_user and role in ('reception', 'manager')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform _set_auth_password(p_user, p_password);
end $$;

-- Center staff set a doctor's working hours at the center: [{"weekday":0,"opens":"17:00","closes":"22:00"}, …]
create or replace function public.center_set_hours(p_center uuid, p_doctor uuid, p_hours jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_clinic uuid; h jsonb;
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  select clinic_id into v_clinic from center_members where center_id = p_center and user_id = p_doctor and role = 'doctor' and status = 'active';
  if v_clinic is null then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from clinic_hours where clinic_id = v_clinic;
  for h in select * from jsonb_array_elements(coalesce(p_hours, '[]'::jsonb)) loop
    insert into clinic_hours (clinic_id, weekday, opens_at, closes_at)
    values (v_clinic, (h->>'weekday')::smallint, (h->>'opens')::time, (h->>'closes')::time);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------
create or replace function public.my_centers()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'center_id', c.id, 'name', c.name, 'logo_url', c.logo_url, 'role', m.role, 'status', m.status,
      'share_percent', m.share_percent, 'can_finance', m.can_finance,
      'owner_name', op.full_name, 'doctors', (select count(*) from center_members x where x.center_id = c.id
                                              and x.role = 'doctor' and x.status = 'active'))
      order by (m.status = 'invited') desc, c.name), '[]'::jsonb)
  from center_members m join centers c on c.id = m.center_id join profiles op on op.id = c.owner_id
  where m.user_id = auth.uid() and m.status in ('active', 'invited');
$$;

create or replace function public.center_doctors(p_center uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_day date := (now() at time zone 'Africa/Cairo')::date;
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'doctor_id', m.user_id, 'name', p.full_name, 'avatar_url', p.avatar_url, 'phone', p.phone, 'status', m.status,
      'specialty_ar', s.name_ar, 'specialty_en', s.name_en, 'doctor_status', d.status,
      'share_percent', m.share_percent, 'share_by_kind', m.share_by_kind, 'clinic_id', m.clinic_id,
      'hours', (select coalesce(jsonb_agg(jsonb_build_object('weekday', h.weekday, 'opens', to_char(h.opens_at, 'HH24:MI'),
                                                            'closes', to_char(h.closes_at, 'HH24:MI')) order by h.weekday, h.opens_at), '[]'::jsonb)
                from clinic_hours h where h.clinic_id = m.clinic_id),
      'today_bookings', (select count(*) from appointments a where a.clinic_id = m.clinic_id and a.status in ('pending', 'confirmed', 'completed')
                           and (a.starts_at at time zone 'Africa/Cairo')::date = v_day),
      'waiting', (select count(*) from clinic_queue q where q.clinic_id = m.clinic_id and q.day = v_day and q.status = 'waiting'))
      order by (m.status = 'active') desc, p.full_name)
    from center_members m join profiles p on p.id = m.user_id join doctors d on d.id = m.user_id
    left join specialties s on s.id = d.specialty_id
    where m.center_id = p_center and m.role = 'doctor' and m.status in ('active', 'invited')), '[]'::jsonb);
end $$;

create or replace function public.center_staff(p_center uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'name', p.full_name, 'phone', p.phone,
      'role', m.role, 'status', m.status, 'can_finance', m.can_finance, 'avatar_url', p.avatar_url) order by m.role, p.full_name)
    from center_members m join profiles p on p.id = m.user_id
    where m.center_id = p_center and m.role in ('owner', 'manager', 'reception')), '[]'::jsonb);
end $$;

create or replace function public.center_appointments(p_center uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'starts_at', a.starts_at, 'status', a.status, 'patient_note', a.patient_note,
      'patient_id', a.patient_id, 'patient_name', pp.full_name, 'patient_phone', pp.phone, 'patient_avatar', pp.avatar_url,
      'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
      'clinic_id', a.clinic_id,
      'local_date', to_char(a.starts_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
      'local_time', to_char(a.starts_at at time zone 'Africa/Cairo', 'HH24:MI')) order by a.starts_at)
    from appointments a join clinics c on c.id = a.clinic_id and c.center_id = p_center
    join profiles pp on pp.id = a.patient_id join profiles dp on dp.id = a.doctor_id
    join doctors d on d.id = a.doctor_id left join specialties s on s.id = d.specialty_id
    where a.starts_at >= (p_from::timestamp at time zone 'Africa/Cairo')
      and a.starts_at < ((p_to + 1)::timestamp at time zone 'Africa/Cairo')), '[]'::jsonb);
end $$;

-- Doctor's share of one income row.
create or replace function public._doctor_cut(p_center uuid, p_doctor uuid, p_kind text, p_amount numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select round(p_amount * coalesce((m.share_by_kind->>p_kind)::numeric, m.share_percent, 100) / 100, 2)
  from center_members m where m.center_id = p_center and m.user_id = p_doctor and m.role = 'doctor';
$$;

-- ---------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------
create or replace function public.center_save_income(p_center uuid, p_doctor uuid, p_kind text, p_amount numeric,
  p_on date default null, p_patient uuid default null, p_patient_name text default null, p_note text default null,
  p_appointment uuid default null, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from center_members where center_id = p_center and user_id = p_doctor and role = 'doctor' and status = 'active') then
    raise exception 'doctor is not in this center' using errcode = 'P0001';
  end if;
  if p_patient is not null and not exists (select 1 from care_links where patient_id = p_patient and doctor_id = p_doctor)
     and not exists (select 1 from appointments where patient_id = p_patient and doctor_id = p_doctor) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    insert into doctor_income (doctor_id, center_id, patient_id, patient_name, kind, amount, paid_on, note, appointment_id, created_by)
    values (p_doctor, p_center, p_patient, nullif(trim(p_patient_name), ''), p_kind, p_amount,
            coalesce(p_on, (now() at time zone 'Africa/Cairo')::date), nullif(trim(p_note), ''), p_appointment, auth.uid())
    returning id into v_id;
  else
    if not center_can(p_center, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
    update doctor_income set doctor_id = p_doctor, kind = p_kind, amount = p_amount, paid_on = coalesce(p_on, paid_on),
           patient_id = p_patient, patient_name = nullif(trim(p_patient_name), ''), note = nullif(trim(p_note), '')
     where id = p_id and center_id = p_center returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.center_save_expense(p_center uuid, p_category text, p_amount numeric, p_on date default null,
                                                      p_reason text default null, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not center_can(p_center, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is null then
    insert into center_expenses (center_id, category, amount, spent_on, reason, created_by)
    values (p_center, p_category, p_amount, coalesce(p_on, (now() at time zone 'Africa/Cairo')::date), nullif(trim(p_reason), ''), auth.uid())
    returning id into v_id;
  else
    update center_expenses set category = p_category, amount = p_amount, spent_on = coalesce(p_on, spent_on), reason = nullif(trim(p_reason), '')
     where id = p_id and center_id = p_center returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.center_delete_entry(p_center uuid, p_type text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_type = 'income' then
    delete from doctor_income where id = p_id and center_id = p_center;
  else
    delete from center_expenses where id = p_id and center_id = p_center;
  end if;
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('center.entry_deleted', 'centers', p_center::text, jsonb_build_object('type', p_type, 'id', p_id));
end $$;

-- The center ledger for a period: per doctor (income, their share, center share, cases), expenses, and the net.
-- Reception without finance rights sees only today's entries they need (no totals of doctor shares).
create or replace function public.center_finance(p_center uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_fin boolean;
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_fin := center_can(p_center, 'finance');
  return (
    with inc as (
      select i.*, _doctor_cut(p_center, i.doctor_id, i.kind, i.amount) as dcut
      from doctor_income i where i.center_id = p_center and i.paid_on between p_from and p_to),
    per as (
      select doctor_id, sum(amount) income, sum(dcut) doctor_share, count(*) entries,
             count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text)) cases
      from inc group by doctor_id),
    exp as (select * from center_expenses where center_id = p_center and spent_on between p_from and p_to)
    select jsonb_build_object(
      'can_finance', v_fin,
      'income', (select coalesce(sum(amount), 0) from inc),
      'doctor_shares', case when v_fin then (select coalesce(sum(dcut), 0) from inc) end,
      'center_share', case when v_fin then (select coalesce(sum(amount - dcut), 0) from inc) end,
      'expenses', case when v_fin then (select coalesce(sum(amount), 0) from exp) end,
      'net', case when v_fin then (select coalesce(sum(amount - dcut), 0) from inc) - (select coalesce(sum(amount), 0) from exp) end,
      'cases', (select coalesce(sum(cases), 0) from per),
      'doctors', (select coalesce(jsonb_agg(jsonb_build_object(
            'doctor_id', per.doctor_id, 'name', p.full_name, 'avatar_url', p.avatar_url, 'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
            'income', per.income, 'cases', per.cases,
            'doctor_share', case when v_fin then per.doctor_share end,
            'center_share', case when v_fin then per.income - per.doctor_share end,
            'share_percent', m.share_percent) order by per.income desc), '[]'::jsonb)
          from per join profiles p on p.id = per.doctor_id join doctors d on d.id = per.doctor_id
          left join specialties s on s.id = d.specialty_id
          left join center_members m on m.center_id = p_center and m.user_id = per.doctor_id and m.role = 'doctor'),
      'by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'income', i, 'cases', c) order by d), '[]'::jsonb)
                 from (select paid_on d, sum(amount) i, count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text)) c
                       from inc group by paid_on) x),
      'income_items', (select coalesce(jsonb_agg(jsonb_build_object(
            'id', i.id, 'doctor_id', i.doctor_id, 'doctor_name', dp.full_name, 'kind', i.kind, 'amount', i.amount,
            'doctor_share', case when v_fin then i.dcut end, 'paid_on', i.paid_on, 'note', i.note,
            'patient_name', coalesce(pp.full_name, i.patient_name), 'by', cb.full_name) order by i.paid_on desc, i.created_at desc), '[]'::jsonb)
          from (select * from inc order by paid_on desc, created_at desc limit 300) i
          join profiles dp on dp.id = i.doctor_id left join profiles pp on pp.id = i.patient_id left join profiles cb on cb.id = i.created_by),
      'expense_items', case when v_fin then (select coalesce(jsonb_agg(jsonb_build_object(
            'id', e.id, 'category', e.category, 'amount', e.amount, 'spent_on', e.spent_on, 'reason', e.reason, 'by', cb.full_name)
            order by e.spent_on desc, e.created_at desc), '[]'::jsonb)
          from exp e left join profiles cb on cb.id = e.created_by) else '[]'::jsonb end));
end $$;

-- A doctor sees what the centers they work in recorded for them (income and their share).
create or replace function public.doctor_center_earnings(p_from date, p_to date)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('center_id', c.id, 'name', c.name, 'income', x.income, 'my_share', x.share, 'cases', x.n)
                            order by c.name), '[]'::jsonb)
  from (select center_id, sum(amount) income, sum(_doctor_cut(center_id, doctor_id, kind, amount)) share, count(*) n
        from doctor_income where doctor_id = auth.uid() and center_id is not null and paid_on between p_from and p_to
        group by center_id) x
  join centers c on c.id = x.center_id;
$$;

-- Context: tells the app which centers the user runs (for the center home screen).
create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'phone', p.phone, 'login_kind', p.login_kind,
    'locale', p.locale, 'is_suspended', p.is_suspended, 'avatar_url', p.avatar_url,
    'doctor_status', d.status, 'specialty_id', d.specialty_id,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null),
    'assistant_of', (select jsonb_build_object(
        'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'doctor_avatar', dp.avatar_url,
        'doctor_status', dd.status, 'specialty_ar', ds.name_ar, 'specialty_en', ds.name_en,
        'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
        'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical, 'can_finance', a.can_finance)
      from doctor_assistants a
      join profiles dp on dp.id = a.doctor_id
      join doctors dd on dd.id = a.doctor_id
      left join specialties ds on ds.id = dd.specialty_id
      where a.assistant_id = p.id limit 1),
    'centers', (select coalesce(jsonb_agg(jsonb_build_object('center_id', c.id, 'name', c.name, 'role', m.role,
                                                             'can_finance', m.can_finance or m.role in ('owner', 'manager'))
                                          order by c.name), '[]'::jsonb)
                from center_members m join centers c on c.id = m.center_id
                where m.user_id = p.id and m.status = 'active' and m.role in ('owner', 'manager', 'reception')))
  from profiles p
  left join doctors d on d.id = p.id
  left join specialties s on s.id = d.specialty_id
  where p.id = auth.uid();
$$;

revoke all on function public.center_can(uuid, text), public._center_doctor_clinic(uuid, uuid), public._doctor_cut(uuid, uuid, text, numeric)
  from public, anon;
revoke all on function public._center_doctor_clinic(uuid, uuid) from authenticated;
grant execute on function public.center_can(uuid, text), public._doctor_cut(uuid, uuid, text, numeric) to authenticated;
revoke all on function public.create_center(text, text, text, int, int, text, double precision, double precision, uuid),
  public.admin_create_center(text, text, text, text, text, int, int),
  public.update_center(uuid, text, text, text, int, int, text, double precision, double precision, text),
  public.center_invite_doctor(uuid, text, numeric), public.center_respond_invite(uuid, boolean),
  public.center_set_share(uuid, uuid, numeric, jsonb), public.center_remove_doctor(uuid, uuid),
  public.center_add_staff(uuid, text, text, text, text, boolean), public.center_update_staff(uuid, uuid, boolean, boolean),
  public.center_reset_staff_password(uuid, uuid, text), public.center_set_hours(uuid, uuid, jsonb),
  public.my_centers(), public.center_doctors(uuid), public.center_staff(uuid), public.center_appointments(uuid, date, date),
  public.center_save_income(uuid, uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.center_save_expense(uuid, text, numeric, date, text, uuid), public.center_delete_entry(uuid, text, uuid),
  public.center_finance(uuid, date, date), public.doctor_center_earnings(date, date)
from public, anon;
grant execute on function public.create_center(text, text, text, int, int, text, double precision, double precision, uuid),
  public.admin_create_center(text, text, text, text, text, int, int),
  public.update_center(uuid, text, text, text, int, int, text, double precision, double precision, text),
  public.center_invite_doctor(uuid, text, numeric), public.center_respond_invite(uuid, boolean),
  public.center_set_share(uuid, uuid, numeric, jsonb), public.center_remove_doctor(uuid, uuid),
  public.center_add_staff(uuid, text, text, text, text, boolean), public.center_update_staff(uuid, uuid, boolean, boolean),
  public.center_reset_staff_password(uuid, uuid, text), public.center_set_hours(uuid, uuid, jsonb),
  public.my_centers(), public.center_doctors(uuid), public.center_staff(uuid), public.center_appointments(uuid, date, date),
  public.center_save_income(uuid, uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.center_save_expense(uuid, text, numeric, date, text, uuid), public.center_delete_entry(uuid, text, uuid),
  public.center_finance(uuid, date, date), public.doctor_center_earnings(date, date)
to authenticated;
