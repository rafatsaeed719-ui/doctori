-- =====================================================================
-- دكتوري — المرحلة الأولى: دوال الشاشات (قوائم جاهزة لكل دور)
-- Read-model functions used by the app screens. Each returns only what
-- that screen needs, after checking who is calling.
-- =====================================================================

-- Who am I? Drives which home screen the app opens.
create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'locale', p.locale, 'is_suspended', p.is_suspended,
    'doctor_status', d.status,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null))
  from profiles p left join doctors d on d.id = p.id
  where p.id = auth.uid();
$$;

-- Doctor: pending requests with the minimum the doctor needs to decide.
-- The patient chose to send these details by sending the request.
create or replace function public.doctor_incoming_requests()
returns table (request_id uuid, patient_name text, gender public.gender, age int,
               message text, share_scope public.share_scope, clinic_name text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         r.message, r.share_scope, c.name, r.created_at
  from join_requests r
  join profiles p on p.id = r.patient_id
  left join clinics c on c.id = r.clinic_id
  where r.doctor_id = auth.uid() and r.status = 'pending'
  order by r.created_at;
$$;

-- Doctor: active patients.
create or replace function public.doctor_my_patients()
returns table (link_id uuid, patient_id uuid, patient_name text, gender public.gender, age int,
               scope public.share_scope, started_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, p.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         c.scope, l.started_at
  from care_links l
  join profiles p on p.id = l.patient_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.doctor_id = auth.uid() and l.status = 'active'
  order by p.full_name;
$$;

-- Patient: doctors I am linked to.
create or replace function public.patient_my_doctors()
returns table (link_id uuid, doctor_id uuid, doctor_name text, title text, specialty_ar text,
               specialty_en text, scope public.share_scope, started_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, d.id, p.full_name, d.title, s.name_ar, s.name_en, c.scope, l.started_at
  from care_links l
  join doctors d on d.id = l.doctor_id
  join profiles p on p.id = d.id
  left join specialties s on s.id = d.specialty_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.patient_id = auth.uid() and l.status = 'active'
  order by l.started_at desc;
$$;

-- Patient: my requests and their status.
create or replace function public.patient_my_requests()
returns table (request_id uuid, doctor_id uuid, doctor_name text, specialty_ar text, specialty_en text,
               status public.request_status, reject_reason text, created_at timestamptz, responded_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, d.id, p.full_name, s.name_ar, s.name_en, r.status, r.reject_reason, r.created_at, r.responded_at
  from join_requests r
  join doctors d on d.id = r.doctor_id
  join profiles p on p.id = d.id
  left join specialties s on s.id = d.specialty_id
  where r.patient_id = auth.uid()
  order by r.created_at desc
  limit 100;
$$;

-- Admin: doctors by status, with their latest verification documents.
create or replace function public.admin_list_doctors(p_status public.doctor_status default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc) from (
      select d.id, p.full_name, p.email, p.is_suspended, d.status, d.title, d.license_number,
             d.years_experience, d.qualifications, s.name_ar as specialty_ar, d.created_at,
             (select v.documents from doctor_verifications v where v.doctor_id = d.id
              order by v.submitted_at desc limit 1) as documents,
             (select v.note from doctor_verifications v where v.doctor_id = d.id
              order by v.submitted_at desc limit 1) as note,
             (select count(*) from clinics c where c.doctor_id = d.id) as clinics_count
      from doctors d
      join profiles p on p.id = d.id
      left join specialties s on s.id = d.specialty_id
      where p_status is null or d.status = p_status
      limit 200) x), '[]'::jsonb);
end $$;

-- Admin: simple dashboard counters.
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return jsonb_build_object(
    'patients',         (select count(*) from patients),
    'doctors_verified', (select count(*) from doctors where status = 'verified'),
    'doctors_pending',  (select count(*) from doctors where status = 'pending'),
    'active_links',     (select count(*) from care_links where status = 'active'),
    'pending_requests', (select count(*) from join_requests where status = 'pending'));
end $$;

revoke all on function public.get_my_context(), public.doctor_incoming_requests(),
  public.doctor_my_patients(), public.patient_my_doctors(), public.patient_my_requests(),
  public.admin_list_doctors(public.doctor_status), public.admin_stats() from public, anon;
grant execute on function public.get_my_context(), public.doctor_incoming_requests(),
  public.doctor_my_patients(), public.patient_my_doctors(), public.patient_my_requests(),
  public.admin_list_doctors(public.doctor_status), public.admin_stats() to authenticated;
