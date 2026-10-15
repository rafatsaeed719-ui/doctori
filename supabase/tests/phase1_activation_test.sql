-- Tests for 0008_doctor_activation.sql. Run after phase1_accounts_test.sql on the same database.
\set QUIET on
set client_min_messages = warning;
delete from t.results;

-- A doctor signs up with a mobile number in the metadata
insert into auth.users (id, email, raw_user_meta_data) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'doctor.new@test.local',
   '{"full_name":"د. جديد","role":"doctor","phone":"0100 111 2222"}');
select t.ok((select phone from profiles where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') = '201001112222',
            'C01 sign-up keeps the doctor mobile number (normalized)');
select t.ok((select value #>> '{}' from app_settings where key = 'admin_whatsapp') = '201207760898',
            'C02 admin WhatsApp number setting exists');

set role authenticated;
-- Doctor cannot read codes or issue one
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails($$select * from doctor_activation_codes$$, 'C03 codes table is not readable from the app');
select t.fails($$select admin_issue_doctor_code(auth.uid())$$, 'C04 doctor cannot issue own code');
select t.fails($$select doctor_activate_with_code('123456')$$, 'C05 no code yet → clear error');

-- Admin issues a code
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
create temp table code as select admin_issue_doctor_code('dddddddd-dddd-dddd-dddd-dddddddddddd') as r;
select t.ok(length((select r->>'code' from code)) = 6 and (select r->>'phone' from code) = '201001112222',
            'C06 admin gets a 6-digit code and the doctor phone');

-- Doctor: wrong codes are counted, right code verifies
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.ok((doctor_activate_with_code('000000')->>'ok')::boolean = false, 'C07 wrong code rejected');
reset role;
select t.ok((select attempts from doctor_activation_codes where doctor_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') = 1,
            'C08 wrong attempt is saved');
set role authenticated;
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails($$update doctors set status = 'verified' where id = auth.uid()$$, 'C09 doctor still cannot self-verify directly');
select t.ok((doctor_activate_with_code((select r->>'code' from code))->>'ok')::boolean, 'C10 right code accepted');
select t.ok((select status from doctors where id = auth.uid()) = 'verified', 'C11 doctor is now verified');
select t.fails(format('select doctor_activate_with_code(%L)', (select r->>'code' from code)), 'C12 code cannot be reused');

-- Lockout after 5 wrong attempts
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select admin_issue_doctor_code('dddddddd-dddd-dddd-dddd-dddddddddddd');
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select doctor_activate_with_code('000001'), doctor_activate_with_code('000002'), doctor_activate_with_code('000003'),
       doctor_activate_with_code('000004'), doctor_activate_with_code('000005');
select t.fails($$select doctor_activate_with_code('000006')$$, 'C13 locked after 5 wrong attempts');

reset role;
select t.ok(exists (select 1 from audit_log where action = 'doctor.activated_with_code'), 'C14 activation is audit-logged');
\set QUIET off
select count(*) as activation_tests_passed from t.results;
