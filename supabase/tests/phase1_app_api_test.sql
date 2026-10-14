-- Tests for 0002_phase1_app_api.sql. Run after phase1_security_test.sql on the same database
-- (reuses its users and the t.ok / t.fails helpers).
\set QUIET on
set client_min_messages = warning;
delete from t.results;

-- Fresh state: reactivate doctor 1, add a patient with a birth date, and a pending + accepted request.
update profiles set is_suspended = false where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into auth.users (id, email, raw_user_meta_data) values
  ('33333333-3333-3333-3333-333333333333', 'patient.c@test.local', '{"full_name":"مريض تجريبي ج"}');
update profiles set birth_date = '1990-01-01', gender = 'female' where id = '33333333-3333-3333-3333-333333333333';

set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select t.ok((get_my_context()->>'role') = 'patient', 'A01 context returns patient role');
create temp table c3 as select request_join('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', null, 'كشف متابعة') as req;
select t.ok((select count(*) from patient_my_requests() where status = 'pending') = 1, 'A02 patient sees own pending request');

select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select t.ok((get_my_context()->>'doctor_status') = 'verified', 'A03 context returns doctor status');
select t.ok((select patient_name from doctor_incoming_requests()) = 'مريض تجريبي ج', 'A04 doctor sees requester name');
select t.ok((select age from doctor_incoming_requests()) >= 36, 'A05 doctor sees requester age');
select t.ok((select count(*) from doctor_my_patients()) = 0, 'A06 no patients before accepting');
select respond_join((select req from c3), true);
select t.ok((select count(*) from doctor_incoming_requests()) = 0, 'A07 accepted request leaves the inbox');
select t.ok((select scope from doctor_my_patients()) = 'full', 'A08 accepted patient appears with scope');
select t.fails($$select admin_list_doctors()$$, 'A09 doctor cannot list doctors as admin');
select t.fails($$select admin_stats()$$, 'A10 doctor cannot read admin stats');

select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
select t.ok((select count(*) from doctor_my_patients()) = 0, 'A11 other doctor sees none of these patients');
select t.ok((select count(*) from doctor_incoming_requests()) = 0, 'A12 other doctor sees no requests');

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select t.ok((select doctor_name from patient_my_doctors()) = 'طبيب تجريبي 1', 'A13 patient sees linked doctor');
select t.ok((select status from patient_my_requests()) = 'accepted', 'A14 request shows accepted');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select t.ok((select count(*) from patient_my_doctors()) = 0, 'A15 another patient sees no linked doctors');

select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select t.ok(jsonb_array_length(admin_list_doctors()) = 2, 'A16 admin lists all doctors');
select t.ok(jsonb_array_length(admin_list_doctors('pending')) = 1, 'A17 admin filters by status');
select t.ok((admin_stats()->>'active_links')::int = 1, 'A18 admin stats count active links');

set role anon;
select set_config('request.jwt.claim.sub', '', false);
select t.fails($$select get_my_context()$$, 'A19 anonymous cannot call app functions');

reset role;
\set QUIET off
select count(*) as app_api_tests_passed from t.results;
