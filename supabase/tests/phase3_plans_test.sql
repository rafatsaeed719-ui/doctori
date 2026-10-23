-- Tests for 0011 (medicine review, case plans, follow-ups). Run after phase2_care_test.sql.
-- Fixtures from phase2: doctor eeee (verified) linked to f1 (full) and f2 (own_uploads); f3 unlinked; doctor dddd verified, unlinked.
\set QUIET on
set client_min_messages = warning;
delete from t.results;
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role authenticated;

-- ---------- Medicine photo → doctor sets the dose ----------
select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
insert into medications (patient_id, name, form, photo_path, needs_review, review_doctor, is_active)
values (auth.uid(), 'علبة دوا من الصيدلية', 'syrup', 'f2f2f2f2-0000-0000-0000-000000000002/1_med.jpg', true,
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.fails($$insert into medications (patient_id, name, needs_review, review_doctor)
                 values (auth.uid(), 'x', true, 'dddddddd-dddd-dddd-dddd-dddddddddddd')$$,
               'R01 cannot send a medicine to a doctor you are not linked to');
select t.fails($$insert into medications (patient_id, name, form) values (auth.uid(), 'x', 'pill-ish')$$, 'R02 unknown medicine type rejected');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok(jsonb_array_length(doctor_pending_med_reviews()) = 1, 'R03 doctor sees the medicine waiting for review');
select t.ok(exists (select 1 from jsonb_array_elements(list_medications('f2f2f2f2-0000-0000-0000-000000000002')) m
                    where (m->>'needs_review')::boolean), 'R04 own-uploads patient: doctor sees the medicine sent to them');
select t.ok(can_view_medical_object('f2f2f2f2-0000-0000-0000-000000000002/1_med.jpg'), 'R05 doctor may open the medicine photo');
select review_medication((select (m->>'id')::uuid from jsonb_array_elements(doctor_pending_med_reviews()) m limit 1),
                         'شراب كحة', '5 مل', 8, '09:00', null, null, 'بعد الأكل');
select t.ok(jsonb_array_length(doctor_pending_med_reviews()) = 0, 'R06 review clears the queue');

select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.ok((select is_active and not needs_review and prescribed_by = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' and dose = '5 مل'
             from medications where name = 'شراب كحة'), 'R07 reviewed medicine is active with the doctor dose');
update medications set dose = '50 مل' where name = 'شراب كحة';
select t.ok((select dose from medications where name = 'شراب كحة') = '5 مل', 'R08 patient cannot change the reviewed dose');

select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.ok(not can_view_medical_object('f2f2f2f2-0000-0000-0000-000000000002/1_med.jpg'), 'R09 other doctor cannot open the photo');
select t.fails($$select review_medication((select id from medications limit 1), 'x', null, 8, '09:00')$$, 'R10 other doctor cannot review');

-- ---------- Case plans ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table plan as select save_case_plan(null, 'f1f1f1f1-0000-0000-0000-000000000001',
  '{"problems":["آلام ظهر"],"regions":["lower_back"],"goal":"lose_weight","measures":{"weight":96,"height":175}}'::jsonb,
  'physio', 8, 16, null, 'active') as id;
select t.ok((select id from plan) is not null, 'P01 doctor saves a specialty plan');
select t.fails($$select save_case_plan(null, 'f3f3f3f3-0000-0000-0000-000000000003', '{}'::jsonb)$$, 'P02 no plan for an unlinked patient');
select save_case_plan((select id from plan), 'f1f1f1f1-0000-0000-0000-000000000001',
  '{"problems":["آلام ظهر"],"regions":["lower_back"],"goal":"lose_weight","measures":{"weight":93,"height":175}}'::jsonb,
  'physio', 8, 16, null, 'active');
select t.ok(add_plan_session((select id from plan)) = 1, 'P03 session counter goes up');
select t.ok(jsonb_array_length(list_case_plans('f1f1f1f1-0000-0000-0000-000000000001')->0->'history') = 3,
            'P04 every change is kept in history (weight progress)');
select t.fails($$update case_plans set sessions_done = 99$$ , 'P05 plans change only through functions');

select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok((list_case_plans()->0->'data'->'measures'->>'weight')::int = 93, 'P06 patient sees their plan');
select t.fails(format('select add_plan_session(%L)', (select id from plan)), 'P07 patient cannot log sessions');

select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
select t.ok(jsonb_array_length(list_case_plans('f1f1f1f1-0000-0000-0000-000000000001')) = 0
            and (select count(*) from case_plans) = 0, 'P08 another patient sees nothing');

select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails(format('select save_case_plan(%L, %L, %L::jsonb)', (select id from plan), 'f1f1f1f1-0000-0000-0000-000000000001', '{}'),
               'P09 other doctor cannot edit the plan');

-- ---------- Follow-ups ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table fu as select schedule_followup('f1f1f1f1-0000-0000-0000-000000000001', now() + interval '3 days',
  'جلسة علاج طبيعي', 'هات الأشعة معاك', (select id from plan)) as r;
select t.ok((select r->>'patient_name' from fu) = 'مريض كامل', 'F01 doctor schedules a dated follow-up');
select t.fails($$select schedule_followup('f3f3f3f3-0000-0000-0000-000000000003', now() + interval '1 day', 'x')$$,
               'F02 cannot schedule for an unlinked patient');
select t.fails($$select schedule_followup('f1f1f1f1-0000-0000-0000-000000000001', now() - interval '2 days', 'x')$$,
               'F03 past date rejected');
select t.ok(jsonb_array_length(doctor_followups(current_date, current_date + 7)) = 1, 'F04 doctor sees follow-ups in the calendar range');

select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok((patient_followups()->0->>'title') = 'جلسة علاج طبيعي', 'F05 patient sees the follow-up');
select t.fails(format('select set_followup_status(%L, %L)', (select r->>'id' from fu), 'cancelled'), 'F06 patient cannot change it');

select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.ok(jsonb_array_length(patient_followups('f1f1f1f1-0000-0000-0000-000000000001')) = 0
            and (select count(*) from followups) = 0, 'F07 another patient sees nothing');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select set_followup_status((select (r->>'id')::uuid from fu), 'done');
select t.ok((select status from followups where id = (select (r->>'id')::uuid from fu)) = 'done', 'F08 doctor marks it done');

-- ---------- رصيدي اليومي ----------
create temp table today as select (now() at time zone 'Africa/Cairo')::date as d;
select save_income(null, 'visit', 300, (select d from today), 'f1f1f1f1-0000-0000-0000-000000000001');
select save_income(null, 'xray', 450, (select d from today), 'f1f1f1f1-0000-0000-0000-000000000001', null, 'أشعة ركبة');
select save_income(null, 'revisit', 150, (select d from today), null, 'حالة بدون حساب');
select save_income(null, 'lab', 200, (select d from today) - 1, null, 'تحليل امبارح');
select save_expense(null, 'supplies', 120, (select d from today), 'قطن وشاش');
select t.ok((finance_day()->>'income')::numeric = 900 and (finance_day()->>'expenses')::numeric = 120
            and (finance_day()->>'net')::numeric = 780, 'M01 day totals: income − expenses = net');
select t.ok((finance_day()->>'cases')::int = 2, 'M02 cases counted once per patient');
select t.ok((finance_day((select d from today) - 1)->>'income')::numeric = 200, 'M03 search any day');
select t.ok((finance_month(extract(year from (select d from today))::int, extract(month from (select d from today))::int)->>'net')::numeric
            = case when extract(month from (select d from today)) = extract(month from (select d from today) - 1) then 980 else 780 end,
            'M04 month net');
select t.ok((finance_year(extract(year from (select d from today))::int)->>'income')::numeric
            >= 900, 'M05 year totals');
select t.fails($$select save_income(null, 'visit', 100, null, '99999999-0000-0000-0000-000000000009')$$,
               'M06 cannot tie income to a stranger patient');
select t.fails($$select save_income(null, 'visit', -5)$$, 'M07 negative amount rejected');
select t.fails($$insert into doctor_income (doctor_id, kind, amount, paid_on) values (auth.uid(), 'visit', 1, current_date)$$,
               'M08 no direct writes');

create temp table asst2 as select doctor_create_assistant('سكرتيرة', '01077776666', 'assistpass2', true, false, false, false) as r;
select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst2), false);
select t.fails($$select finance_day(null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$, 'M09 assistant without permission sees no money');
select t.ok((select count(*) from doctor_income) = 0, 'M10 … not even through the table');
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select set_assistant_finance((select (r->>'assistant_id')::uuid from asst2), true);
select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst2), false);
select save_income(null, 'visit', 300, null, null, 'حالة الاستقبال', null, null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
select t.ok((finance_day(null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')->>'income')::numeric = 1200, 'M11 receptionist with permission records income');
select t.ok((get_my_context()->'assistant_of'->>'can_finance')::boolean, 'M12 permission shows in context');
select t.fails($$select set_price_list('{"visit":300}'::jsonb, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$, 'M13 only the doctor sets prices');

select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails($$select finance_day(null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$, 'M14 another doctor sees nothing');
select t.ok((select count(*) from doctor_expenses) = 0, 'M15 … not even through the table');
select t.fails(format('select delete_finance_entry(%L, %L)', 'expense', (select id from doctor_expenses limit 1)), 'M16 cannot delete others');

select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok((select count(*) from doctor_income) = 0, 'M17 patients never see the doctor ledger');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select set_price_list('{"visit":300,"revisit":150}'::jsonb);
select t.ok((finance_day()->'prices'->>'visit')::int = 300, 'M18 doctor saves the price list');
select delete_finance_entry('expense', (select id from doctor_expenses limit 1));
select t.ok((finance_day()->>'expenses')::numeric = 0, 'M19 doctor deletes an expense');

-- ---------- الروشتة ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table rx1 as select create_prescription('f1f1f1f1-0000-0000-0000-000000000001', null,
  '[{"name":"أوجمنتين 1جم","form":"tablet","dose":"قرص","every_hours":12,"days":7,"instructions":"بعد الأكل"},
    {"name":"مرهم","form":"cream","dose":"دهان","instructions":"مرتين"}]'::jsonb, 'التهاب لوز') as id;
select t.ok((select patient_name from prescriptions where id = (select id from rx1)) = 'مريض كامل', 'X01 doctor writes a prescription for a linked patient');
select t.ok((select count(*) from medications where name = 'أوجمنتين 1جم' and end_date is not null and form = 'tablet') = 1,
            'X02 timed medicines also go to «علاجي» with reminders');
select t.ok((select count(*) from medications where name = 'مرهم') = 0, 'X03 items without a schedule stay on paper only');
select create_prescription(null, 'زائر بدون حساب', '[{"name":"باراسيتامول"}]'::jsonb);
select t.ok((select count(*) from prescriptions where patient_id is null) = 1, 'X04 walk-in prescription by name (print only)');
select t.fails($$select create_prescription('f3f3f3f3-0000-0000-0000-000000000003', null, '[{"name":"x"}]'::jsonb)$$, 'X05 not for unlinked patients');
select t.fails($$select create_prescription(null, 'x y', '[]'::jsonb)$$, 'X06 needs at least one medicine');
select set_rx_settings('{"logo_url":"https://x/logo.png","whatsapp":"01000000000"}'::jsonb);
select t.ok((rx_header()->'settings'->>'whatsapp') = '01000000000' and rx_header()->>'doctor_name' is not null, 'X07 header with settings');
select t.ok(jsonb_array_length(list_prescriptions(null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 2, 'X08 doctor sees own prescriptions');

select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok(jsonb_array_length(list_prescriptions()) = 1, 'X09 patient sees their prescription');
select t.ok((rx_header('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')->'settings'->>'logo_url') is not null, 'X10 patient can draw the header');

select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.ok(jsonb_array_length(list_prescriptions(null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 0
            and (select count(*) from prescriptions) = 0, 'X11 other patients see nothing');
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.ok((select count(*) from prescriptions) = 0, 'X12 other doctors see nothing');

-- ---------- عروض الأطباء + إعلانات الإدارة ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table of1 as select save_offer(null, 'عملية الغضروف بالمنظار', 'operation', 'خصم لأول 10 حالات', 15000, 20000) as id;
select save_offer(null, 'كشف مخفض', 'visit_price', null, 150, 300, null, current_date - 1);
select t.ok((select id from of1) is not null, 'O01 verified doctor posts an offer');
select t.fails($$insert into doctor_offers (doctor_id, title) values (auth.uid(), 'direct')$$, 'O02 no direct writes');

select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
select t.ok(jsonb_array_length(list_offers(null, null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 1,
            'O03 every patient sees active offers (expired one hidden)');
select offer_event((select id from of1), 'view');
select offer_event((select id from of1), 'booking');
select t.fails($$select save_offer(null, 'patient offer')$$, 'O04 patients cannot post offers');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok((select (o->>'views')::int = 1 and (o->>'bookings')::int = 1
             from jsonb_array_elements(list_offers(null, null, null, true)) o where o->>'id' = (select id::text from of1)),
            'O05 doctor sees views and bookings of their offer');
select t.ok(jsonb_array_length(list_offers(null, null, null, true)) = 2, 'O06 doctor sees own offers incl. expired');

select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails(format('select delete_offer(%L)', (select id from of1)), 'O07 other doctors cannot delete it');

select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select admin_hide_offer((select id from of1), true);
create temp table an1 as select admin_save_announcement(null, 'تحديث جديد للأطباء', 'جربوا الروشتة', 'doctors') as id;
select admin_save_announcement(null, 'نصيحة لكل المرضى', null, 'patients');
select t.ok(jsonb_array_length(admin_list_announcements()) = 2, 'A01 admin posts announcements');

select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
select t.ok(jsonb_array_length(list_offers(null, null, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) = 0, 'O08 hidden offer disappears for patients');
select t.ok(jsonb_array_length(my_announcements()) = 1 and my_announcements()->0->>'title' = 'نصيحة لكل المرضى',
            'A02 patients see only patient announcements');
select dismiss_announcement((my_announcements()->0->>'id')::uuid);
select t.ok(jsonb_array_length(my_announcements()) = 0, 'A03 closed announcement stays closed');
select t.fails($$select admin_save_announcement(null, 'hack')$$, 'A04 only the admin posts announcements');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok(my_announcements()->0->>'title' = 'تحديث جديد للأطباء', 'A05 doctors see doctor announcements');

reset role;
insert into auth.users (id, email, encrypted_password) values ('abababab-0000-0000-0000-00000000000a', 'newdoc@test.com', 'x');
select t.ok((select email_confirmed_at is not null from auth.users where email = 'newdoc@test.com'), 'E01 email sign-ups are confirmed automatically');
\set QUIET off
select count(*) as plan_tests_passed from t.results;
