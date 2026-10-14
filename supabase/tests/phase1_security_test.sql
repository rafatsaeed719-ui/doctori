-- Phase 1 security & workflow tests. Run on a throw-away database:
--   psql -v ON_ERROR_STOP=1 -f 00_local_supabase_shim.sql -f ../migrations/0001_phase1_core.sql -f phase1_security_test.sql
-- Every check raises an exception on failure, so the run stops at the first broken rule.
\set QUIET on
set client_min_messages = warning;

create schema t;
create table t.results (n serial, label text, passed boolean);
grant usage on schema t to authenticated, anon;
grant insert, select on t.results to authenticated, anon;
grant usage on sequence t.results_n_seq to authenticated, anon;

create function t.ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', label; end if;
  insert into t.results(label, passed) values (label, true);
end $$;

-- Runs SQL and passes only if it raises an error.
create function t.fails(stmt text, label text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    insert into t.results(label, passed) values (label, true);
    return;
  end;
  raise exception 'FAIL (no error raised): %', label;
end $$;
grant execute on all functions in schema t to authenticated, anon;

-- ---- Fixtures (created as the owner, the way Supabase Auth would) ----
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'patient.a@test.local', '{"full_name":"مريض تجريبي أ","role":"patient"}'),
  ('22222222-2222-2222-2222-222222222222', 'patient.b@test.local', '{"full_name":"مريض تجريبي ب"}'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'doctor.1@test.local',  '{"full_name":"طبيب تجريبي 1","role":"doctor"}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'doctor.2@test.local',  '{"full_name":"طبيب تجريبي 2","role":"doctor"}'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'admin@test.local',     '{"full_name":"مدير تجريبي","role":"admin"}');

select t.ok((select role from profiles where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') = 'patient',
            '01 signing up with role=admin creates a patient, not an admin');
-- The owner promotes the admin manually (documented step).
update profiles set role = 'admin' where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
update doctors set specialty_id = 2, license_number = 'TEST-1' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
update doctors set specialty_id = 2 where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

-- ================= as PATIENT A =================
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select t.fails($$update profiles set role = 'admin' where id = auth.uid()$$,
               '02 patient cannot promote self to admin');
select t.fails($$update profiles set is_suspended = true where id = auth.uid()$$,
               '03 patient cannot change own suspension flag');
update profiles set full_name = 'مريض تجريبي أ (معدل)', gender = 'male' where id = auth.uid();
select t.ok((select full_name from profiles where id = auth.uid()) like '%معدل%', '04 patient can edit own name');
select t.ok((select count(*) from profiles) = 1, '05 patient sees only own profile');
select t.ok((select count(*) from doctors) = 0, '06 patient sees no unverified doctors');

-- ================= as DOCTOR 1 (still pending) =================
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select t.fails($$update doctors set status = 'verified' where id = auth.uid()$$, '07 doctor cannot self-verify');
select t.fails($$update doctors set rating_avg = 5 where id = auth.uid()$$, '08 doctor cannot edit own rating');
insert into doctor_verifications (doctor_id, documents) values (auth.uid(), '["verif/aaaa/license.pdf"]');
select t.fails($$insert into doctor_verifications (doctor_id) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$$,
               '09 doctor cannot submit verification for another doctor');
insert into clinics (id, doctor_id, name, address, governorate_id, lat, lng)
values ('d1000000-0000-0000-0000-000000000001', auth.uid(), 'عيادة تجريبية - مدينة نصر', 'عنوان تجريبي', 1, 30.0561, 31.3301);
insert into clinic_hours (clinic_id, weekday, opens_at, closes_at)
values ('d1000000-0000-0000-0000-000000000001', 0, '17:00', '21:00');
select t.fails($$insert into clinics (doctor_id, name, address) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','x','y')$$,
               '10 doctor cannot create a clinic for another doctor');
select t.fails($$select admin_review_doctor(auth.uid(), 'verified')$$, '11 doctor cannot call admin functions');

-- ================= as DOCTOR 2 (stays pending) =================
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
insert into clinics (id, doctor_id, name, address, governorate_id, lat, lng)
values ('d2000000-0000-0000-0000-000000000002', auth.uid(), 'عيادة تجريبية 2', 'عنوان تجريبي 2', 1, 30.0444, 31.2357);

-- ================= as ADMIN =================
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select t.ok((select count(*) from doctors) = 2, '12 admin sees all doctors');
select admin_review_doctor('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'verified', 'license checked');
select t.ok((select status from doctors where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'verified', '13 admin verifies doctor 1');
select t.ok((select decision from doctor_verifications where doctor_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'verified',
            '14 verification submission marked reviewed');
select t.ok(exists (select 1 from audit_log where action = 'doctor.reviewed'), '15 verification written to audit log');

-- ================= as PATIENT A: search & join =================
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select t.ok((select count(*) from search_doctors()) = 1, '16 search returns only the verified doctor');
select t.ok((select distance_km from search_doctors(p_lat => 30.05, p_lng => 31.33)) between 0 and 2,
            '17 search computes distance to nearest clinic');
select t.ok((select count(*) from search_doctors(p_query => 'قلب')) = 1, '18 search by specialty name');
select t.ok((select count(*) from search_doctors(p_governorate => 2)) = 0, '19 governorate filter excludes');
select t.ok((select count(*) from search_doctors(p_open_weekday => 1::smallint)) = 0, '20 working-day filter excludes');
select t.ok((get_doctor_public('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')->'clinics'->0->'hours'->0->>'opens_at') = '17:00:00',
            '21 doctor public card includes clinic hours');
select t.ok(get_doctor_public('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') is null, '22 unverified doctor card hidden');
select t.ok((select count(*) from clinics) = 1, '23 unverified doctor clinic hidden from patients');
select t.fails($$select request_join('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$$, '24 cannot join an unverified doctor');
select t.fails($$select request_join('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'd2000000-0000-0000-0000-000000000002')$$,
               '25 cannot attach another doctor''s clinic to a request');
create temp table ctx as
  select request_join('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'd1000000-0000-0000-0000-000000000001', 'متابعة ضغط') as req;
select t.fails($$select request_join('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$, '26 duplicate pending request rejected');
select t.fails($$insert into care_links (patient_id, doctor_id) values (auth.uid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
               '27 patient cannot create a care link directly');
select t.fails($$update join_requests set status = 'accepted'$$, '28 patient cannot accept own request');

-- ================= as DOCTOR 1: before accepting =================
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select t.ok((select count(*) from join_requests where status = 'pending') = 1, '29 doctor sees incoming request');
select t.ok((select count(*) from profiles where id = '11111111-1111-1111-1111-111111111111') = 0,
            '30 doctor cannot read patient profile before acceptance');
select t.ok(doctor_access_scope('11111111-1111-1111-1111-111111111111') is null, '31 no medical access before acceptance');

-- ================= as DOCTOR 2: tries to hijack =================
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
select t.ok((select count(*) from join_requests) = 0, '32 other doctor cannot see the request');
select t.fails(format('select respond_join(%L, true)', (select req from ctx)), '33 other doctor cannot accept the request');

-- ================= as DOCTOR 1: accept =================
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
create temp table ctx2 as select respond_join((select req from ctx), true) as link;
select t.ok((select status from care_links where id = (select link from ctx2)) = 'active', '34 acceptance creates active care link');
select t.ok(doctor_access_scope('11111111-1111-1111-1111-111111111111') = 'full', '35 linked doctor gets consented scope');
select t.ok((select full_name from profiles where id = '11111111-1111-1111-1111-111111111111') is not null,
            '36 linked doctor can read patient profile');
select t.fails(format('select respond_join(%L, false)', (select req from ctx)), '37 request cannot be answered twice');

-- ================= as PATIENT B: snooping =================
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select t.ok((select count(*) from profiles where id <> auth.uid()) = 0, '38 another patient cannot read other profiles');
select t.ok((select count(*) from care_links) + (select count(*) from consents) + (select count(*) from join_requests) = 0,
            '39 another patient sees no links, consents or requests');
select t.fails(format('select end_care_link(%L)', (select link from ctx2)), '40 another patient cannot end someone else''s link');
select t.ok((select count(*) from audit_log) = 0, '41 another patient sees nothing in audit log');
select request_join('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select cancel_join_request((select id from join_requests where patient_id = auth.uid()));
select t.ok((select status from join_requests where patient_id = auth.uid()) = 'cancelled', '42 patient can cancel own request');

-- ================= as PATIENT A: consent & unlink =================
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select t.ok((select count(*) from profiles) = 2, '43 patient can read own linked doctor profile');
select set_consent_scope((select link from ctx2), 'own_uploads');
select t.ok((select count(*) from consents where revoked_at is null) = 1 and (select count(*) from consents) = 2,
            '44 changing consent keeps history (one live, one revoked)');
select t.ok(exists (select 1 from audit_log where action = 'consent.changed'), '45 patient sees audit entries about own data');
select end_care_link((select link from ctx2));

-- ================= as DOCTOR 1: after unlink =================
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select t.ok(doctor_access_scope('11111111-1111-1111-1111-111111111111') is null, '46 access gone after unlink');
select t.ok((select count(*) from profiles where id = '11111111-1111-1111-1111-111111111111') = 0,
            '47 doctor cannot read patient profile after unlink');
update doctors set license_number = 'TEST-1-CHANGED' where id = auth.uid();
select t.ok((select status from doctors where id = auth.uid()) = 'pending', '48 changing licence sends doctor back to review');

-- ================= ADMIN: suspension =================
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select admin_review_doctor('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'verified');
select admin_set_suspended('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true, 'test');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select t.ok((select count(*) from search_doctors()) = 0, '49 suspended doctor disappears from search');
select t.fails($$select request_join('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$, '50 cannot join a suspended doctor');

-- ================= anonymous =================
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select t.fails($$select * from profiles$$, '51 anonymous cannot read profiles');
select t.fails($$select search_doctors()$$, '52 anonymous cannot search doctors');
select t.ok((select count(*) from specialties) = 22, '53 anonymous can read specialties list');

-- ================= owner: audit log is append-only =================
reset role;
select t.fails($$delete from audit_log$$, '54 audit log cannot be deleted, even by the owner');
select t.fails($$update audit_log set action = 'x'$$, '55 audit log cannot be edited');

\set QUIET off
select count(*) as tests_passed from t.results;
