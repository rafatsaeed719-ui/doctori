-- Tests for 0019 (live sync pings). Run after phase5.
\set QUIET on
set client_min_messages = warning;
delete from t.results;
reset role;
select set_config('request.jwt.claim.sub', '', false);
delete from sync_pings;
create temp table who as
  select (select id from profiles where full_name = 'استقبال المركز') as recep,
         (select id from profiles where role = 'assistant' and full_name = 'سكرتيرة') as asst;
grant select on who to authenticated;
-- The center reception records a payment for the owner-doctor (eeee).
insert into doctor_income (doctor_id, kind, amount, paid_on, patient_name, center_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'visit', 250, current_date, 'مزامنة',
        (select center_id from center_members where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' and role = 'owner' limit 1));
-- A booking for patient f1 with eeee.
insert into appointments (doctor_id, clinic_id, patient_id, starts_at, ends_at, status)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'c1c1c1c1-0000-0000-0000-000000000001', 'f1f1f1f1-0000-0000-0000-000000000001',
        now() + interval '3 days', now() + interval '3 days 20 minutes', 'pending');
-- The removed doctor (dddd) gets income: the center staff must not be pinged.
insert into doctor_income (doctor_id, kind, amount, paid_on) values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'visit', 100, current_date);
-- A medical note on f1's file (patient-only row) reaches f1's doctors.
insert into medical_entries (patient_id, kind, title, body) values ('f1f1f1f1-0000-0000-0000-000000000001', 'note', 'x', 'y');
set role authenticated;

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok(exists (select 1 from sync_pings where scope = 'finance') and exists (select 1 from sync_pings where scope = 'bookings'),
            'S01 the doctor is pinged when the secretary records money or a booking');
select t.ok(exists (select 1 from sync_pings where scope = 'medical'), 'S02 a change in a patient''s file reaches the patient''s doctor');
select set_config('request.jwt.claim.sub', (select recep::text from who), false);
select t.ok((select count(*) from sync_pings where scope = 'finance') = 1, 'S03 center reception is pinged for its doctors only (not the removed one)');
select t.ok(exists (select 1 from sync_pings where scope = 'bookings'), 'S04 … and for their bookings');
select set_config('request.jwt.claim.sub', (select asst::text from who), false);
select t.ok(exists (select 1 from sync_pings where scope = 'bookings'), 'S05 the doctor''s own assistant is pinged');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok(exists (select 1 from sync_pings where scope = 'bookings'), 'S06 the patient is pinged about their booking');
select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.ok((select count(*) from sync_pings) = 0, 'S07 other users see no pings');
select t.fails($$insert into sync_pings (user_id, scope) values ('f1f1f1f1-0000-0000-0000-000000000001', 'x')$$, 'S08 nobody can forge pings');

reset role;
\set QUIET off
select count(*) as sync_tests_passed from t.results;
