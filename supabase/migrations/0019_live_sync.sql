-- 0019: live sync. Whenever clinic data changes (a booking, a payment, the queue, a prescription…),
-- everyone who works on it gets a tiny "ping" row over Realtime and their open screens reload at once:
-- the doctor, the doctor's assistants, the staff of every center the doctor works in, and the patient.
-- Pings carry no medical data — only a scope word — so they are safe to broadcast.

create table public.sync_pings (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  scope      text not null,
  created_at timestamptz not null default now()
);
create index on public.sync_pings (created_at);
alter table public.sync_pings enable row level security;
create policy sync_pings_own on public.sync_pings for select using (user_id = auth.uid());
grant select on public.sync_pings to authenticated;

-- Everyone who should see changes of this doctor / patient.
create or replace function public._sync_audience(p_doctor uuid, p_patient uuid, p_center uuid default null)
returns setof uuid language sql stable security definer set search_path = public as $$
  with docs as (
    select p_doctor as d where p_doctor is not null
    union
    -- rows that only name a patient (medical file, doses, health data) reach the patient's doctors
    select l.doctor_id from care_links l where p_doctor is null and p_patient is not null
                                         and l.patient_id = p_patient and l.status = 'active'
  )
  select d from docs
  union select a.assistant_id from doctor_assistants a join docs on docs.d = a.doctor_id
  union select s.user_id from center_members m join docs on docs.d = m.user_id
          join center_members s on s.center_id = m.center_id and s.role <> 'doctor' and s.status = 'active'
        where m.role = 'doctor' and m.status = 'active'
  union select s.user_id from center_members s where p_center is not null and s.center_id = p_center and s.status = 'active'
  union select p_patient where p_patient is not null;
$$;

create or replace function public._sync_ping() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_doc uuid := coalesce(r->>'doctor_id', r->>'prescribed_by')::uuid;
  v_pat uuid := (r->>'patient_id')::uuid;
  v_center uuid := (r->>'center_id')::uuid;
begin
  if tg_table_name = 'center_members' then
    v_doc := null;
    v_pat := (r->>'user_id')::uuid; -- the member themself + the center's staff
  end if;
  insert into sync_pings (user_id, scope)
  select distinct u, tg_argv[0] from _sync_audience(v_doc, v_pat, v_center) u where u is not null;
  -- keep the table tiny: pings are only useful for a few seconds
  if random() < 0.02 then
    delete from sync_pings where created_at < now() - interval '15 minutes';
  end if;
  return null;
exception when others then
  return null; -- syncing must never block saving the data itself
end $$;

create trigger sync_appointments after insert or update or delete on public.appointments
  for each row execute function public._sync_ping('bookings');
create trigger sync_queue after insert or update or delete on public.clinic_queue
  for each row execute function public._sync_ping('queue');
create trigger sync_income after insert or update or delete on public.doctor_income
  for each row execute function public._sync_ping('finance');
create trigger sync_expenses after insert or update or delete on public.doctor_expenses
  for each row execute function public._sync_ping('finance');
create trigger sync_center_expenses after insert or update or delete on public.center_expenses
  for each row execute function public._sync_ping('finance');
create trigger sync_center_members after insert or update or delete on public.center_members
  for each row execute function public._sync_ping('center');
create trigger sync_care_links after insert or update or delete on public.care_links
  for each row execute function public._sync_ping('patients');
create trigger sync_join_requests after insert or update on public.join_requests
  for each row execute function public._sync_ping('patients');
create trigger sync_medical_entries after insert or update or delete on public.medical_entries
  for each row execute function public._sync_ping('medical');
create trigger sync_medications after insert or update or delete on public.medications
  for each row execute function public._sync_ping('medical');
create trigger sync_doses after insert or update on public.medication_doses
  for each row execute function public._sync_ping('medical');
create trigger sync_case_plans after insert or update or delete on public.case_plans
  for each row execute function public._sync_ping('medical');
create trigger sync_followups after insert or update or delete on public.followups
  for each row execute function public._sync_ping('medical');
create trigger sync_prescriptions after insert or update or delete on public.prescriptions
  for each row execute function public._sync_ping('medical');
create trigger sync_surgeries after insert or update or delete on public.surgeries
  for each row execute function public._sync_ping('medical');
create trigger sync_health after insert or update on public.patient_health
  for each row execute function public._sync_ping('medical');
create trigger sync_inventory after insert or update or delete on public.inventory_items
  for each row execute function public._sync_ping('inventory');

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.sync_pings; exception when duplicate_object then null; end;
  end if;
end $$;
