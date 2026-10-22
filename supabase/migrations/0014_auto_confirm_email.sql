-- =====================================================================
-- دكتوري — 0014: تأكيد حسابات الإيميل تلقائياً
-- The free Supabase mailer only delivers to the project team and a few emails per hour,
-- so doctors never got the confirmation link. Doctors are verified by the admin's WhatsApp
-- activation code instead, so email accounts are confirmed as soon as they are created.
-- =====================================================================
create or replace function public.auto_confirm_email() returns trigger
language plpgsql security definer set search_path = public, auth as $$
begin
  if new.email is not null and new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end $$;
revoke all on function public.auto_confirm_email() from public, anon, authenticated;

drop trigger if exists auto_confirm_email on auth.users;
create trigger auto_confirm_email before insert on auth.users
  for each row execute function public.auto_confirm_email();

-- Accounts that signed up and are still waiting for the email.
update auth.users set email_confirmed_at = now()
 where email is not null and email_confirmed_at is null and deleted_at is null;
