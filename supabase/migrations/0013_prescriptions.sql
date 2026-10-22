-- =====================================================================
-- دكتوري — 0013: الروشتة
-- * prescriptions: what the doctor wrote — diagnosis, medicines (name, type, dose, how often, days, notes).
--   Sent to a linked patient in the app (and optionally added to «علاجي» with reminders),
--   or written for a walk-in by name to print / share as PDF.
-- * doctors.rx_settings: the prescription look — clinic logo, phones, WhatsApp, header and footer lines.
-- =====================================================================

alter table public.doctors add column if not exists rx_settings jsonb not null default '{}'::jsonb
  check (jsonb_typeof(rx_settings) = 'object' and pg_column_size(rx_settings) < 6000);

create table public.prescriptions (
  id            uuid primary key default gen_random_uuid(),
  doctor_id     uuid not null references public.doctors(id) on delete cascade,
  patient_id    uuid references public.patients(id) on delete set null,
  patient_name  text check (patient_name is null or length(patient_name) <= 120),
  patient_age   text check (patient_age is null or length(patient_age) <= 20),
  clinic_id     uuid references public.clinics(id) on delete set null,
  diagnosis     text check (diagnosis is null or length(diagnosis) <= 1000),
  items         jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and pg_column_size(items) < 30000),
  notes         text check (notes is null or length(notes) <= 1500),
  next_visit    date,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_prescriptions_doctor on public.prescriptions (doctor_id, created_at);
create index if not exists idx_prescriptions_patient on public.prescriptions (patient_id, created_at);
alter table public.prescriptions enable row level security;
create policy rx_read on public.prescriptions for select
  using (patient_id = auth.uid() or public.acts_for(doctor_id, 'medical'));
revoke all on public.prescriptions from anon;
grant select on public.prescriptions to authenticated;

create or replace function public.create_prescription(
  p_patient uuid, p_patient_name text, p_items jsonb, p_diagnosis text default null, p_notes text default null,
  p_clinic uuid default null, p_next_visit date default null, p_add_to_meds boolean default true,
  p_patient_age text default null, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid; it jsonb; v_every int; v_days int;
begin
  if not acts_for(v_doc, 'medical') or not exists (select 1 from doctors where id = v_doc and status = 'verified') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_patient is not null and not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_patient is null and length(trim(coalesce(p_patient_name, ''))) < 2 then
    raise exception 'name is required' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'add at least one medicine' using errcode = 'P0001';
  end if;
  if p_clinic is not null and not exists (select 1 from clinics where id = p_clinic and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into prescriptions (doctor_id, patient_id, patient_name, patient_age, clinic_id, diagnosis, items, notes, next_visit, created_by)
  values (v_doc, p_patient,
          coalesce(nullif(trim(p_patient_name), ''), (select full_name from profiles where id = p_patient)),
          nullif(trim(p_patient_age), ''), p_clinic, nullif(trim(p_diagnosis), ''), p_items, nullif(trim(p_notes), ''),
          p_next_visit, auth.uid())
  returning id into v_id;

  -- Linked patient: each medicine also goes to «علاجي» with phone reminders.
  if p_patient is not null and coalesce(p_add_to_meds, true) then
    for it in select * from jsonb_array_elements(p_items) loop
      continue when length(trim(coalesce(it->>'name', ''))) = 0;
      v_every := case when (it->>'every_hours') ~ '^\d+$' and (it->>'every_hours')::int in (4, 6, 8, 12, 24)
                      then (it->>'every_hours')::int else null end;
      continue when v_every is null;
      v_days := case when (it->>'days') ~ '^\d+$' then least((it->>'days')::int, 365) else null end;
      insert into medications (patient_id, prescribed_by, name, dose, form, every_hours, first_time, start_date, end_date, instructions)
      values (p_patient, v_doc, left(trim(it->>'name'), 120), nullif(left(trim(coalesce(it->>'dose', '')), 120), ''),
              case when it->>'form' in ('tablet', 'capsule', 'syrup', 'injection', 'drops', 'cream', 'inhaler', 'sachet',
                                        'suppository', 'other') then it->>'form' end,
              v_every, coalesce(nullif(it->>'first_time', '')::time, '09:00'),
              (now() at time zone 'Africa/Cairo')::date,
              case when v_days is not null and v_days > 0 then (now() at time zone 'Africa/Cairo')::date + v_days - 1 end,
              nullif(left(trim(coalesce(it->>'instructions', '')), 1000), ''));
    end loop;
  end if;
  perform write_audit('prescription.created', 'prescriptions', v_id::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc));
  return v_id;
end $$;

-- Everything needed to draw a prescription: doctor, specialty, clinics, logo and contact settings.
create or replace function public.rx_header(p_doctor uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'doctor_id', d.id, 'doctor_name', p.full_name, 'title', d.title, 'avatar_url', p.avatar_url,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en, 'qualifications', d.qualifications,
    'public_phone', d.public_phone, 'settings', d.rx_settings,
    'clinics', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'address', c.address,
                                                             'area', c.area, 'phone', c.phone,
                                                             'city', ci.name_ar, 'governorate', g.name_ar)
                                          order by c.created_at), '[]'::jsonb)
                from clinics c left join cities ci on ci.id = c.city_id left join governorates g on g.id = c.governorate_id
                where c.doctor_id = d.id and c.is_active))
  from doctors d join profiles p on p.id = d.id left join specialties s on s.id = d.specialty_id
  where d.id = coalesce(p_doctor, auth.uid());
$$;

create or replace function public.set_rx_settings(p_settings jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from doctors where id = auth.uid()) then raise exception 'not allowed' using errcode = '42501'; end if;
  update doctors set rx_settings = coalesce(p_settings, '{}'::jsonb) where id = auth.uid();
end $$;

create or replace function public.list_prescriptions(p_patient uuid default null, p_doctor uuid default null, p_limit int default 50)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
    select r.created_at, jsonb_build_object(
      'id', r.id, 'doctor_id', r.doctor_id, 'patient_id', r.patient_id, 'patient_name', r.patient_name,
      'patient_age', r.patient_age, 'clinic_id', r.clinic_id, 'diagnosis', r.diagnosis, 'items', r.items,
      'notes', r.notes, 'next_visit', r.next_visit, 'created_at', r.created_at,
      'doctor_name', dp.full_name, 'specialty_en', s.name_en) j
    from prescriptions r
    join profiles dp on dp.id = r.doctor_id
    join doctors d on d.id = r.doctor_id
    left join specialties s on s.id = d.specialty_id
    where (p_patient is null or r.patient_id = p_patient)
      and (p_doctor is null or r.doctor_id = p_doctor)
      and (r.patient_id = auth.uid() or acts_for(r.doctor_id, 'medical'))
      and (p_patient is not null or p_doctor is not null or r.patient_id = auth.uid())
    order by r.created_at desc
    limit least(coalesce(p_limit, 50), 200)) x;
$$;

revoke all on function public.create_prescription(uuid, text, jsonb, text, text, uuid, date, boolean, text, uuid),
  public.rx_header(uuid), public.set_rx_settings(jsonb), public.list_prescriptions(uuid, uuid, int) from public, anon;
grant execute on function public.create_prescription(uuid, text, jsonb, text, text, uuid, date, boolean, text, uuid),
  public.rx_header(uuid), public.set_rx_settings(jsonb), public.list_prescriptions(uuid, uuid, int) to authenticated;
