-- Tests for 0018 (multi-doctor medical centers). Run after phase4.
\set QUIET on
set client_min_messages = warning;
delete from t.results;
reset role;
select set_config('request.jwt.claim.sub', '', false);
create temp table dd_login as select email from profiles where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
grant select on dd_login to authenticated;
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
set role authenticated;

-- ---------- Owner opens a center ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
insert into ids select 'center', create_center('مركز الشفاء الطبي', '01011112222', 'شارع النصر');
select t.ok((select count(*) from center_members where center_id = (select v from ids where k = 'center')) = 2,
            'C01 verified doctor opens a center (owner + works in it)');
select t.ok(exists (select 1 from clinics where center_id = (select v from ids where k = 'center')
                    and doctor_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'), 'C02 the owner gets a clinic at the center');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.fails($$select create_center('fake center')$$, 'C03 patients cannot open centers');

-- ---------- Invite a second doctor ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select center_invite_doctor((select v from ids where k = 'center'), (select email from dd_login), 40);
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.ok((my_centers()->0->>'status') = 'invited', 'C04 doctor sees the invitation');
select center_respond_invite((select v from ids where k = 'center'), true);
select t.ok(exists (select 1 from clinics where center_id = (select v from ids where k = 'center')
                    and doctor_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'), 'C05 accepted doctor gets a center clinic');
select t.fails(format('select center_set_share(%L, %L, 90)', (select v from ids where k = 'center'), 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
               'C06 a doctor cannot change their own share');

select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select center_set_share((select v from ids where k = 'center'), 'dddddddd-dddd-dddd-dddd-dddddddddddd', 40, '{"xray":20}'::jsonb);
insert into ids select 'recep', (center_add_staff((select v from ids where k = 'center'), 'استقبال المركز', '01055554444', 'recep12345')->>'user_id')::uuid;

-- ---------- Reception runs all doctors ----------
select set_config('request.jwt.claim.sub', (select v::text from ids where k = 'recep'), false);
select t.ok(jsonb_array_length(get_my_context()->'centers') = 1, 'C07 reception context lists the center');
select t.ok(jsonb_array_length(center_doctors((select v from ids where k = 'center'))) = 2, 'C08 reception sees both doctors');
select t.ok(acts_for('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bookings')
            and not acts_for('dddddddd-dddd-dddd-dddd-dddddddddddd', 'medical')
            and not acts_for('dddddddd-dddd-dddd-dddd-dddddddddddd', 'finance'),
            'C09 reception handles bookings but never medical files or private ledgers');
select center_save_income((select v from ids where k = 'center'), 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'visit', 300, null, null, 'مريض 1');
select center_save_income((select v from ids where k = 'center'), 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'xray', 500, null, null, 'مريض 2');
select center_save_income((select v from ids where k = 'center'), 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'visit', 400, null, null, 'مريض 3');
select t.ok((center_finance((select v from ids where k = 'center'), current_date, current_date)->>'income')::numeric = 1200
            and center_finance((select v from ids where k = 'center'), current_date, current_date)->>'doctor_shares' is null,
            'C10 reception records income; no access to shares without finance rights');
select t.fails(format('select center_save_expense(%L, %L, 100)', (select v from ids where k = 'center'), 'rent'),
               'C11 reception without finance rights cannot add expenses');

-- ---------- Owner sees the money per doctor and the center net ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select center_save_expense((select v from ids where k = 'center'), 'rent', 100, null, 'إيجار');
create temp table fin as select center_finance((select v from ids where k = 'center'), current_date, current_date) as j;
-- dddd: 300×40% + 500×20% = 220 ; eeee: 400×100% = 400 → doctor shares 620, center share 580, net 480
select t.ok((select (j->>'doctor_shares')::numeric from fin) = 620, 'C12 doctor shares use percent and per-service rates');
select t.ok((select (j->>'center_share')::numeric from fin) = 580 and (select (j->>'net')::numeric from fin) = 480,
            'C13 center share minus center expenses = net');
select t.ok((select (d->>'doctor_share')::numeric from fin, jsonb_array_elements(j->'doctors') d
             where d->>'doctor_id' = 'dddddddd-dddd-dddd-dddd-dddddddddddd') = 220, 'C14 per-doctor report');

select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.ok((doctor_center_earnings(current_date, current_date)->0->>'my_share')::numeric = 220, 'C15 doctor sees their earnings');
select t.fails(format('select center_finance(%L, current_date, current_date)', (select v from ids where k = 'center')),
               'C16 a doctor of the center cannot see the center books');

select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.fails(format('select center_doctors(%L)', (select v from ids where k = 'center')), 'C17 outsiders see nothing');
select t.ok((select count(*) from center_expenses) = 0, 'C18 … not even through the table');

-- ---------- Leaving ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select center_remove_doctor((select v from ids where k = 'center'), 'dddddddd-dddd-dddd-dddd-dddddddddddd');
select set_config('request.jwt.claim.sub', (select v::text from ids where k = 'recep'), false);
select t.fails(format('select center_save_income(%L, %L, %L, 100)', (select v from ids where k = 'center'),
                      'dddddddd-dddd-dddd-dddd-dddddddddddd', 'visit'), 'C19 removed doctor takes no new income');
select t.ok(not acts_for('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bookings'), 'C20 reception loses access to a removed doctor');

-- ---------- Admin: center with a non-doctor owner ----------
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select t.ok((admin_create_center('مجمع عيادات النور', 'مدير المجمع', '01066667777', 'manager123')->>'center_id') is not null,
            'C21 admin opens a center with a manager login');

reset role;
\set QUIET off
select count(*) as center_tests_passed from t.results;
