-- =====================================================================
-- دكتوري — 0015: عروض الأطباء + إعلانات الإدارة
-- * doctor_offers: a verified doctor announces something at their clinic (an operation, the visit price,
--   a service, a discount). Shown to every user of the app; patients book with the offer in one tap.
--   The admin can hide any offer.
-- * announcements: the platform owner posts to doctors, patients or everyone; shown at the top of the
--   home screen until the user closes it or it ends.
-- * Public "offers" bucket for their pictures (each user uploads only in their own folder).
-- =====================================================================

create table public.doctor_offers (
  id           uuid primary key default gen_random_uuid(),
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  clinic_id    uuid references public.clinics(id) on delete set null,
  kind         text not null default 'service'
               check (kind in ('operation', 'visit_price', 'service', 'discount', 'package', 'other')),
  title        text not null check (length(trim(title)) between 3 and 120),
  body         text check (body is null or length(body) <= 1500),
  price        numeric(12,2) check (price is null or (price >= 0 and price < 10000000)),
  old_price    numeric(12,2) check (old_price is null or (old_price >= 0 and old_price < 10000000)),
  image_url    text check (image_url is null or length(image_url) <= 500),
  valid_until  date,
  is_active    boolean not null default true,
  hidden_by_admin boolean not null default false,
  views        int not null default 0,
  bookings     int not null default 0,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_doctor_offers_doctor on public.doctor_offers (doctor_id, created_at);
alter table public.doctor_offers enable row level security;
create policy offers_read on public.doctor_offers for select using (
  public.acts_for(doctor_id, 'any') or public.is_admin()
  or (is_active and not hidden_by_admin
      and (valid_until is null or valid_until >= (now() at time zone 'Africa/Cairo')::date)
      and exists (select 1 from public.doctors d where d.id = doctor_id and d.status = 'verified')));
revoke all on public.doctor_offers from anon;
grant select on public.doctor_offers to authenticated;
drop trigger if exists doctor_offers_touch on public.doctor_offers;
create trigger doctor_offers_touch before update on public.doctor_offers for each row execute function public.touch_updated_at();

create table public.announcements (
  id         uuid primary key default gen_random_uuid(),
  audience   text not null default 'all' check (audience in ('all', 'doctors', 'patients')),
  title      text not null check (length(trim(title)) between 2 and 120),
  body       text check (body is null or length(body) <= 2000),
  image_url  text check (image_url is null or length(image_url) <= 500),
  link_url   text check (link_url is null or (length(link_url) <= 500 and link_url ~* '^https?://')),
  ends_on    date,
  is_active  boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.announcements enable row level security;
create policy announcements_admin_read on public.announcements for select using (public.is_admin());
revoke all on public.announcements from anon;
grant select on public.announcements to authenticated;

create table public.announcement_dismissals (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  dismissed_at    timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
alter table public.announcement_dismissals enable row level security;
revoke all on public.announcement_dismissals from anon, authenticated;

-- ---------------------------------------------------------------------
-- Offers
-- ---------------------------------------------------------------------
create or replace function public.save_offer(
  p_id uuid, p_title text, p_kind text default 'service', p_body text default null,
  p_price numeric default null, p_old_price numeric default null, p_image_url text default null,
  p_valid_until date default null, p_clinic uuid default null, p_active boolean default true,
  p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not (auth.uid() = v_doc or acts_for(v_doc, 'bookings'))
     or not exists (select 1 from doctors d join profiles p on p.id = d.id
                    where d.id = v_doc and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if p_clinic is not null and not exists (select 1 from clinics where id = p_clinic and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    if (select count(*) from doctor_offers where doctor_id = v_doc and created_at > now() - interval '1 day') >= 5 then
      raise exception 'daily offer limit reached' using errcode = 'P0001';
    end if;
    insert into doctor_offers (doctor_id, clinic_id, kind, title, body, price, old_price, image_url, valid_until, is_active, created_by)
    values (v_doc, p_clinic, coalesce(p_kind, 'service'), trim(p_title), nullif(trim(p_body), ''), p_price, p_old_price,
            nullif(trim(p_image_url), ''), p_valid_until, coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    update doctor_offers set clinic_id = p_clinic, kind = coalesce(p_kind, kind), title = trim(p_title),
           body = nullif(trim(p_body), ''), price = p_price, old_price = p_old_price,
           image_url = nullif(trim(p_image_url), ''), valid_until = p_valid_until, is_active = coalesce(p_active, is_active)
     where id = p_id and doctor_id = v_doc
    returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  perform write_audit('offer.saved', 'doctor_offers', v_id::text, jsonb_build_object('doctor_id', v_doc));
  return v_id;
end $$;

create or replace function public.delete_offer(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid;
begin
  select doctor_id into v_doc from doctor_offers where id = p_id;
  if v_doc is null or not (auth.uid() = v_doc or acts_for(v_doc, 'bookings') or is_admin()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from doctor_offers where id = p_id;
  perform write_audit('offer.deleted', 'doctor_offers', p_id::text, jsonb_build_object('doctor_id', v_doc));
end $$;

create or replace function public.admin_hide_offer(p_id uuid, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update doctor_offers set hidden_by_admin = coalesce(p_hidden, true) where id = p_id;
  perform write_audit('offer.hidden', 'doctor_offers', p_id::text, jsonb_build_object('hidden', p_hidden));
end $$;

-- Offers feed. p_mine = the doctor's own (any state); admin sees everything incl. hidden.
create or replace function public.list_offers(
  p_specialty int default null, p_governorate int default null, p_doctor uuid default null,
  p_mine boolean default false, p_limit int default 60)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
    select o.created_at, jsonb_build_object(
      'id', o.id, 'doctor_id', o.doctor_id, 'kind', o.kind, 'title', o.title, 'body', o.body,
      'price', o.price, 'old_price', o.old_price, 'image_url', o.image_url, 'valid_until', o.valid_until,
      'is_active', o.is_active, 'hidden_by_admin', o.hidden_by_admin, 'views', o.views, 'bookings', o.bookings,
      'created_at', o.created_at,
      'doctor_name', p.full_name, 'doctor_avatar', p.avatar_url, 'doctor_title', d.title,
      'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
      'clinic_name', c.name, 'clinic_address', c.address, 'clinic_phone', c.phone,
      'city', ci.name_ar, 'governorate', g.name_ar) j
    from doctor_offers o
    join doctors d on d.id = o.doctor_id
    join profiles p on p.id = d.id
    left join specialties s on s.id = d.specialty_id
    left join clinics c on c.id = coalesce(o.clinic_id,
         (select c2.id from clinics c2 where c2.doctor_id = d.id and c2.is_active order by c2.created_at limit 1))
    left join cities ci on ci.id = c.city_id
    left join governorates g on g.id = c.governorate_id
    where case
            when coalesce(p_mine, false) then acts_for(o.doctor_id, 'any') and o.doctor_id = coalesce(p_doctor, o.doctor_id)
            when is_admin() and p_doctor is null and p_specialty is null and p_governorate is null then true
            else o.is_active and not o.hidden_by_admin and d.status = 'verified' and not p.is_suspended
                 and (o.valid_until is null or o.valid_until >= (now() at time zone 'Africa/Cairo')::date)
          end
      and (p_specialty is null or d.specialty_id = p_specialty)
      and (p_governorate is null or c.governorate_id = p_governorate)
      and (p_doctor is null or o.doctor_id = p_doctor)
    order by o.created_at desc
    limit least(coalesce(p_limit, 60), 200)) x;
$$;

create or replace function public.offer_event(p_id uuid, p_event text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  if p_event = 'view' then
    update doctor_offers set views = views + 1 where id = p_id and doctor_id <> auth.uid();
  elsif p_event = 'booking' then
    update doctor_offers set bookings = bookings + 1 where id = p_id and doctor_id <> auth.uid();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Admin announcements
-- ---------------------------------------------------------------------
create or replace function public.admin_save_announcement(
  p_id uuid, p_title text, p_body text default null, p_audience text default 'all',
  p_image_url text default null, p_link_url text default null, p_ends_on date default null, p_active boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_id is null then
    insert into announcements (audience, title, body, image_url, link_url, ends_on, is_active, created_by)
    values (coalesce(p_audience, 'all'), trim(p_title), nullif(trim(p_body), ''), nullif(trim(p_image_url), ''),
            nullif(trim(p_link_url), ''), p_ends_on, coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    update announcements set audience = coalesce(p_audience, audience), title = trim(p_title), body = nullif(trim(p_body), ''),
           image_url = nullif(trim(p_image_url), ''), link_url = nullif(trim(p_link_url), ''), ends_on = p_ends_on,
           is_active = coalesce(p_active, is_active)
     where id = p_id returning id into v_id;
  end if;
  perform write_audit('announcement.saved', 'announcements', v_id::text, jsonb_build_object('audience', p_audience));
  return v_id;
end $$;

create or replace function public.admin_delete_announcement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  delete from announcements where id = p_id;
end $$;

create or replace function public.admin_list_announcements()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'audience', a.audience, 'title', a.title, 'body', a.body, 'image_url', a.image_url,
      'link_url', a.link_url, 'ends_on', a.ends_on, 'is_active', a.is_active, 'created_at', a.created_at,
      'dismissed', (select count(*) from announcement_dismissals x where x.announcement_id = a.id))
      order by a.created_at desc) from announcements a), '[]'::jsonb);
end $$;

-- What the signed-in user should see on their home screen.
create or replace function public.my_announcements()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'title', a.title, 'body', a.body, 'image_url', a.image_url, 'link_url', a.link_url,
      'audience', a.audience, 'created_at', a.created_at) order by a.created_at desc), '[]'::jsonb)
  from announcements a, profiles me
  where me.id = auth.uid()
    and a.is_active
    and (a.ends_on is null or a.ends_on >= (now() at time zone 'Africa/Cairo')::date)
    and (a.audience = 'all'
         or (a.audience = 'doctors' and me.role in ('doctor', 'assistant', 'admin'))
         or (a.audience = 'patients' and me.role in ('patient', 'admin')))
    and not exists (select 1 from announcement_dismissals x where x.announcement_id = a.id and x.user_id = me.id);
$$;

create or replace function public.dismiss_announcement(p_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into announcement_dismissals (announcement_id, user_id)
  select p_id, auth.uid() where auth.uid() is not null and exists (select 1 from announcements where id = p_id)
  on conflict do nothing;
$$;

revoke all on function public.save_offer(uuid, text, text, text, numeric, numeric, text, date, uuid, boolean, uuid),
  public.delete_offer(uuid), public.admin_hide_offer(uuid, boolean),
  public.list_offers(int, int, uuid, boolean, int), public.offer_event(uuid, text),
  public.admin_save_announcement(uuid, text, text, text, text, text, date, boolean), public.admin_delete_announcement(uuid),
  public.admin_list_announcements(), public.my_announcements(), public.dismiss_announcement(uuid)
from public, anon;
grant execute on function public.save_offer(uuid, text, text, text, numeric, numeric, text, date, uuid, boolean, uuid),
  public.delete_offer(uuid), public.admin_hide_offer(uuid, boolean),
  public.list_offers(int, int, uuid, boolean, int), public.offer_event(uuid, text),
  public.admin_save_announcement(uuid, text, text, text, text, text, date, boolean), public.admin_delete_announcement(uuid),
  public.admin_list_announcements(), public.my_announcements(), public.dismiss_announcement(uuid)
to authenticated;
