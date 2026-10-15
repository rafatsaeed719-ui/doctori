-- =====================================================================
-- دكتوري — 0008: تفعيل الطبيب بكود من الإدارة عبر واتساب
-- 1. The doctor registers with a mobile number and asks for a code on WhatsApp.
-- 2. The admin issues a 6-digit code (stored hashed, valid 7 days) and sends it.
-- 3. The doctor enters the code → account verified and visible to patients.
-- =====================================================================

create table if not exists public.doctor_activation_codes (
  doctor_id  uuid primary key references public.doctors(id) on delete cascade,
  code_hash  text not null,
  issued_by  uuid references public.profiles(id) on delete set null,
  issued_at  timestamptz not null default now(),
  expires_at timestamptz not null,
  attempts   int not null default 0,
  used_at    timestamptz
);
alter table public.doctor_activation_codes enable row level security;  -- no policies: functions only
revoke all on public.doctor_activation_codes from anon, authenticated;

-- Admin's WhatsApp number that doctors message for their code (editable by the admin).
insert into public.app_settings (key, value) values ('admin_whatsapp', '"201207760898"')
on conflict (key) do nothing;

-- Sign-up keeps the mobile number the user typed (metadata "phone"), normalized when it is Egyptian.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role user_role := case when new.raw_user_meta_data->>'role' = 'doctor'
                           then 'doctor'::user_role else 'patient'::user_role end;
  v_phone text := coalesce(new.phone, nullif(trim(new.raw_user_meta_data->>'phone'), ''));
begin
  if v_phone is not null then
    begin
      v_phone := normalize_eg_phone(v_phone);
    exception when others then
      v_phone := regexp_replace(v_phone, '\D', '', 'g');
    end;
  end if;
  insert into profiles (id, role, full_name, phone, email, locale)
  values (new.id, v_role,
          coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'مستخدم'),
          v_phone, new.email,
          case when new.raw_user_meta_data->>'locale' = 'en' then 'en' else 'ar' end);
  if v_role = 'doctor' then
    insert into doctors (id) values (new.id);
  else
    insert into patients (id) values (new.id);
  end if;
  return new;
end $$;

-- Let trusted functions verify a doctor without being admin (flag set only inside them).
create or replace function public.guard_doctor_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and auth.uid() is not null
     and coalesce(current_setting('doctori.trusted_verify', true), '') <> '1' then
    if new.status is distinct from old.status
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by
       or new.rating_avg is distinct from old.rating_avg
       or new.rating_count is distinct from old.rating_count then
      raise exception 'verification and rating fields are managed by the platform' using errcode = '42501';
    end if;
    if old.status = 'verified' and new.license_number is distinct from old.license_number then
      new.status := 'pending';
      new.verified_at := null;
      new.verified_by := null;
    end if;
  end if;
  return new;
end $$;

-- Admin: create (or replace) a code for a doctor. Returns the plain code once, to send on WhatsApp.
create or replace function public.admin_issue_doctor_code(p_doctor uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_code text; v_phone text;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if not exists (select 1 from doctors where id = p_doctor) then
    raise exception 'doctor not found' using errcode = 'P0001';
  end if;
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into doctor_activation_codes (doctor_id, code_hash, issued_by, issued_at, expires_at, attempts, used_at)
  values (p_doctor, extensions.crypt(v_code, extensions.gen_salt('bf')), auth.uid(), now(), now() + interval '7 days', 0, null)
  on conflict (doctor_id) do update
    set code_hash = excluded.code_hash, issued_by = excluded.issued_by, issued_at = now(),
        expires_at = excluded.expires_at, attempts = 0, used_at = null;
  select phone into v_phone from profiles where id = p_doctor;
  perform write_audit('doctor.activation_code_issued', 'doctors', p_doctor::text, '{}'::jsonb);
  return jsonb_build_object('code', v_code, 'phone', v_phone);
end $$;

-- Doctor: enter the code → verified. Returns {ok, attempts_left} instead of raising on a wrong
-- code, so the failed attempt is saved (a raised error would roll the counter back).
create or replace function public.doctor_activate_with_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r doctor_activation_codes;
begin
  select * into r from doctor_activation_codes where doctor_id = auth.uid() for update;
  if not found then raise exception 'no activation code yet' using errcode = 'P0001'; end if;
  if r.used_at is not null then raise exception 'code already used' using errcode = 'P0001'; end if;
  if r.expires_at < now() then raise exception 'activation code expired' using errcode = 'P0001'; end if;
  if r.attempts >= 5 then raise exception 'too many wrong attempts' using errcode = 'P0001'; end if;

  if extensions.crypt(regexp_replace(coalesce(p_code, ''), '\D', '', 'g'), r.code_hash) <> r.code_hash then
    update doctor_activation_codes set attempts = attempts + 1 where doctor_id = r.doctor_id;
    return jsonb_build_object('ok', false, 'attempts_left', greatest(0, 4 - r.attempts));
  end if;

  perform set_config('doctori.trusted_verify', '1', true);
  update doctors set status = 'verified', verified_at = now(), verified_by = r.issued_by where id = r.doctor_id;
  perform set_config('doctori.trusted_verify', '', true);
  update doctor_activation_codes set used_at = now() where doctor_id = r.doctor_id;
  perform write_audit('doctor.activated_with_code', 'doctors', r.doctor_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.admin_issue_doctor_code(uuid), public.doctor_activate_with_code(text) from public, anon;
grant execute on function public.admin_issue_doctor_code(uuid), public.doctor_activate_with_code(text) to authenticated;
