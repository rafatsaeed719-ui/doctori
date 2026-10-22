-- =====================================================================
-- دكتوري — 0012: رصيدي اليومي (إيرادات الحالات + المصروفات + الصافي)
-- * doctor_income: each paid case — كشف / إعادة / تحليل / أشعة / جلسة / إجراء / أخرى.
-- * doctor_expenses: what the doctor spent — type, amount, reason.
-- * Day / month / year summaries and a calendar of cases + net per day (Cairo dates).
-- * Doctors can let an assistant (receptionist) record and see the ledger: can_finance.
-- =====================================================================

alter table public.doctor_assistants add column if not exists can_finance boolean not null default false;
alter table public.doctors add column if not exists price_list jsonb not null default '{}'::jsonb
  check (jsonb_typeof(price_list) = 'object' and pg_column_size(price_list) < 4000);

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
                else false end);
$$;

create table public.doctor_income (
  id             uuid primary key default gen_random_uuid(),
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  patient_id     uuid references public.patients(id) on delete set null,
  patient_name   text check (patient_name is null or length(patient_name) <= 120),
  kind           text not null check (kind in ('visit', 'revisit', 'lab', 'xray', 'session', 'procedure', 'other')),
  amount         numeric(12,2) not null check (amount > 0 and amount < 10000000),
  paid_on        date not null,
  note           text check (note is null or length(note) <= 300),
  appointment_id uuid references public.appointments(id) on delete set null,
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now()
);
create index if not exists idx_doctor_income_day on public.doctor_income (doctor_id, paid_on);
alter table public.doctor_income enable row level security;
create policy income_read on public.doctor_income for select using (public.acts_for(doctor_id, 'finance'));
revoke all on public.doctor_income from anon;
grant select on public.doctor_income to authenticated;

create table public.doctor_expenses (
  id          uuid primary key default gen_random_uuid(),
  doctor_id   uuid not null references public.doctors(id) on delete cascade,
  category    text not null check (category in ('rent', 'salaries', 'supplies', 'utilities', 'equipment',
                                                'maintenance', 'lab', 'marketing', 'transport', 'other')),
  amount      numeric(12,2) not null check (amount > 0 and amount < 10000000),
  spent_on    date not null,
  reason      text check (reason is null or length(reason) <= 300),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_doctor_expenses_day on public.doctor_expenses (doctor_id, spent_on);
alter table public.doctor_expenses enable row level security;
create policy expenses_read on public.doctor_expenses for select using (public.acts_for(doctor_id, 'finance'));
revoke all on public.doctor_expenses from anon;
grant select on public.doctor_expenses to authenticated;

-- ---------------------------------------------------------------------
-- Writes
-- ---------------------------------------------------------------------
create or replace function public.save_income(
  p_id uuid, p_kind text, p_amount numeric, p_on date default null,
  p_patient uuid default null, p_patient_name text default null, p_note text default null,
  p_appointment uuid default null, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_patient is not null and not exists (select 1 from care_links where patient_id = p_patient and doctor_id = v_doc)
     and not exists (select 1 from appointments where patient_id = p_patient and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_appointment is not null and not exists (select 1 from appointments where id = p_appointment and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    insert into doctor_income (doctor_id, patient_id, patient_name, kind, amount, paid_on, note, appointment_id, created_by)
    values (v_doc, p_patient, nullif(trim(p_patient_name), ''), p_kind, p_amount,
            coalesce(p_on, (now() at time zone 'Africa/Cairo')::date), nullif(trim(p_note), ''), p_appointment, auth.uid())
    returning id into v_id;
  else
    update doctor_income set patient_id = p_patient, patient_name = nullif(trim(p_patient_name), ''), kind = p_kind,
           amount = p_amount, paid_on = coalesce(p_on, paid_on), note = nullif(trim(p_note), ''),
           appointment_id = coalesce(p_appointment, appointment_id)
     where id = p_id and doctor_id = v_doc returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.save_expense(
  p_id uuid, p_category text, p_amount numeric, p_on date default null, p_reason text default null,
  p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is null then
    insert into doctor_expenses (doctor_id, category, amount, spent_on, reason, created_by)
    values (v_doc, p_category, p_amount, coalesce(p_on, (now() at time zone 'Africa/Cairo')::date),
            nullif(trim(p_reason), ''), auth.uid())
    returning id into v_id;
  else
    update doctor_expenses set category = p_category, amount = p_amount, spent_on = coalesce(p_on, spent_on),
           reason = nullif(trim(p_reason), '')
     where id = p_id and doctor_id = v_doc returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.delete_finance_entry(p_type text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_amount numeric;
begin
  if p_type = 'income' then
    select doctor_id, amount into v_doc, v_amount from doctor_income where id = p_id;
  elsif p_type = 'expense' then
    select doctor_id, amount into v_doc, v_amount from doctor_expenses where id = p_id;
  end if;
  if v_doc is null or not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_type = 'income' then delete from doctor_income where id = p_id; else delete from doctor_expenses where id = p_id; end if;
  perform write_audit('finance.deleted', case when p_type = 'income' then 'doctor_income' else 'doctor_expenses' end,
                      p_id::text, jsonb_build_object('doctor_id', v_doc, 'amount', v_amount));
end $$;

create or replace function public.set_price_list(p_prices jsonb, p_doctor uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if auth.uid() is distinct from v_doc or not acts_for(v_doc, 'finance') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update doctors set price_list = coalesce(p_prices, '{}'::jsonb) where id = v_doc;
end $$;

create or replace function public.set_assistant_finance(p_assistant uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update doctor_assistants set can_finance = coalesce(p_on, false)
   where doctor_id = auth.uid() and assistant_id = p_assistant;
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('assistant.permissions_changed', 'profiles', p_assistant::text, jsonb_build_object('finance', p_on));
end $$;

-- ---------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------
create or replace function public.finance_day(p_day date default null, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
        v_day date := coalesce(p_day, (now() at time zone 'Africa/Cairo')::date);
        v_in numeric; v_out numeric; v_cases int;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  select coalesce(sum(amount), 0), count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text))
    into v_in, v_cases from doctor_income where doctor_id = v_doc and paid_on = v_day;
  select coalesce(sum(amount), 0) into v_out from doctor_expenses where doctor_id = v_doc and spent_on = v_day;
  return jsonb_build_object(
    'day', v_day, 'income', v_in, 'expenses', v_out, 'net', v_in - v_out, 'cases', v_cases,
    'by_kind', (select coalesce(jsonb_object_agg(kind, jsonb_build_object('count', n, 'amount', s)), '{}'::jsonb)
                from (select kind, count(*) n, sum(amount) s from doctor_income
                      where doctor_id = v_doc and paid_on = v_day group by kind) k),
    'income_items', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', i.id, 'kind', i.kind, 'amount', i.amount, 'note', i.note, 'patient_id', i.patient_id,
          'patient_name', coalesce(p.full_name, i.patient_name), 'patient_avatar', p.avatar_url,
          'created_at', i.created_at, 'by', cb.full_name) order by i.created_at), '[]'::jsonb)
        from doctor_income i left join profiles p on p.id = i.patient_id left join profiles cb on cb.id = i.created_by
        where i.doctor_id = v_doc and i.paid_on = v_day),
    'expense_items', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', e.id, 'category', e.category, 'amount', e.amount, 'reason', e.reason,
          'created_at', e.created_at, 'by', cb.full_name) order by e.created_at), '[]'::jsonb)
        from doctor_expenses e left join profiles cb on cb.id = e.created_by
        where e.doctor_id = v_doc and e.spent_on = v_day),
    'prices', (select price_list from doctors where id = v_doc));
end $$;

create or replace function public.finance_month(p_year int, p_month int, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
        v_from date := make_date(p_year, p_month, 1);
        v_to date := (make_date(p_year, p_month, 1) + interval '1 month')::date;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with inc as (
      select paid_on d, sum(amount) s, count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text)) c
      from doctor_income where doctor_id = v_doc and paid_on >= v_from and paid_on < v_to group by paid_on),
    exp as (
      select spent_on d, sum(amount) s from doctor_expenses
      where doctor_id = v_doc and spent_on >= v_from and spent_on < v_to group by spent_on),
    days as (
      select coalesce(inc.d, exp.d) d, coalesce(inc.s, 0) i, coalesce(exp.s, 0) e, coalesce(inc.c, 0) c
      from inc full join exp on exp.d = inc.d)
    select jsonb_build_object(
      'year', p_year, 'month', p_month,
      'days', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'income', i, 'expenses', e, 'net', i - e, 'cases', c)
                                         order by d), '[]'::jsonb) from days),
      'income', (select coalesce(sum(i), 0) from days),
      'expenses', (select coalesce(sum(e), 0) from days),
      'net', (select coalesce(sum(i - e), 0) from days),
      'cases', (select coalesce(sum(c), 0) from days),
      'by_kind', (select coalesce(jsonb_object_agg(kind, jsonb_build_object('count', n, 'amount', s)), '{}'::jsonb)
                  from (select kind, count(*) n, sum(amount) s from doctor_income
                        where doctor_id = v_doc and paid_on >= v_from and paid_on < v_to group by kind) k),
      'by_category', (select coalesce(jsonb_object_agg(category, jsonb_build_object('count', n, 'amount', s)), '{}'::jsonb)
                      from (select category, count(*) n, sum(amount) s from doctor_expenses
                            where doctor_id = v_doc and spent_on >= v_from and spent_on < v_to group by category) k)));
end $$;

create or replace function public.finance_year(p_year int, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with m as (select generate_series(1, 12) mo),
    inc as (select extract(month from paid_on)::int mo, sum(amount) s, count(*) c from doctor_income
            where doctor_id = v_doc and extract(year from paid_on) = p_year group by 1),
    exp as (select extract(month from spent_on)::int mo, sum(amount) s from doctor_expenses
            where doctor_id = v_doc and extract(year from spent_on) = p_year group by 1)
    select jsonb_build_object('year', p_year,
      'months', jsonb_agg(jsonb_build_object('month', m.mo, 'income', coalesce(inc.s, 0), 'expenses', coalesce(exp.s, 0),
                                             'net', coalesce(inc.s, 0) - coalesce(exp.s, 0), 'entries', coalesce(inc.c, 0))
                          order by m.mo),
      'income', coalesce(sum(inc.s), 0), 'expenses', coalesce(sum(exp.s), 0),
      'net', coalesce(sum(inc.s), 0) - coalesce(sum(exp.s), 0))
    from m left join inc on inc.mo = m.mo left join exp on exp.mo = m.mo);
end $$;

-- Assistants list and context include the finance permission.
create or replace function public.doctor_list_assistants()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'assistant_id', a.assistant_id, 'full_name', p.full_name, 'phone', p.phone, 'avatar_url', p.avatar_url,
           'is_suspended', p.is_suspended, 'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
           'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical, 'can_finance', a.can_finance,
           'created_at', a.created_at)
         order by a.created_at), '[]'::jsonb)
  from doctor_assistants a join profiles p on p.id = a.assistant_id
  where a.doctor_id = auth.uid();
$$;

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
      where a.assistant_id = p.id))
  from profiles p
  left join doctors d on d.id = p.id
  left join specialties s on s.id = d.specialty_id
  where p.id = auth.uid();
$$;

revoke all on function public.save_income(uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.save_expense(uuid, text, numeric, date, text, uuid), public.delete_finance_entry(text, uuid),
  public.set_price_list(jsonb, uuid), public.set_assistant_finance(uuid, boolean),
  public.finance_day(date, uuid), public.finance_month(int, int, uuid), public.finance_year(int, uuid)
from public, anon;
grant execute on function public.save_income(uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.save_expense(uuid, text, numeric, date, text, uuid), public.delete_finance_entry(text, uuid),
  public.set_price_list(jsonb, uuid), public.set_assistant_finance(uuid, boolean),
  public.finance_day(date, uuid), public.finance_month(int, int, uuid), public.finance_year(int, uuid)
to authenticated;
