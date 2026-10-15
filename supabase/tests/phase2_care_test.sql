-- Tests for 0009 (assistants, medical file, medications, bookings). Run after the earlier test files.
\set QUIET on
set client_min_messages = warning;
delete from t.results;
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ---------- Fixtures ----------
insert into auth.users (id, email, raw_user_meta_data) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'doctor.e@test.local', '{"full_name":"د. إيمان","role":"doctor","phone":"01011112222"}'),
  ('f1f1f1f1-0000-0000-0000-000000000001', 'f1@test.local', '{"full_name":"مريض كامل"}'),
  ('f2f2f2f2-0000-0000-0000-000000000002', 'f2@test.local', '{"full_name":"مريض جزئي"}'),
  ('f3f3f3f3-0000-0000-0000-000000000003', 'f3@test.local', '{"full_name":"مريض غير مرتبط"}');
update doctors set status = 'verified', specialty_id = 1, appointment_minutes = 20 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
insert into clinics (id, doctor_id, name, address) values
  ('c1c1c1c1-0000-0000-0000-000000000001', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'عيادة اختبار', 'عنوان');
insert into clinic_hours (clinic_id, weekday, opens_at, closes_at)
select 'c1c1c1c1-0000-0000-0000-000000000001', d, '09:00', '12:00' from generate_series(0, 6) d;

set role authenticated;
-- f1 joins with full sharing, f2 with own_uploads; doctor accepts both
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
create temp table r1 as select request_join('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', null, null, 'full') as id;
select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
create temp table r2 as select request_join('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', null, null, 'own_uploads') as id;
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select respond_join((select id from r1), true), respond_join((select id from r2), true);

-- ---------- Assistants ----------
create temp table asst as select doctor_create_assistant('مساعدة سارة', '01099998888', 'assistpass1', true, false, false, false) as r;
select t.ok((select r->>'phone' from asst) = '201099998888', 'D01 doctor creates an assistant with a mobile login');
select t.ok(jsonb_array_length(doctor_list_assistants()) = 1, 'D02 doctor lists assistants');

select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst), false);
select t.ok((get_my_context()->>'role') = 'assistant'
            and (get_my_context()->'assistant_of'->>'doctor_id') = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
            'D03 assistant context names the doctor');
select t.ok((select count(*) from doctor_my_patients('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 0,
            'D04 bookings-only assistant cannot list patients');
select t.ok(jsonb_array_length(list_medical_entries('f1f1f1f1-0000-0000-0000-000000000001')) = 0
            and not can_view_medical('f1f1f1f1-0000-0000-0000-000000000001', null),
            'D05 bookings-only assistant cannot see medical files');
select t.fails($$select doctor_update_assistant(auth.uid(), true, true, true, true)$$, 'D06 assistant cannot change own permissions');
select t.fails($$select doctor_create_assistant('x', '01011110000', 'password123')$$, 'D07 assistant cannot create assistants');

-- ---------- Medical file ----------
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
insert into medical_entries (patient_id, kind, title, body, created_by)
values (auth.uid(), 'note', 'ضغط', 'الضغط 130/85 الصبح', auth.uid());
insert into medical_entries (patient_id, kind, title, storage_path, mime_type, created_by)
values (auth.uid(), 'image', 'تحليل', 'f1f1f1f1-0000-0000-0000-000000000001/1_lab.png', 'image/png', auth.uid());
select t.fails($$insert into medical_entries (patient_id, kind, body, created_by)
                 values ('f2f2f2f2-0000-0000-0000-000000000002', 'note', 'x', auth.uid())$$,
               'E01 patient cannot add to another patient file');
select t.fails($$insert into medical_entries (patient_id, kind, created_by) values (auth.uid(), 'note', auth.uid())$$,
               'E02 empty note rejected');

select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
insert into medical_entries (patient_id, kind, body, created_by) values (auth.uid(), 'note', 'خاص بيا', auth.uid());
insert into medical_entries (patient_id, kind, body, shared_with, created_by)
values (auth.uid(), 'note', 'مبعوت للدكتورة', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', auth.uid());
select t.fails($$insert into medical_entries (patient_id, kind, body, shared_with, created_by)
                 values (auth.uid(), 'note', 'x', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', auth.uid())$$,
               'E03 cannot send an item to a doctor you are not linked to');

select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
insert into medical_entries (patient_id, kind, body, created_by) values (auth.uid(), 'note', 'سري', auth.uid());
select t.ok((select count(*) from medical_entries) = 1, 'E04 a patient sees only their own items');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok(jsonb_array_length(list_medical_entries('f1f1f1f1-0000-0000-0000-000000000001')) = 2, 'E05 full sharing: doctor sees all items');
select t.ok(jsonb_array_length(list_medical_entries('f2f2f2f2-0000-0000-0000-000000000002')) = 1
            and (list_medical_entries('f2f2f2f2-0000-0000-0000-000000000002')->0->>'body') = 'مبعوت للدكتورة',
            'E06 own-uploads sharing: doctor sees only items sent to them');
select t.ok(jsonb_array_length(list_medical_entries('f3f3f3f3-0000-0000-0000-000000000003')) = 0, 'E07 unlinked patient file is hidden');
select t.ok(can_view_medical_object('f1f1f1f1-0000-0000-0000-000000000001/1_lab.png'), 'E08 doctor may open the shared file');
select t.ok((select count(*) from medical_entries where patient_id = 'f3f3f3f3-0000-0000-0000-000000000003') = 0,
            'E09 table access also hides the unlinked patient');

-- assistant gets medical permission
select doctor_update_assistant((select (r->>'assistant_id')::uuid from asst), true, true, false, true);
select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst), false);
select t.ok(jsonb_array_length(list_medical_entries('f1f1f1f1-0000-0000-0000-000000000001')) = 2,
            'E10 assistant with medical permission sees the shared file');
select t.ok((select count(*) from doctor_my_patients('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 2,
            'E11 assistant with patients permission lists patients');

-- ---------- Medications ----------
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
insert into medications (patient_id, name, dose, every_hours, first_time) values (auth.uid(), 'فيتامين د', 'قرص', 24, '09:00');
select t.fails($$insert into medications (patient_id, prescribed_by, name) values (auth.uid(), 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'مزور')$$,
               'M01 patient cannot fake a doctor prescription');
select t.fails($$insert into medications (patient_id, name, every_hours) values (auth.uid(), 'x', 5)$$, 'M02 invalid interval rejected');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table rx as select prescribe_medication('f1f1f1f1-0000-0000-0000-000000000001', 'أموكسيسيلين 500', 'كبسولة',
  8, '08:00', null, null, 'بعد الأكل') as id;
select prescribe_medication('f2f2f2f2-0000-0000-0000-000000000002', 'باراسيتامول', 'قرص', 12, '10:00');
select t.fails($$select prescribe_medication('f3f3f3f3-0000-0000-0000-000000000003', 'x', null, 24, '09:00')$$,
               'M03 cannot prescribe to an unlinked patient');
select t.ok(jsonb_array_length(list_medications('f1f1f1f1-0000-0000-0000-000000000001')) = 2, 'M04 full sharing: doctor sees all medicines');

select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
insert into medications (patient_id, name) values (auth.uid(), 'دوا خاص');
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok(jsonb_array_length(list_medications('f2f2f2f2-0000-0000-0000-000000000002')) = 1,
            'M05 own-uploads: doctor sees only what they prescribed');

select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok(jsonb_array_length(list_medications()) = 2, 'M06 patient sees self-added and prescribed medicines');
update medications set name = 'تعديل' where id = (select id from rx);
select t.ok((select name from medications where id = (select id from rx)) = 'أموكسيسيلين 500', 'M07 patient cannot edit a prescription');
select set_med_reminders((select id from rx), false);
select t.ok((select not reminders_on from medications where id = (select id from rx)), 'M08 patient can silence reminders');
insert into medication_doses (medication_id, patient_id) values ((select id from rx), auth.uid());
select t.fails($$insert into medication_doses (medication_id, patient_id)
                 select id, 'f2f2f2f2-0000-0000-0000-000000000002' from medications limit 1$$, 'M09 cannot log doses for someone else');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok((select (m->>'doses_7d')::int from jsonb_array_elements(list_medications('f1f1f1f1-0000-0000-0000-000000000001')) m
             where m->>'id' = (select id::text from rx)) = 1, 'M10 doctor sees dose adherence');
select stop_prescription((select id from rx));
select t.ok((select not is_active from medications where id = (select id from rx)), 'M11 doctor stops a prescription');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.fails(format('select stop_prescription(%L)', (select id from rx)), 'M12 patient cannot stop through doctor function');

-- ---------- Bookings ----------
create temp table day as select ((now() at time zone 'Africa/Cairo')::date + 1) as d;
select t.ok((select count(*) from clinic_slots('c1c1c1c1-0000-0000-0000-000000000001', (select d from day))) = 9,
            'B01 3 hours at 20 minutes = 9 slots');
create temp table slots as select * from clinic_slots('c1c1c1c1-0000-0000-0000-000000000001', (select d from day)) order by starts_at;

select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
create temp table b1 as select book_appointment('c1c1c1c1-0000-0000-0000-000000000001', (select min(starts_at) from slots), 'كشف أول مرة') as id;
select t.ok((select status from appointments where id = (select id from b1)) = 'pending', 'B02 patient booking starts as pending');
select t.fails(format('select book_appointment(%L, %L)', 'c1c1c1c1-0000-0000-0000-000000000001',
               (select min(starts_at) + interval '5 minutes' from slots)), 'B03 off-grid time rejected');

select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.fails(format('select book_appointment(%L, %L)', 'c1c1c1c1-0000-0000-0000-000000000001', (select min(starts_at) from slots)),
               'B04 a taken slot cannot be double-booked');
select t.ok(not (select available from clinic_slots('c1c1c1c1-0000-0000-0000-000000000001', (select d from day)) order by starts_at limit 1),
            'B05 taken slot shows as unavailable');
select t.ok((select count(*) from appointments) = 0, 'B06 patient does not see other patients bookings');

select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
select set_appointment_status((select id from b1), 'cancelled');
select t.ok((select status from appointments where id = (select id from b1)) = 'cancelled', 'B07 patient cancels own booking');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
create temp table b2 as select book_appointment('c1c1c1c1-0000-0000-0000-000000000001', (select min(starts_at) from slots)) as id;
select t.ok((select id from b2) is not null, 'B08 a cancelled slot can be booked again');
select t.fails(format('select set_appointment_status(%L, %L)', (select id from b2), 'completed'),
               'B09 patient cannot mark a visit completed');
select book_appointment('c1c1c1c1-0000-0000-0000-000000000001', (select starts_at from slots order by starts_at offset 1 limit 1));
select t.fails(format('select book_appointment(%L, %L)', 'c1c1c1c1-0000-0000-0000-000000000001',
               (select starts_at from slots order by starts_at offset 2 limit 1)), 'B10 max 2 upcoming bookings per doctor');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok(jsonb_array_length(doctor_appointments((select d from day), (select d from day))) = 3, 'B11 doctor sees the day bookings');
select set_appointment_status((select id from b2), 'confirmed');
select t.ok((select status from appointments where id = (select id from b2)) = 'confirmed', 'B12 doctor confirms');
select book_appointment('c1c1c1c1-0000-0000-0000-000000000001', (select starts_at from slots order by starts_at offset 4 limit 1), null,
                        'f2f2f2f2-0000-0000-0000-000000000002');
select t.ok((select status from appointments where patient_id = 'f2f2f2f2-0000-0000-0000-000000000002') = 'confirmed',
            'B13 staff booking for a linked patient is confirmed');
select t.fails(format('select book_appointment(%L, %L, null, %L)', 'c1c1c1c1-0000-0000-0000-000000000001',
               (select starts_at from slots order by starts_at offset 5 limit 1), 'f3f3f3f3-0000-0000-0000-000000000003'),
               'B14 staff cannot book for an unlinked patient');

-- assistant (has bookings) sees and manages; then loses bookings permission
select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst), false);
select t.ok(jsonb_array_length(doctor_appointments((select d from day), (select d from day), 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 4,
            'B15 assistant with bookings permission sees the calendar');
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select doctor_update_assistant((select (r->>'assistant_id')::uuid from asst), false, false, false, false);
select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst), false);
select t.fails($$select doctor_appointments(current_date, current_date, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$,
               'B16 assistant without bookings permission is refused');

-- other doctor cannot touch these bookings
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails(format('select set_appointment_status(%L, %L)', (select id from b2), 'cancelled'), 'B17 other doctor cannot change bookings');

-- remove the assistant
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select doctor_remove_assistant((select (r->>'assistant_id')::uuid from asst));
select t.ok(jsonb_array_length(doctor_list_assistants()) = 0, 'D08 doctor removes the assistant');
reset role;
select t.ok(not exists (select 1 from auth.users where id = (select (r->>'assistant_id')::uuid from asst)), 'D09 assistant login is deleted');

\set QUIET off
select count(*) as care_tests_passed from t.results;
