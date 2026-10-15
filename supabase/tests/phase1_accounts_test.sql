-- Tests for 0004_accounts_admin.sql. Run after phase1_app_api_test.sql on the same database.
\set QUIET on
set client_min_messages = warning;
delete from t.results;

-- Phone normalization
select t.ok(normalize_eg_phone('01012345678') = '201012345678', 'B01 01... → 2010...');
select t.ok(normalize_eg_phone('+20 101 234 5678') = '201012345678', 'B02 +20 with spaces');
select t.ok(normalize_eg_phone('00201012345678') = '201012345678', 'B03 0020 prefix');
select t.fails($$select normalize_eg_phone('12345')$$, 'B04 invalid phone rejected');

set role authenticated;

-- ===== Doctor 1 (verified) adds a patient =====
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
create temp table np as
  select doctor_create_patient('مريض العيادة', '0101 234 5678', 'clinicpass1', 'male', '1980-05-01') as r;
select t.ok((select r->>'phone' from np) = '201012345678', 'B05 doctor creates patient with phone login');
select t.ok(exists (select 1 from doctor_my_patients() where phone = '201012345678' and created_by_clinic and scope = 'full'),
            'B06 new patient appears linked with full scope, marked clinic-created');
select t.fails($$select doctor_create_patient('تاني', '01012345678', 'clinicpass1')$$, 'B07 same phone twice rejected');
select t.fails($$select doctor_create_patient('قصير', '01112345678', 'short')$$, 'B08 short password rejected');
select t.fails($$select _create_auth_user('x@y.z', 'password123', '{}')$$, 'B09 internal create function not callable from app');
select doctor_reset_patient_password((select (r->>'patient_id')::uuid from np), 'newpass123');

-- ===== Doctor 2 (pending) cannot create patients or reset others =====
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
select t.fails($$select doctor_create_patient('س', '01212345678', 'password123')$$, 'B10 unverified doctor cannot create patients');
select t.fails(format('select doctor_reset_patient_password(%L, %L)', (select r->>'patient_id' from np), 'hijack1234'),
               'B11 other doctor cannot reset the patient password');

-- ===== The created patient can use the app normally =====
select set_config('request.jwt.claim.sub', (select r->>'patient_id' from np), false);
select t.ok((get_my_context()->>'role') = 'patient', 'B12 clinic-created account is a normal patient');
select t.ok((select doctor_name from patient_my_doctors()) = 'طبيب تجريبي 1', 'B13 patient sees the clinic doctor');
select t.fails($$select admin_list_users()$$,
               'B14 patient cannot list users');

-- ===== Admin =====
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
create temp table nd as select admin_create_user('د. مضاف من الإدارة', '01512345678', 'doctorpass1', 'doctor', 3, 'LIC-9', true) as r;
select t.ok((select status from doctors where id = (select (r->>'user_id')::uuid from nd)) = 'verified',
            'B15 admin creates an already-verified doctor');
select t.ok((select count(*) from search_doctors(p_specialty => 3)) = 1, 'B16 admin-created doctor is searchable');
create temp table na as select admin_create_user('مدير تاني', 'admin2@test.local', 'adminpass1', 'admin') as r;
select t.ok((select role from profiles where id = (select (r->>'user_id')::uuid from na)) = 'admin', 'B17 admin creates another admin by email');
select t.ok(jsonb_array_length(admin_list_users('doctor')) = 3, 'B18 admin lists doctors');
select t.ok(jsonb_array_length(admin_list_users(null, '01012345678')) = 1, 'B19 admin finds user by phone');
update profiles set full_name = 'اسم معدل من الإدارة' where id = (select (r->>'patient_id')::uuid from np);
select t.ok((select full_name from profiles where id = (select (r->>'patient_id')::uuid from np)) = 'اسم معدل من الإدارة',
            'B20 admin edits any profile');
insert into clinics (doctor_id, name, address) values ((select (r->>'user_id')::uuid from nd), 'عيادة أضافتها الإدارة', 'عنوان');
select t.ok((select count(*) from clinics where name = 'عيادة أضافتها الإدارة') = 1, 'B21 admin adds a clinic for a doctor');
select admin_set_password((select (r->>'user_id')::uuid from nd), 'resetbyadmin1');
select t.fails($$select admin_delete_user(auth.uid())$$, 'B22 admin cannot delete self');
select admin_delete_user((select (r->>'user_id')::uuid from nd));
select t.ok(not exists (select 1 from profiles where id = (select (r->>'user_id')::uuid from nd)), 'B23 admin deletes a doctor');
select admin_delete_user('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select t.ok(not exists (select 1 from doctors where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
            'B24 deleting a doctor with patients, links and history works');
select t.ok(exists (select 1 from audit_log where action = 'user.deleted_by_admin'), 'B25 deletions are audit-logged');

reset role;
-- Passwords are really hashed and verifiable (what Supabase Auth checks at login)
select t.ok((select encrypted_password = extensions.crypt('newpass123', encrypted_password)
             from auth.users where email = 'p201012345678@phone.doctori.app'), 'B26 reset password verifies with bcrypt');
select t.ok((select email_confirmed_at is not null and confirmation_token = '' from auth.users
             where email = 'p201012345678@phone.doctori.app'), 'B27 created accounts are confirmed, no null tokens');
select t.ok((select count(*) from auth.identities where email = 'p201012345678@phone.doctori.app') = 1,
            'B28 identity row created for login');

\set QUIET off
select count(*) as accounts_tests_passed from t.results;
