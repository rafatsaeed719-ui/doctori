-- =====================================================================
-- دكتوري — 0017: دور الانتظار، المخزن، التقارير، العمليات، الشات، البيانات الطبية الأساسية،
--                 الإشعارات، تقييم الدكتور
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Notifications (written by the features below; read live by the app)
-- ---------------------------------------------------------------------
create table public.notifications (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (length(kind) <= 40),
  title      text not null check (length(title) <= 200),
  body       text check (body is null or length(body) <= 500),
  ref        jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists idx_notifications_user on public.notifications (user_id, created_at);
alter table public.notifications enable row level security;
create policy notifications_own on public.notifications for select using (user_id = auth.uid());
revoke all on public.notifications from anon;
grant select on public.notifications to authenticated;

-- Internal: notify one user.
create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text default null,
                                          p_ref jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, kind, title, body, ref)
  select p_user, p_kind, left(p_title, 200), left(p_body, 500), coalesce(p_ref, '{}'::jsonb)
  where p_user is not null and p_user is distinct from auth.uid();
$$;
-- Internal: notify a doctor and their assistants who hold a permission.
create or replace function public._notify_clinic(p_doctor uuid, p_perm text, p_kind text, p_title text,
                                                 p_body text default null, p_ref jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  perform _notify(p_doctor, p_kind, p_title, p_body, p_ref);
  for u in select assistant_id from doctor_assistants
           where doctor_id = p_doctor
             and case p_perm when 'bookings' then can_bookings when 'patients' then can_patients
                             when 'medical' then can_medical when 'finance' then can_finance else false end loop
    perform _notify(u, p_kind, p_title, p_body, p_ref);
  end loop;
end $$;
revoke all on function public._notify(uuid, text, text, text, jsonb), public._notify_clinic(uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;

create or replace function public.my_notifications(p_limit int default 60)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'unread', (select count(*) from notifications where user_id = auth.uid() and read_at is null),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body,
                                                           'ref', n.ref, 'created_at', n.created_at, 'read', n.read_at is not null)
                                        order by n.created_at desc)
                       from (select * from notifications where user_id = auth.uid()
                             order by created_at desc limit least(coalesce(p_limit, 60), 200)) n), '[]'::jsonb));
$$;

create or replace function public.mark_notifications_read(p_upto bigint default null)
returns void language sql security definer set search_path = public as $$
  update notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_upto is null or id <= p_upto);
$$;

-- Events → notifications
create or replace function public.trg_appointment_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_when text := to_char(new.starts_at at time zone 'Africa/Cairo', 'YYYY/MM/DD HH12:MI AM');
        v_doc text; v_pat text;
begin
  select full_name into v_doc from profiles where id = new.doctor_id;
  select full_name into v_pat from profiles where id = new.patient_id;
  if tg_op = 'INSERT' then
    if auth.uid() = new.patient_id then
      perform _notify_clinic(new.doctor_id, 'bookings', 'booking', 'حجز جديد 📅', coalesce(v_pat, '') || ' — ' || v_when,
                             jsonb_build_object('appointment_id', new.id));
    else
      perform _notify(new.patient_id, 'booking', 'اتحجزلك ميعاد 📅', 'د. ' || coalesce(v_doc, '') || ' — ' || v_when,
                      jsonb_build_object('appointment_id', new.id));
    end if;
  elsif new.status is distinct from old.status then
    if new.status = 'confirmed' then
      perform _notify(new.patient_id, 'booking', 'حجزك اتأكد ✓', 'د. ' || coalesce(v_doc, '') || ' — ' || v_when,
                      jsonb_build_object('appointment_id', new.id));
    elsif new.status = 'cancelled' then
      if auth.uid() = new.patient_id then
        perform _notify_clinic(new.doctor_id, 'bookings', 'booking', 'حجز اتلغى', coalesce(v_pat, '') || ' — ' || v_when,
                               jsonb_build_object('appointment_id', new.id));
      else
        perform _notify(new.patient_id, 'booking', 'حجزك اتلغى', 'د. ' || coalesce(v_doc, '') || ' — ' || v_when ||
                        '. ممكن تحجز ميعاد تاني.', jsonb_build_object('appointment_id', new.id));
      end if;
    elsif new.status = 'completed' then
      perform _notify(new.patient_id, 'review', 'ألف سلامة عليك 💙', 'قيّم زيارتك لـد. ' || coalesce(v_doc, ''),
                      jsonb_build_object('doctor_id', new.doctor_id, 'appointment_id', new.id));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists appointments_notify on public.appointments;
create trigger appointments_notify after insert or update of status on public.appointments
  for each row execute function public.trg_appointment_notify();

create or replace function public.trg_rx_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.patient_id is not null then
    perform _notify(new.patient_id, 'prescription', 'روشتة جديدة 📝',
                    'د. ' || coalesce((select full_name from profiles where id = new.doctor_id), '') || ' كتبلك روشتة',
                    jsonb_build_object('prescription_id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists prescriptions_notify on public.prescriptions;
create trigger prescriptions_notify after insert on public.prescriptions for each row execute function public.trg_rx_notify();

create or replace function public.trg_followup_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform _notify(new.patient_id, 'followup', 'ميعاد متابعة 🔁',
                  new.title || ' — ' || to_char(new.scheduled_at at time zone 'Africa/Cairo', 'YYYY/MM/DD HH12:MI AM'),
                  jsonb_build_object('followup_id', new.id));
  return new;
end $$;
drop trigger if exists followups_notify on public.followups;
create trigger followups_notify after insert on public.followups for each row execute function public.trg_followup_notify();

create or replace function public.trg_med_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.needs_review and new.review_doctor is not null then
    perform _notify_clinic(new.review_doctor, 'medical', 'med_review', 'دوا محتاج تحدد جرعته 💊',
                           coalesce((select full_name from profiles where id = new.patient_id), '') || ' بعت صورة دوا',
                           jsonb_build_object('medication_id', new.id));
  elsif tg_op = 'INSERT' and new.prescribed_by is not null then
    perform _notify(new.patient_id, 'medication', 'علاج جديد من دكتورك 💊', new.name, jsonb_build_object('medication_id', new.id));
  elsif tg_op = 'UPDATE' and old.needs_review and not new.needs_review then
    perform _notify(new.patient_id, 'medication', 'الدكتور حدد جرعة دواك ✓', new.name || coalesce(' — ' || new.dose, ''),
                    jsonb_build_object('medication_id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists medications_notify on public.medications;
create trigger medications_notify after insert or update of needs_review on public.medications
  for each row execute function public.trg_med_notify();

create or replace function public.trg_join_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform _notify_clinic(new.doctor_id, 'patients', 'join', 'طلب انضمام جديد 👋',
                           coalesce((select full_name from profiles where id = new.patient_id), ''), '{}'::jsonb);
  elsif new.status is distinct from old.status and new.status in ('accepted', 'rejected') then
    perform _notify(new.patient_id, 'join',
                    case when new.status = 'accepted' then 'الدكتور قبل طلبك ✓' else 'الدكتور اعتذر عن طلبك' end,
                    'د. ' || coalesce((select full_name from profiles where id = new.doctor_id), ''), '{}'::jsonb);
  end if;
  return new;
end $$;
drop trigger if exists join_requests_notify on public.join_requests;
create trigger join_requests_notify after insert or update of status on public.join_requests
  for each row execute function public.trg_join_notify();

-- ---------------------------------------------------------------------
-- 2) Waiting queue (today, per clinic)
-- ---------------------------------------------------------------------
create table public.clinic_queue (
  id             uuid primary key default gen_random_uuid(),
  clinic_id      uuid not null references public.clinics(id) on delete cascade,
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  day            date not null,
  number         int not null,
  patient_id     uuid references public.patients(id) on delete set null,
  patient_name   text check (patient_name is null or length(patient_name) <= 120),
  appointment_id uuid references public.appointments(id) on delete set null,
  status         text not null default 'waiting' check (status in ('waiting', 'called', 'in_room', 'done', 'skipped')),
  created_at     timestamptz not null default now(),
  called_at      timestamptz,
  done_at        timestamptz,
  unique (clinic_id, day, number)
);
create unique index if not exists clinic_queue_one_per_appt on public.clinic_queue (appointment_id) where appointment_id is not null;
alter table public.clinic_queue enable row level security;
create policy queue_read on public.clinic_queue for select using (patient_id = auth.uid() or public.acts_for(doctor_id, 'bookings'));
revoke all on public.clinic_queue from anon;
grant select on public.clinic_queue to authenticated;

create or replace function public._queue_add(p_clinic uuid, p_patient uuid, p_name text, p_appt uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_day date := (now() at time zone 'Africa/Cairo')::date; v_no int; v_id uuid;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  perform pg_advisory_xact_lock(hashtext(p_clinic::text || v_day::text));
  select coalesce(max(number), 0) + 1 into v_no from clinic_queue where clinic_id = p_clinic and day = v_day;
  insert into clinic_queue (clinic_id, doctor_id, day, number, patient_id, patient_name, appointment_id)
  values (p_clinic, v_doc, v_day, v_no, p_patient,
          coalesce(nullif(trim(p_name), ''), (select full_name from profiles where id = p_patient)), p_appt)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public._queue_add(uuid, uuid, text, uuid) from public, anon, authenticated;

-- Staff: add a walk-in or a booked patient to today's queue.
create or replace function public.queue_add(p_clinic uuid, p_patient uuid default null, p_name text default null,
                                            p_appointment uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_existing uuid;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  if v_doc is null or not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_appointment is not null then
    select id into v_existing from clinic_queue where appointment_id = p_appointment;
    if v_existing is not null then return v_existing; end if;
    select patient_id into p_patient from appointments where id = p_appointment and doctor_id = v_doc;
  end if;
  if p_patient is null and length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'name is required' using errcode = 'P0001';
  end if;
  return _queue_add(p_clinic, p_patient, p_name, p_appointment);
end $$;

-- Patient: "I arrived" for today's booking.
create or replace function public.queue_checkin(p_appointment uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare a appointments; v_existing uuid;
begin
  select * into a from appointments where id = p_appointment and patient_id = auth.uid();
  if not found or a.status not in ('pending', 'confirmed')
     or (a.starts_at at time zone 'Africa/Cairo')::date <> (now() at time zone 'Africa/Cairo')::date then
    raise exception 'check-in is only for today''s booking' using errcode = 'P0001';
  end if;
  select id into v_existing from clinic_queue where appointment_id = p_appointment;
  if v_existing is not null then return v_existing; end if;
  v_existing := _queue_add(a.clinic_id, a.patient_id, null, a.id);
  perform _notify_clinic(a.doctor_id, 'bookings', 'queue', 'مريض وصل العيادة 🚶',
                         coalesce((select full_name from profiles where id = a.patient_id), ''), '{}'::jsonb);
  return v_existing;
end $$;

create or replace function public.queue_set_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare q clinic_queue;
begin
  select * into q from clinic_queue where id = p_id for update;
  if not found or not acts_for(q.doctor_id, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('waiting', 'called', 'in_room', 'done', 'skipped') then
    raise exception 'invalid status' using errcode = 'P0001';
  end if;
  update clinic_queue set status = p_status,
         called_at = case when p_status = 'called' then now() else called_at end,
         done_at = case when p_status in ('done', 'skipped') then now() else done_at end
   where id = p_id;
  if p_status = 'called' and q.patient_id is not null then
    perform _notify(q.patient_id, 'queue', 'دورك جه! 🔔', 'اتفضل ادخل للدكتور — رقمك ' || q.number,
                    jsonb_build_object('queue_id', q.id));
  end if;
  if p_status = 'done' and q.appointment_id is not null then
    update appointments set status = 'completed', updated_by = auth.uid()
     where id = q.appointment_id and status in ('pending', 'confirmed');
  end if;
end $$;

-- Staff: call the next waiting number.
create or replace function public.queue_call_next(p_clinic uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_day date := (now() at time zone 'Africa/Cairo')::date; q clinic_queue;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  if v_doc is null or not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  update clinic_queue set status = 'done', done_at = now()
   where clinic_id = p_clinic and day = v_day and status in ('called', 'in_room');
  select * into q from clinic_queue where clinic_id = p_clinic and day = v_day and status = 'waiting'
   order by number limit 1;
  if not found then return null; end if;
  perform queue_set_status(q.id, 'called');
  return jsonb_build_object('id', q.id, 'number', q.number, 'patient_name', q.patient_name);
end $$;

create or replace function public.queue_today(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid; v_day date := (now() at time zone 'Africa/Cairo')::date;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  if v_doc is null or not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'minutes', (select appointment_minutes from doctors where id = v_doc),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', q.id, 'number', q.number, 'status', q.status, 'patient_id', q.patient_id, 'patient_name', q.patient_name,
        'patient_phone', p.phone, 'patient_avatar', p.avatar_url, 'appointment_id', q.appointment_id,
        'created_at', q.created_at, 'called_at', q.called_at) order by q.number)
      from clinic_queue q left join profiles p on p.id = q.patient_id
      where q.clinic_id = p_clinic and q.day = v_day), '[]'::jsonb),
    'appointments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'patient_id', a.patient_id, 'patient_name', p.full_name,
        'time', to_char(a.starts_at at time zone 'Africa/Cairo', 'HH24:MI'), 'status', a.status) order by a.starts_at)
      from appointments a join profiles p on p.id = a.patient_id
      where a.clinic_id = p_clinic and a.status in ('pending', 'confirmed')
        and (a.starts_at at time zone 'Africa/Cairo')::date = v_day
        and not exists (select 1 from clinic_queue q where q.appointment_id = a.id)), '[]'::jsonb));
end $$;

-- Patient: my place in today's queue(s).
create or replace function public.my_queue()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', q.id, 'number', q.number, 'status', q.status, 'clinic_name', c.name, 'doctor_name', dp.full_name,
      'now_serving', (select max(number) from clinic_queue x where x.clinic_id = q.clinic_id and x.day = q.day
                        and x.status in ('called', 'in_room', 'done')),
      'ahead', (select count(*) from clinic_queue x where x.clinic_id = q.clinic_id and x.day = q.day
                  and x.status = 'waiting' and x.number < q.number),
      'minutes', d.appointment_minutes) order by q.created_at), '[]'::jsonb)
  from clinic_queue q
  join clinics c on c.id = q.clinic_id
  join doctors d on d.id = q.doctor_id
  join profiles dp on dp.id = q.doctor_id
  where q.patient_id = auth.uid() and q.day = (now() at time zone 'Africa/Cairo')::date
    and q.status in ('waiting', 'called', 'in_room');
$$;

-- ---------------------------------------------------------------------
-- 3) Inventory
-- ---------------------------------------------------------------------
create table public.inventory_items (
  id         uuid primary key default gen_random_uuid(),
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 120),
  category   text check (category is null or length(category) <= 60),
  unit       text check (unit is null or length(unit) <= 30),
  qty        numeric(12,2) not null default 0,
  min_qty    numeric(12,2) not null default 0 check (min_qty >= 0),
  unit_cost  numeric(12,2) check (unit_cost is null or unit_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_inventory_doctor on public.inventory_items (doctor_id);
alter table public.inventory_items enable row level security;
create policy inventory_read on public.inventory_items for select
  using (public.acts_for(doctor_id, 'finance') or public.acts_for(doctor_id, 'bookings'));
revoke all on public.inventory_items from anon;
grant select on public.inventory_items to authenticated;
drop trigger if exists inventory_items_touch on public.inventory_items;
create trigger inventory_items_touch before update on public.inventory_items for each row execute function public.touch_updated_at();

create table public.inventory_moves (
  id         bigserial primary key,
  item_id    uuid not null references public.inventory_items(id) on delete cascade,
  delta      numeric(12,2) not null check (delta <> 0),
  reason     text not null check (reason in ('purchase', 'use', 'adjust', 'expired', 'return')),
  note       text check (note is null or length(note) <= 200),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.inventory_moves enable row level security;
create policy inventory_moves_read on public.inventory_moves for select using (
  exists (select 1 from public.inventory_items i where i.id = item_id
          and (public.acts_for(i.doctor_id, 'finance') or public.acts_for(i.doctor_id, 'bookings'))));
revoke all on public.inventory_moves from anon;
grant select on public.inventory_moves to authenticated;

create or replace function public._can_stock(p_doctor uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select acts_for(p_doctor, 'finance') or acts_for(p_doctor, 'bookings');
$$;

create or replace function public.save_inventory_item(p_id uuid, p_name text, p_category text default null,
  p_unit text default null, p_min_qty numeric default 0, p_unit_cost numeric default null,
  p_initial_qty numeric default 0, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not _can_stock(v_doc) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is null then
    insert into inventory_items (doctor_id, name, category, unit, min_qty, unit_cost, qty)
    values (v_doc, trim(p_name), nullif(trim(p_category), ''), nullif(trim(p_unit), ''), coalesce(p_min_qty, 0), p_unit_cost,
            greatest(coalesce(p_initial_qty, 0), 0))
    returning id into v_id;
    if coalesce(p_initial_qty, 0) > 0 then
      insert into inventory_moves (item_id, delta, reason, note, created_by) values (v_id, p_initial_qty, 'adjust', 'رصيد أول المدة', auth.uid());
    end if;
  else
    update inventory_items set name = trim(p_name), category = nullif(trim(p_category), ''), unit = nullif(trim(p_unit), ''),
           min_qty = coalesce(p_min_qty, 0), unit_cost = p_unit_cost
     where id = p_id and doctor_id = v_doc returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.delete_inventory_item(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid;
begin
  select doctor_id into v_doc from inventory_items where id = p_id;
  if v_doc is null or not _can_stock(v_doc) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inventory_items where id = p_id;
end $$;

-- Stock in (+) or out (−). A purchase with a cost can also be recorded as a clinic expense.
create or replace function public.inventory_move(p_item uuid, p_delta numeric, p_reason text, p_note text default null,
                                                 p_cost numeric default null, p_record_expense boolean default false)
returns numeric language plpgsql security definer set search_path = public as $$
declare i inventory_items; v_qty numeric;
begin
  select * into i from inventory_items where id = p_item for update;
  if not found or not _can_stock(i.doctor_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'quantity is required' using errcode = 'P0001'; end if;
  if i.qty + p_delta < 0 then raise exception 'not enough stock' using errcode = 'P0001'; end if;
  insert into inventory_moves (item_id, delta, reason, note, created_by) values (p_item, p_delta, p_reason, nullif(trim(p_note), ''), auth.uid());
  update inventory_items set qty = qty + p_delta,
         unit_cost = case when p_reason = 'purchase' and p_cost is not null and p_delta > 0 then round(p_cost / p_delta, 2) else unit_cost end
   where id = p_item returning qty into v_qty;
  if coalesce(p_record_expense, false) and p_reason = 'purchase' and coalesce(p_cost, 0) > 0
     and acts_for(i.doctor_id, 'finance') then
    insert into doctor_expenses (doctor_id, category, amount, spent_on, reason, created_by)
    values (i.doctor_id, 'supplies', p_cost, (now() at time zone 'Africa/Cairo')::date, 'شراء ' || i.name || ' (' || p_delta || ')', auth.uid());
  end if;
  if v_qty <= i.min_qty and i.qty > i.min_qty then
    perform _notify_clinic(i.doctor_id, 'bookings', 'stock', 'صنف قرب يخلص ⚠️', i.name || ' — الباقي ' || v_qty, jsonb_build_object('item_id', i.id));
  end if;
  return v_qty;
end $$;

create or replace function public.list_inventory(p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not _can_stock(v_doc) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', i.id, 'name', i.name, 'category', i.category, 'unit', i.unit, 'qty', i.qty, 'min_qty', i.min_qty,
      'unit_cost', i.unit_cost, 'low', i.qty <= i.min_qty, 'updated_at', i.updated_at,
      'moves', (select coalesce(jsonb_agg(jsonb_build_object('delta', m.delta, 'reason', m.reason, 'note', m.note,
                                                             'at', m.created_at, 'by', p.full_name) order by m.created_at desc), '[]'::jsonb)
                from (select * from inventory_moves where item_id = i.id order by created_at desc limit 15) m
                left join profiles p on p.id = m.created_by))
      order by (i.qty <= i.min_qty) desc, i.name) from inventory_items i where i.doctor_id = v_doc), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 4) Reports
-- ---------------------------------------------------------------------
create or replace function public.doctor_reports(p_from date, p_to date, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
        v_from timestamptz := p_from::timestamp at time zone 'Africa/Cairo';
        v_to timestamptz := (p_to + 1)::timestamp at time zone 'Africa/Cairo';
        v_fin boolean;
begin
  if not (acts_for(v_doc, 'bookings') or acts_for(v_doc, 'finance')) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_fin := acts_for(v_doc, 'finance');
  return jsonb_build_object(
    'appointments', (select jsonb_build_object(
        'total', count(*),
        'completed', count(*) filter (where status = 'completed'),
        'cancelled', count(*) filter (where status = 'cancelled'),
        'no_show', count(*) filter (where status = 'no_show'),
        'pending', count(*) filter (where status in ('pending', 'confirmed')))
      from appointments where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to),
    'by_weekday', (select coalesce(jsonb_object_agg(wd, n), '{}'::jsonb) from (
        select extract(dow from starts_at at time zone 'Africa/Cairo')::int wd, count(*) n from appointments
        where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to and status <> 'cancelled' group by 1) x),
    'by_hour', (select coalesce(jsonb_object_agg(h, n), '{}'::jsonb) from (
        select extract(hour from starts_at at time zone 'Africa/Cairo')::int h, count(*) n from appointments
        where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to and status <> 'cancelled' group by 1) x),
    'by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'visits', n) order by d), '[]'::jsonb) from (
        select (starts_at at time zone 'Africa/Cairo')::date d, count(*) n from appointments
        where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to and status in ('completed', 'confirmed', 'pending')
        group by 1) x),
    'new_patients', (select count(*) from care_links where doctor_id = v_doc and started_at >= v_from and started_at < v_to),
    'active_patients', (select count(*) from care_links where doctor_id = v_doc and status = 'active'),
    'prescriptions', (select count(*) from prescriptions where doctor_id = v_doc and created_at >= v_from and created_at < v_to),
    'followups', (select count(*) from followups where doctor_id = v_doc and scheduled_at >= v_from and scheduled_at < v_to),
    'surgeries', (select count(*) from surgeries where doctor_id = v_doc and scheduled_at >= v_from and scheduled_at < v_to),
    'rating', (select jsonb_build_object('avg', rating_avg, 'count', rating_count) from doctors where id = v_doc),
    'finance', case when v_fin then jsonb_build_object(
        'income', (select coalesce(sum(amount), 0) from doctor_income where doctor_id = v_doc and paid_on between p_from and p_to),
        'expenses', (select coalesce(sum(amount), 0) from doctor_expenses where doctor_id = v_doc and spent_on between p_from and p_to),
        'top_services', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'count', n, 'amount', s) order by s desc), '[]'::jsonb)
                         from (select kind, count(*) n, sum(amount) s from doctor_income
                               where doctor_id = v_doc and paid_on between p_from and p_to group by kind) k),
        'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'income', i, 'expenses', e) order by m), '[]'::jsonb) from (
              select m, sum(i) i, sum(e) e from (
                select to_char(paid_on, 'YYYY-MM') m, amount i, 0 e from doctor_income where doctor_id = v_doc and paid_on between p_from and p_to
                union all
                select to_char(spent_on, 'YYYY-MM'), 0, amount from doctor_expenses where doctor_id = v_doc and spent_on between p_from and p_to) u
              group by m) y)) end,
    'offers', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'views', views, 'bookings', bookings) order by views desc), '[]'::jsonb)
               from (select * from doctor_offers where doctor_id = v_doc order by views desc limit 5) o));
end $$;

-- ---------------------------------------------------------------------
-- 5) Surgeries
-- ---------------------------------------------------------------------
create table public.surgeries (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients(id) on delete cascade,
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  name         text not null check (length(trim(name)) between 2 and 150),
  place        text check (place is null or length(place) <= 150),
  scheduled_at timestamptz,
  status       text not null default 'planned' check (status in ('planned', 'preparing', 'done', 'recovery', 'closed', 'cancelled')),
  prep         jsonb not null default '[]'::jsonb check (jsonb_typeof(prep) = 'array'),
  post         jsonb not null default '[]'::jsonb check (jsonb_typeof(post) = 'array'),
  notes        text check (notes is null or length(notes) <= 2000),
  fee          numeric(12,2) check (fee is null or fee >= 0),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_surgeries_doctor on public.surgeries (doctor_id, scheduled_at);
create index if not exists idx_surgeries_patient on public.surgeries (patient_id);
alter table public.surgeries enable row level security;
create policy surgeries_read on public.surgeries for select using (public.can_view_medical(patient_id, doctor_id));
revoke all on public.surgeries from anon;
grant select on public.surgeries to authenticated;
drop trigger if exists surgeries_touch on public.surgeries;
create trigger surgeries_touch before update on public.surgeries for each row execute function public.touch_updated_at();

create or replace function public.save_surgery(p_id uuid, p_patient uuid, p_name text, p_scheduled_at timestamptz default null,
  p_place text default null, p_status text default 'planned', p_prep jsonb default '[]'::jsonb, p_post jsonb default '[]'::jsonb,
  p_notes text default null, p_fee numeric default null, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid; v_old text;
begin
  if not acts_for(v_doc, 'medical') or not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    insert into surgeries (patient_id, doctor_id, name, place, scheduled_at, status, prep, post, notes, fee, created_by)
    values (p_patient, v_doc, trim(p_name), nullif(trim(p_place), ''), p_scheduled_at, coalesce(p_status, 'planned'),
            coalesce(p_prep, '[]'::jsonb), coalesce(p_post, '[]'::jsonb), nullif(trim(p_notes), ''), p_fee, auth.uid())
    returning id into v_id;
    perform _notify(p_patient, 'surgery', 'تجهيز للعملية 🏥',
                    trim(p_name) || coalesce(' — ' || to_char(p_scheduled_at at time zone 'Africa/Cairo', 'YYYY/MM/DD HH12:MI AM'), ''),
                    jsonb_build_object('surgery_id', v_id));
  else
    select status into v_old from surgeries where id = p_id and doctor_id = v_doc and patient_id = p_patient;
    update surgeries set name = trim(p_name), place = nullif(trim(p_place), ''), scheduled_at = p_scheduled_at,
           status = coalesce(p_status, status), prep = coalesce(p_prep, prep), post = coalesce(p_post, post),
           notes = nullif(trim(p_notes), ''), fee = p_fee
     where id = p_id and doctor_id = v_doc and patient_id = p_patient returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
    if v_old is distinct from p_status then
      perform _notify(p_patient, 'surgery', 'تحديث عن عمليتك', trim(p_name), jsonb_build_object('surgery_id', v_id));
    end if;
  end if;
  return v_id;
end $$;

create or replace function public.list_surgeries(p_patient uuid default null, p_doctor uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'patient_id', s.patient_id, 'patient_name', pp.full_name, 'doctor_id', s.doctor_id, 'doctor_name', dp.full_name,
      'name', s.name, 'place', s.place, 'scheduled_at', s.scheduled_at, 'status', s.status, 'prep', s.prep, 'post', s.post,
      'notes', s.notes, 'fee', case when acts_for(s.doctor_id, 'medical') then s.fee end, 'updated_at', s.updated_at)
      order by s.scheduled_at desc nulls first), '[]'::jsonb)
  from surgeries s join profiles pp on pp.id = s.patient_id join profiles dp on dp.id = s.doctor_id
  where (p_patient is null or s.patient_id = p_patient)
    and (p_doctor is null or s.doctor_id = p_doctor)
    and (p_patient is not null or p_doctor is not null or s.patient_id = auth.uid())
    and can_view_medical(s.patient_id, s.doctor_id);
$$;

-- ---------------------------------------------------------------------
-- 6) Chat between a patient and a clinic
-- ---------------------------------------------------------------------
create table public.messages (
  id         bigserial primary key,
  patient_id uuid not null references public.patients(id) on delete cascade,
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  sender_id  uuid references public.profiles(id) on delete set null,
  from_patient boolean not null,
  body       text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists idx_messages_thread on public.messages (doctor_id, patient_id, id);
alter table public.messages enable row level security;
create policy messages_read on public.messages for select using (
  patient_id = auth.uid() or public.acts_for(doctor_id, 'patients') or public.acts_for(doctor_id, 'bookings'));
revoke all on public.messages from anon;
grant select on public.messages to authenticated;

create or replace function public._can_chat_staff(p_doctor uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select acts_for(p_doctor, 'patients') or acts_for(p_doctor, 'bookings');
$$;

create or replace function public.send_message(p_doctor uuid, p_body text, p_patient uuid default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_patient uuid; v_from_patient boolean; v_id bigint; v_name text;
begin
  if p_patient is null or p_patient = auth.uid() then
    v_patient := auth.uid(); v_from_patient := true;
    if not exists (select 1 from care_links where patient_id = v_patient and doctor_id = p_doctor and status = 'active')
       and not exists (select 1 from appointments where patient_id = v_patient and doctor_id = p_doctor) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  else
    v_patient := p_patient; v_from_patient := false;
    if not _can_chat_staff(p_doctor)
       or (not exists (select 1 from care_links where patient_id = v_patient and doctor_id = p_doctor)
           and not exists (select 1 from appointments where patient_id = v_patient and doctor_id = p_doctor)) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  end if;
  if (select count(*) from messages where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'too many messages' using errcode = 'P0001';
  end if;
  insert into messages (patient_id, doctor_id, sender_id, from_patient, body)
  values (v_patient, p_doctor, auth.uid(), v_from_patient, trim(p_body)) returning id into v_id;
  select full_name into v_name from profiles where id = auth.uid();
  if v_from_patient then
    perform _notify_clinic(p_doctor, 'patients', 'chat', 'رسالة من ' || coalesce(v_name, ''), left(trim(p_body), 140),
                           jsonb_build_object('patient_id', v_patient, 'doctor_id', p_doctor));
  else
    perform _notify(v_patient, 'chat', 'رسالة من العيادة 💬', left(trim(p_body), 140),
                    jsonb_build_object('patient_id', v_patient, 'doctor_id', p_doctor));
  end if;
  return v_id;
end $$;

create or replace function public.chat_messages(p_doctor uuid, p_patient uuid default null, p_before bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_patient uuid := coalesce(p_patient, auth.uid()); v_staff boolean;
begin
  v_staff := v_patient <> auth.uid();
  if v_staff and not _can_chat_staff(p_doctor) then raise exception 'not allowed' using errcode = '42501'; end if;
  update messages set read_at = now()
   where doctor_id = p_doctor and patient_id = v_patient and read_at is null and from_patient = v_staff;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'from_patient', m.from_patient,
                                                       'sender', p.full_name, 'created_at', m.created_at, 'read', m.read_at is not null)
                                    order by m.id)
                   from (select * from messages where doctor_id = p_doctor and patient_id = v_patient
                           and (p_before is null or id < p_before) order by id desc limit 80) m
                   left join profiles p on p.id = m.sender_id), '[]'::jsonb);
end $$;

-- Conversations list: for a patient (their clinics) or for clinic staff (their patients).
create or replace function public.chat_threads(p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if p_doctor is null then
    return coalesce((select jsonb_agg(t.j order by t.last_at desc nulls last) from (
      select max(m.created_at) last_at, jsonb_build_object(
        'doctor_id', d.id, 'name', dp.full_name, 'avatar_url', dp.avatar_url,
        'last', (select body from messages x where x.doctor_id = d.id and x.patient_id = auth.uid() order by id desc limit 1),
        'last_at', max(m.created_at),
        'unread', count(m.id) filter (where not m.from_patient and m.read_at is null)) j
      from doctors d join profiles dp on dp.id = d.id
      left join messages m on m.doctor_id = d.id and m.patient_id = auth.uid()
      where exists (select 1 from care_links l where l.doctor_id = d.id and l.patient_id = auth.uid() and l.status = 'active')
         or exists (select 1 from messages x where x.doctor_id = d.id and x.patient_id = auth.uid())
      group by d.id, dp.full_name, dp.avatar_url) t), '[]'::jsonb);
  end if;
  if not _can_chat_staff(p_doctor) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(t.j order by t.last_at desc) from (
    select max(m.created_at) last_at, jsonb_build_object(
      'patient_id', m.patient_id, 'name', pp.full_name, 'avatar_url', pp.avatar_url, 'phone', pp.phone,
      'last', (select body from messages x where x.doctor_id = p_doctor and x.patient_id = m.patient_id order by id desc limit 1),
      'last_at', max(m.created_at),
      'unread', count(*) filter (where m.from_patient and m.read_at is null)) j
    from messages m join profiles pp on pp.id = m.patient_id
    where m.doctor_id = p_doctor
    group by m.patient_id, pp.full_name, pp.avatar_url, pp.phone) t), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 7) Basic health profile
-- ---------------------------------------------------------------------
create table public.patient_health (
  patient_id     uuid primary key references public.patients(id) on delete cascade,
  blood_type     text check (blood_type is null or blood_type in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  allergies      text[] not null default '{}',
  chronic        text[] not null default '{}',
  medications    text check (medications is null or length(medications) <= 1000),
  past_surgeries text check (past_surgeries is null or length(past_surgeries) <= 1000),
  family_history text check (family_history is null or length(family_history) <= 1000),
  smoker         boolean,
  pregnant       boolean,
  height_cm      numeric(5,1) check (height_cm is null or height_cm between 30 and 260),
  weight_kg      numeric(5,1) check (weight_kg is null or weight_kg between 1 and 400),
  emergency_name  text check (emergency_name is null or length(emergency_name) <= 120),
  emergency_phone text check (emergency_phone is null or length(emergency_phone) <= 30),
  updated_by     uuid references public.profiles(id) on delete set null,
  updated_at     timestamptz not null default now()
);
alter table public.patient_health enable row level security;
create policy health_read on public.patient_health for select using (
  patient_id = auth.uid() or exists (select 1 from public.care_links l where l.patient_id = patient_health.patient_id
                                     and l.status = 'active' and public.acts_for(l.doctor_id, 'medical')));
revoke all on public.patient_health from anon;
grant select on public.patient_health to authenticated;

create or replace function public._can_health(p_patient uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() = p_patient or exists (select 1 from care_links l where l.patient_id = p_patient
                                            and l.status = 'active' and acts_for(l.doctor_id, 'medical'));
$$;

create or replace function public.get_health(p_patient uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := coalesce(p_patient, auth.uid()); r jsonb;
begin
  if not _can_health(v) then raise exception 'not allowed' using errcode = '42501'; end if;
  select to_jsonb(h) - 'patient_id' || jsonb_build_object('updated_by_name', p.full_name,
         'birth_date', pr.birth_date, 'gender', pr.gender) into r
    from patient_health h left join profiles p on p.id = h.updated_by join profiles pr on pr.id = h.patient_id
   where h.patient_id = v;
  if r is null then
    select jsonb_build_object('birth_date', birth_date, 'gender', gender, 'allergies', '[]'::jsonb, 'chronic', '[]'::jsonb, 'empty', true)
      into r from profiles where id = v;
  end if;
  return r;
end $$;

create or replace function public.save_health(p_patient uuid, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := coalesce(p_patient, auth.uid());
begin
  if not _can_health(v) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into patient_health (patient_id, blood_type, allergies, chronic, medications, past_surgeries, family_history,
                              smoker, pregnant, height_cm, weight_kg, emergency_name, emergency_phone, updated_by, updated_at)
  values (v, nullif(p_data->>'blood_type', ''),
          coalesce((select array_agg(left(trim(x), 80)) from jsonb_array_elements_text(coalesce(p_data->'allergies', '[]')) x where trim(x) <> ''), '{}'),
          coalesce((select array_agg(left(trim(x), 80)) from jsonb_array_elements_text(coalesce(p_data->'chronic', '[]')) x where trim(x) <> ''), '{}'),
          nullif(trim(p_data->>'medications'), ''), nullif(trim(p_data->>'past_surgeries'), ''),
          nullif(trim(p_data->>'family_history'), ''), (p_data->>'smoker')::boolean, (p_data->>'pregnant')::boolean,
          nullif(p_data->>'height_cm', '')::numeric, nullif(p_data->>'weight_kg', '')::numeric,
          nullif(trim(p_data->>'emergency_name'), ''), nullif(trim(p_data->>'emergency_phone'), ''), auth.uid(), now())
  on conflict (patient_id) do update set
    blood_type = excluded.blood_type, allergies = excluded.allergies, chronic = excluded.chronic,
    medications = excluded.medications, past_surgeries = excluded.past_surgeries, family_history = excluded.family_history,
    smoker = excluded.smoker, pregnant = excluded.pregnant, height_cm = excluded.height_cm, weight_kg = excluded.weight_kg,
    emergency_name = excluded.emergency_name, emergency_phone = excluded.emergency_phone,
    updated_by = auth.uid(), updated_at = now();
end $$;

-- ---------------------------------------------------------------------
-- 8) Doctor reviews
-- ---------------------------------------------------------------------
create table public.doctor_reviews (
  id         uuid primary key default gen_random_uuid(),
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  stars      smallint not null check (stars between 1 and 5),
  comment    text check (comment is null or length(comment) <= 600),
  hidden     boolean not null default false,
  reply      text check (reply is null or length(reply) <= 600),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (doctor_id, patient_id)
);
alter table public.doctor_reviews enable row level security;
create policy reviews_read on public.doctor_reviews for select using (not hidden or patient_id = auth.uid()
  or public.acts_for(doctor_id, 'any') or public.is_admin());
revoke all on public.doctor_reviews from anon;
grant select on public.doctor_reviews to authenticated;

create or replace function public._refresh_rating(p_doctor uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('doctori.trusted_verify', '1', true);
  update doctors set
    rating_avg = coalesce((select round(avg(stars)::numeric, 2) from doctor_reviews where doctor_id = p_doctor and not hidden), 0),
    rating_count = (select count(*) from doctor_reviews where doctor_id = p_doctor and not hidden)
  where id = p_doctor;
  perform set_config('doctori.trusted_verify', '', true);
end $$;
revoke all on function public._refresh_rating(uuid) from public, anon, authenticated;

create or replace function public.submit_review(p_doctor uuid, p_stars int, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from appointments where doctor_id = p_doctor and patient_id = auth.uid() and status = 'completed')
     and not exists (select 1 from care_links where doctor_id = p_doctor and patient_id = auth.uid()) then
    raise exception 'only patients of this doctor can review' using errcode = '42501';
  end if;
  insert into doctor_reviews (doctor_id, patient_id, stars, comment)
  values (p_doctor, auth.uid(), p_stars, nullif(trim(p_comment), ''))
  on conflict (doctor_id, patient_id) do update set stars = excluded.stars, comment = excluded.comment, updated_at = now();
  perform _refresh_rating(p_doctor);
  perform _notify(p_doctor, 'review', 'تقييم جديد ⭐ ' || p_stars, left(coalesce(trim(p_comment), ''), 140), '{}'::jsonb);
end $$;

create or replace function public.reply_review(p_id uuid, p_reply text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update doctor_reviews set reply = nullif(trim(p_reply), '') where id = p_id and doctor_id = auth.uid();
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $$;

create or replace function public.admin_hide_review(p_id uuid, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update doctor_reviews set hidden = coalesce(p_hidden, true) where id = p_id returning doctor_id into v_doc;
  if v_doc is not null then perform _refresh_rating(v_doc); end if;
end $$;

create or replace function public.doctor_reviews_list(p_doctor uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'avg', (select rating_avg from doctors where id = p_doctor),
    'count', (select rating_count from doctors where id = p_doctor),
    'mine', (select jsonb_build_object('stars', stars, 'comment', comment) from doctor_reviews
             where doctor_id = p_doctor and patient_id = auth.uid()),
    'can_review', exists (select 1 from appointments where doctor_id = p_doctor and patient_id = auth.uid() and status = 'completed')
                  or exists (select 1 from care_links where doctor_id = p_doctor and patient_id = auth.uid()),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'stars', r.stars, 'comment', r.comment, 'reply', r.reply, 'created_at', r.created_at, 'hidden', r.hidden,
        'name', case when acts_for(p_doctor, 'any') or is_admin() then p.full_name
                     else split_part(p.full_name, ' ', 1) end) order by r.created_at desc)
      from (select * from doctor_reviews where doctor_id = p_doctor
              and (not hidden or acts_for(p_doctor, 'any') or is_admin()) order by created_at desc limit 100) r
      join profiles p on p.id = r.patient_id), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- Live updates for the app (Supabase Realtime) where available
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.clinic_queue; exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke all on function public.my_notifications(int), public.mark_notifications_read(bigint),
  public.queue_add(uuid, uuid, text, uuid), public.queue_checkin(uuid), public.queue_set_status(uuid, text),
  public.queue_call_next(uuid), public.queue_today(uuid), public.my_queue(),
  public._can_stock(uuid), public.save_inventory_item(uuid, text, text, text, numeric, numeric, numeric, uuid),
  public.delete_inventory_item(uuid), public.inventory_move(uuid, numeric, text, text, numeric, boolean), public.list_inventory(uuid),
  public.doctor_reports(date, date, uuid),
  public.save_surgery(uuid, uuid, text, timestamptz, text, text, jsonb, jsonb, text, numeric, uuid), public.list_surgeries(uuid, uuid),
  public._can_chat_staff(uuid), public.send_message(uuid, text, uuid), public.chat_messages(uuid, uuid, bigint), public.chat_threads(uuid),
  public._can_health(uuid), public.get_health(uuid), public.save_health(uuid, jsonb),
  public.submit_review(uuid, int, text), public.reply_review(uuid, text), public.admin_hide_review(uuid, boolean),
  public.doctor_reviews_list(uuid)
from public, anon;
grant execute on function public.my_notifications(int), public.mark_notifications_read(bigint),
  public.queue_add(uuid, uuid, text, uuid), public.queue_checkin(uuid), public.queue_set_status(uuid, text),
  public.queue_call_next(uuid), public.queue_today(uuid), public.my_queue(),
  public._can_stock(uuid), public.save_inventory_item(uuid, text, text, text, numeric, numeric, numeric, uuid),
  public.delete_inventory_item(uuid), public.inventory_move(uuid, numeric, text, text, numeric, boolean), public.list_inventory(uuid),
  public.doctor_reports(date, date, uuid),
  public.save_surgery(uuid, uuid, text, timestamptz, text, text, jsonb, jsonb, text, numeric, uuid), public.list_surgeries(uuid, uuid),
  public._can_chat_staff(uuid), public.send_message(uuid, text, uuid), public.chat_messages(uuid, uuid, bigint), public.chat_threads(uuid),
  public._can_health(uuid), public.get_health(uuid), public.save_health(uuid, jsonb),
  public.submit_review(uuid, int, text), public.reply_review(uuid, text), public.admin_hide_review(uuid, boolean),
  public.doctor_reviews_list(uuid)
to authenticated;
