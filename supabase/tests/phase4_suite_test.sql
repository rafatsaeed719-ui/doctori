-- Tests for 0017 (queue, inventory, reports, surgeries, chat, health, reviews, notifications). Run after phase3.
\set QUIET on
set client_min_messages = warning;
delete from t.results;
reset role;
select set_config('request.jwt.claim.sub', '', false);
-- A booking for f1 today (fixture, written as the system).
insert into appointments (id, doctor_id, clinic_id, patient_id, starts_at, ends_at, status)
values ('a7a7a7a7-0000-0000-0000-000000000007', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'c1c1c1c1-0000-0000-0000-000000000001',
        'f1f1f1f1-0000-0000-0000-000000000001', now() + interval '2 minutes', now() + interval '22 minutes', 'confirmed');
create temp table asst2 as select jsonb_build_object('assistant_id', id) as r from profiles where role = 'assistant' and full_name = 'سكرتيرة';
grant select on asst2 to authenticated;
set role authenticated;

-- ---------- Queue ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select queue_add('c1c1c1c1-0000-0000-0000-000000000001', null, 'زائر بدون حجز');
select t.ok(jsonb_array_length(queue_today('c1c1c1c1-0000-0000-0000-000000000001')->'appointments') >= 1,
            'Q01 today''s bookings are listed to check in');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select queue_checkin('a7a7a7a7-0000-0000-0000-000000000007');
select t.ok((my_queue()->0->>'number')::int = 2 and (my_queue()->0->>'ahead')::int = 1, 'Q02 patient checks in and sees who is ahead');
select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.ok((select count(*) from clinic_queue) = 0, 'Q03 other patients see nothing');
select t.fails($$select queue_checkin('a7a7a7a7-0000-0000-0000-000000000007')$$, 'Q04 cannot check in someone else''s booking');
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok((queue_call_next('c1c1c1c1-0000-0000-0000-000000000001')->>'number')::int = 1, 'Q05 call next = number 1');
select t.ok((queue_call_next('c1c1c1c1-0000-0000-0000-000000000001')->>'number')::int = 2, 'Q06 then number 2');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok(exists (select 1 from jsonb_array_elements(my_notifications()->'items') n where n->>'kind' = 'queue'),
            'Q07 patient is notified when called');
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails($$select queue_today('c1c1c1c1-0000-0000-0000-000000000001')$$, 'Q08 other doctors cannot see the queue');

-- ---------- Inventory ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table inv as select save_inventory_item(null, 'سرنجات 5 مل', 'مستهلكات', 'علبة', 3, 50, 10) as id;
select t.ok(inventory_move((select id from inv), -8, 'use') = 2, 'I01 using stock lowers the quantity');
select t.ok((list_inventory()->0->>'low')::boolean, 'I02 low stock is flagged');
select t.fails(format('select inventory_move(%L, -5, %L)', (select id from inv), 'use'), 'I03 cannot use more than in stock');
select inventory_move((select id from inv), 20, 'purchase', null, 600, true);
select t.ok((select qty from inventory_items where id = (select id from inv)) = 22
            and exists (select 1 from doctor_expenses where reason like 'شراء سرنجات%' and amount = 600),
            'I04 a purchase adds stock and is recorded as an expense');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.fails($$select list_inventory('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$, 'I05 patients cannot see the stock');
select t.ok((select count(*) from inventory_items) = 0, 'I06 … not even through the table');

-- ---------- Reports ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok((doctor_reports(current_date - 30, current_date + 30)->'appointments'->>'total')::int >= 1
            and (doctor_reports(current_date - 30, current_date + 30)->'finance'->>'income') is not null, 'R01 doctor reports');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.fails($$select doctor_reports(current_date - 30, current_date, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$, 'R02 patients cannot');

-- ---------- Surgeries ----------
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
create temp table sg as select save_surgery(null, 'f1f1f1f1-0000-0000-0000-000000000001', 'منظار ركبة', now() + interval '10 days',
  'مستشفى السلام', 'planned', '[{"text":"صيام 8 ساعات","done":false}]'::jsonb) as id;
select t.fails($$select save_surgery(null, 'f3f3f3f3-0000-0000-0000-000000000003', 'x y')$$, 'S01 only for linked patients');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok((list_surgeries()->0->'prep'->0->>'text') = 'صيام 8 ساعات', 'S02 patient sees the surgery and its preparation');
select set_config('request.jwt.claim.sub', 'f3f3f3f3-0000-0000-0000-000000000003', false);
select t.ok(jsonb_array_length(list_surgeries('f1f1f1f1-0000-0000-0000-000000000001')) = 0, 'S03 others see nothing');

-- ---------- Chat ----------
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select send_message('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'ممكن أغير ميعادي؟');
select t.fails($$select send_message('dddddddd-dddd-dddd-dddd-dddddddddddd', 'hi')$$, 'C01 cannot message an unrelated doctor');
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok((chat_threads('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')->0->>'unread')::int = 1, 'C02 clinic sees the unread message');
select send_message('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'أكيد، بكرة الساعة 5', 'f1f1f1f1-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', (select r->>'assistant_id' from asst2), false);
select t.ok(jsonb_array_length(chat_messages('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'f1f1f1f1-0000-0000-0000-000000000001')) = 2,
            'C03 receptionist sees the conversation');
select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select t.ok((select count(*) from messages) = 0, 'C04 other patients see nothing');
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok((chat_threads()->0->>'last') = 'أكيد، بكرة الساعة 5', 'C05 patient sees the reply');

-- ---------- Health profile ----------
select save_health(null, '{"blood_type":"O+","allergies":["بنسلين"],"chronic":["سكر"],"smoker":false}'::jsonb);
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select t.ok((get_health('f1f1f1f1-0000-0000-0000-000000000001')->'allergies'->>0) = 'بنسلين', 'H01 linked doctor sees allergies');
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
select t.fails($$select get_health('f1f1f1f1-0000-0000-0000-000000000001')$$, 'H02 other doctors cannot');

-- ---------- Reviews ----------
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select submit_review('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 5, 'دكتور ممتاز');
select t.fails($$select submit_review('dddddddd-dddd-dddd-dddd-dddddddddddd', 1)$$, 'V01 only the doctor''s patients review');
select set_config('request.jwt.claim.sub', 'f2f2f2f2-0000-0000-0000-000000000002', false);
select submit_review('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 3);
select t.ok((doctor_reviews_list('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')->>'avg')::numeric = 4, 'V02 average rating updates');
select t.fails($$select submit_review('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 9)$$, 'V03 stars are 1 to 5');
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
select admin_hide_review((select id from doctor_reviews where stars = 3), true);
select t.ok((select rating_avg from doctors where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') = 5, 'V04 hidden reviews leave the average');

-- ---------- Notifications ----------
select set_config('request.jwt.claim.sub', 'f1f1f1f1-0000-0000-0000-000000000001', false);
select t.ok((my_notifications()->>'unread')::int >= 3
            and exists (select 1 from jsonb_array_elements(my_notifications()->'items') n where n->>'kind' = 'chat')
            and exists (select 1 from jsonb_array_elements(my_notifications()->'items') n where n->>'kind' = 'surgery'),
            'N01 patient gets notifications (chat, surgery, queue…)');
select mark_notifications_read();
select t.ok((my_notifications()->>'unread')::int = 0, 'N02 mark all read');
select t.ok((select count(*) from notifications where user_id <> auth.uid()) = 0, 'N03 nobody reads others'' notifications');
select t.fails($$insert into notifications (user_id, kind, title) values (auth.uid(), 'x', 'x')$$, 'N04 no direct writes');

reset role;
\set QUIET off
select count(*) as suite_tests_passed from t.results;
