"""Builds the copy-paste setup scripts for the Supabase SQL editor from the migrations.

Output: setup/part1.sql (core tables) and setup/part2.sql (functions, storage, accounts, admin).
Every statement is made re-runnable, so a script that stopped half-way can simply be run again:
  - create type        -> wrapped, duplicate ignored
  - create table       -> create table if not exists
  - create index       -> named + if not exists
  - create policy      -> drop policy if exists first
  - create trigger     -> drop trigger if exists first
  - seed inserts       -> skipped when rows already exist
Run from the supabase/ folder:  python3 setup/build_setup.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
M = ROOT / "migrations"


def idempotent(sql: str) -> str:
    # create type public.x as enum (...);  -> ignore if it already exists
    sql = re.sub(
        r"^create type (public\.\w+)\s+as enum \(([^;]*?)\);",
        lambda m: f"do $t$ begin create type {m.group(1)} as enum ({m.group(2)}); "
                  f"exception when duplicate_object then null; end $t$;",
        sql, flags=re.M)
    sql = re.sub(r"^create table (public\.\w+)", r"create table if not exists \1", sql, flags=re.M)
    sql = re.sub(r"^create unique index (\w+)", r"create unique index if not exists \1", sql, flags=re.M)

    # unnamed indexes: create index on public.t (cols);
    def name_index(m):
        table, cols = m.group(1), m.group(2)
        name = "idx_" + table.split(".")[1] + "_" + re.sub(r"\W+", "_", cols).strip("_")
        return f"create index if not exists {name} on {table} ({cols});"
    sql = re.sub(r"^create index on (public\.\w+) \(([^)]*)\);", name_index, sql, flags=re.M)

    # create policy name on table ...  -> drop policy if exists name on table; create policy ...
    def drop_policy(m):
        name, table = m.group(1), m.group(2)
        return f"drop policy if exists {name} on {table};\n{m.group(0)}"
    sql = re.sub(r'^create policy ("[^"]+"|\w+)\s+on (\w+\.\w+)', drop_policy, sql, flags=re.M)

    # create trigger name before/after ... on table
    def drop_trigger(m):
        return f"drop trigger if exists {m.group(1)} on {m.group(2)};\n{m.group(0)}"
    sql = re.sub(r"^create trigger (\w+)[^;]*?\bon (\w+\.\w+)", drop_trigger, sql, flags=re.M | re.S)

    # seeds
    sql = sql.replace(
        "insert into public.app_settings (key, value) values",
        "insert into public.app_settings (key, value) values", 1)
    sql = re.sub(r"(insert into public\.app_settings \(key, value\) values[^;]*);",
                 r"\1\non conflict (key) do nothing;", sql, flags=re.S)
    sql = re.sub(r"insert into public\.specialties \(name_ar, name_en, sort_order\) values([^;]*);",
                 r"insert into public.specialties (name_ar, name_en, sort_order)\n"
                 r"select * from (values\1) v(name_ar, name_en, sort_order)\n"
                 r"where not exists (select 1 from public.specialties);", sql, flags=re.S)
    sql = re.sub(r"(insert into public\.governorates \(name_ar, name_en\) values[^;]*);",
                 r"\1\non conflict do nothing;", sql, flags=re.S)
    return sql


PRELUDE = """-- =====================================================================
-- دكتوري — الجزء 1 من 2: الجداول الأساسية والصلاحيات
-- آمن للتشغيل أكتر من مرة: بيكمّل الناقص بس.
-- =====================================================================
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int);

"""

PART2_HEAD = """-- =====================================================================
-- دكتوري — الجزء 2 من 2: دوال التطبيق، التخزين، الحسابات، الإدارة
-- شغّل الجزء 1 الأول. آمن للتشغيل أكتر من مرة.
-- =====================================================================
drop function if exists public.doctor_my_patients();
drop function if exists public.doctor_incoming_requests();
drop function if exists public.patient_my_doctors();
drop function if exists public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int);

"""

BACKFILL = """

-- =====================================================================
-- حسابات اتسجلت قبل ما الجداول تتعمل: نعملها ملفات
-- =====================================================================
insert into public.profiles (id, role, full_name, email, locale)
select u.id,
       case when u.raw_user_meta_data->>'role' = 'doctor' then 'doctor'::public.user_role else 'patient'::public.user_role end,
       coalesce(nullif(trim(u.raw_user_meta_data->>'full_name'), ''), 'مستخدم'), u.email, 'ar'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);
insert into public.patients (id)
select p.id from public.profiles p where p.role = 'patient'
  and not exists (select 1 from public.patients x where x.id = p.id);
insert into public.doctors (id)
select p.id from public.profiles p where p.role = 'doctor'
  and not exists (select 1 from public.doctors x where x.id = p.id);

-- =====================================================================
-- تأكيد حساب المدير وجعله مديراً
-- =====================================================================
update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now())
 where lower(email) = 'rafatsaeed719@gmail.com';
update public.profiles set role = 'admin', is_suspended = false
 where lower(email) = 'rafatsaeed719@gmail.com';

-- تحديث ذاكرة السيرفر عشان التطبيق يشوف الدوال الجديدة فوراً
notify pgrst, 'reload schema';

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_my_context') as "دالة التطبيق",
  (select role::text from public.profiles where lower(email) = 'rafatsaeed719@gmail.com') as "الصلاحية";
"""

PART1_TAIL = """

notify pgrst, 'reload schema';
select 'الجزء 1 تم ✓' as "النتيجة", (select count(*) from public.specialties) as "التخصصات";
"""


def build():
    p1 = PRELUDE + idempotent((M / "0001_phase1_core.sql").read_text(encoding="utf-8")) + PART1_TAIL
    p2 = PART2_HEAD + "\n".join(
        idempotent((M / n).read_text(encoding="utf-8"))
        for n in ("0002_phase1_app_api.sql", "0003_phase1_storage.sql", "0004_accounts_admin.sql",
                  "0005_avatars.sql", "0006_avatars_in_lists.sql")
    ) + BACKFILL
    out = ROOT / "setup"
    (out / "part1.sql").write_text(p1, encoding="utf-8")
    (out / "part2.sql").write_text(p2, encoding="utf-8")
    return p1, p2


if __name__ == "__main__":
    a, b = build()
    print(len(a), len(b))
