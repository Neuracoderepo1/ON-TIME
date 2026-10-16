create table public.app_config (key text primary key, value jsonb not null);
create table public.app_secrets (key text primary key, value text not null);
create table public.rate_limit_hits (key text not null, window_start timestamptz not null, hits integer not null default 0, primary key (key, window_start));
insert into public.app_secrets values ('ip_hash_salt', gen_random_uuid()::text);
insert into public.app_config(key, value) values
 ('daily_participation_cap','30'),('streak_min_window_minutes','10'),('streak_bonus_7','5'),('streak_bonus_30','15'),
 ('redemption_hold_hours','24'),('history_mask_threshold','10'),('phone_otp_enabled','false'),
 ('weekly_redemption_cap_no_phone','1'),('min_age','18'),
 ('rl_checkin_user_per_min','10'),('rl_checkin_ip_per_min','60'),('rl_redeem_user_per_min','10'),('rl_redeem_ip_per_min','30');

create table public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin')),
  created_at timestamptz not null default now());

create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'admin') $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  email text,
  display_name text check (char_length(display_name) <= 60),
  timezone text not null default 'UTC',
  country_code text check (country_code ~ '^[A-Z]{2}$'),
  phone_e164 text unique check (phone_e164 ~ '^\+[1-9][0-9]{1,14}$'),
  phone_verified_at timestamptz,
  age_confirmed_at timestamptz not null,
  consent_at timestamptz not null,
  credit_balance integer not null default 0 check (credit_balance >= 0),
  current_streak integer not null default 0 check (current_streak >= 0),
  longest_streak integer not null default 0 check (longest_streak >= 0),
  streak_seq integer not null default 0,
  streak_last_day date,
  streak_evaluated_through date not null,
  anonymized_at timestamptz,
  created_at timestamptz not null default now(),
  constraint phone_verified_needs_phone check (phone_verified_at is null or phone_e164 is not null));

create function public.guard_profile() returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'INVALID_TIMEZONE';
  end if;
  if tg_op = 'UPDATE' then
    if new.id <> old.id then raise exception 'PROFILE_ID_IMMUTABLE'; end if;
    if new.credit_balance is distinct from old.credit_balance
       and coalesce(current_setting('app.ledger_write', true), '') <> '1' then
      raise exception 'BALANCE_IMMUTABLE';
    end if;
  end if;
  return new;
end $$;
create trigger profiles_guard before insert or update on public.profiles for each row execute function public.guard_profile();

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
        tz text := coalesce(nullif(m->>'timezone', ''), 'UTC');
begin
  if coalesce(m->>'age_confirmed', 'false') <> 'true' then raise exception 'AGE_CONFIRMATION_REQUIRED'; end if;
  if coalesce(m->>'consent', 'false') <> 'true' then raise exception 'CONSENT_REQUIRED'; end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  insert into public.profiles (id, email, display_name, timezone, country_code, age_confirmed_at, consent_at, streak_evaluated_through)
  values (new.id, new.email, left(nullif(m->>'display_name', ''), 60), tz,
          case when upper(m->>'country_code') ~ '^[A-Z]{2}$' then upper(m->>'country_code') end,
          now(), now(), ((now() at time zone tz)::date) - 1);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'ON-TIME Round' check (char_length(title) between 1 and 120),
  start_at timestamptz not null,
  participation_open_at timestamptz not null,
  participation_close_at timestamptz not null,
  credit_award integer not null default 10 check (credit_award between 1 and 1000),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  check (participation_open_at < participation_close_at));
create index rounds_open_idx on public.rounds (participation_open_at);

create function public.round_status(r public.rounds) returns text language sql stable set search_path = '' as $$
  select case when r.cancelled_at is not null then 'cancelled'
              when now() < r.participation_open_at then 'scheduled'
              when now() < r.participation_close_at then 'open'
              else 'closed' end $$;

create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  round_id uuid not null references public.rounds(id),
  checked_in_at timestamptz not null default now(),
  local_day date not null,
  latency_ms integer not null,
  unique (user_id, round_id));
create index check_ins_round_idx on public.check_ins (round_id);
create index check_ins_user_day_idx on public.check_ins (user_id, local_day);

create table public.credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  amount integer not null check (amount <> 0),
  type text not null check (type in ('ROUND_PARTICIPATION','STREAK_BONUS','REWARD_REDEMPTION','REDEMPTION_REFUND','ADMIN_ADJUSTMENT')),
  reference_id uuid,
  idempotency_key text not null unique,
  description text not null default '',
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  constraint ledger_sign check (
    (type in ('ROUND_PARTICIPATION','STREAK_BONUS','REDEMPTION_REFUND') and amount > 0)
    or (type = 'REWARD_REDEMPTION' and amount < 0)
    or type = 'ADMIN_ADJUSTMENT'),
  constraint ledger_admin_needs_actor check (type <> 'ADMIN_ADJUSTMENT' or (created_by is not null and char_length(btrim(description)) > 0)));
create index ledger_user_idx on public.credit_ledger (user_id, created_at);

create function public.forbid_mutation() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'APPEND_ONLY: % on % is not allowed', tg_op, tg_table_name using errcode = '42501'; end $$;
create trigger ledger_no_mutation before update or delete on public.credit_ledger for each row execute function public.forbid_mutation();
create trigger ledger_no_truncate before truncate on public.credit_ledger for each statement execute function public.forbid_mutation();

create function public.apply_ledger_to_balance() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('app.ledger_write', '1', true);
  update public.profiles set credit_balance = credit_balance + new.amount where id = new.user_id;
  perform set_config('app.ledger_write', '0', true);
  return new;
end $$;
create trigger ledger_apply after insert on public.credit_ledger for each row execute function public.apply_ledger_to_balance();

create table public.partners (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  description text not null default '',
  logo_url text,
  active boolean not null default true,
  created_at timestamptz not null default now());
create table public.partner_contacts (
  partner_id uuid primary key references public.partners(id) on delete cascade,
  contact_name text, email text, phone text, notes text);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid references public.partners(id),
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '',
  category text not null check (category in ('Connectivity','Food','Shopping','Events','Education','Digital','Services')),
  cost integer not null check (cost > 0),
  stock integer check (stock is null or stock >= 0),
  instructions text not null default '',
  expires_at timestamptz,
  image_url text,
  active boolean not null default false,
  fulfilment_type text not null check (fulfilment_type in ('code_pool','manual')),
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint code_pool_has_no_stock check (fulfilment_type <> 'code_pool' or stock is null));

create table public.reward_codes (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.rewards(id),
  code text not null check (char_length(code) between 1 and 200),
  status text not null default 'available' check (status in ('available','assigned')),
  redemption_id uuid,
  created_at timestamptz not null default now(),
  assigned_at timestamptz,
  unique (reward_id, code));
create index reward_codes_avail_idx on public.reward_codes (reward_id, status);

create table public.redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  reward_id uuid not null references public.rewards(id),
  cost integer not null check (cost > 0),
  status text not null check (status in ('pending','fulfilled','cancelled')),
  idempotency_key text not null,
  fulfilment_ref text,
  code_id uuid references public.reward_codes(id),
  created_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  unique (user_id, idempotency_key));
create index redemptions_user_idx on public.redemptions (user_id, created_at);
create index redemptions_status_idx on public.redemptions (status, created_at);

create table public.redemption_events (
  id uuid primary key default gen_random_uuid(),
  redemption_id uuid not null references public.redemptions(id),
  status text not null,
  actor uuid,
  note text,
  created_at timestamptz not null default now());

create function public.guard_redemption() returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'APPEND_ONLY: DELETE on redemptions is not allowed' using errcode = '42501'; end if;
  if new.id <> old.id or new.user_id <> old.user_id or new.reward_id <> old.reward_id or new.cost <> old.cost
     or new.idempotency_key <> old.idempotency_key or new.created_at <> old.created_at then
    raise exception 'REDEMPTION_IMMUTABLE';
  end if;
  if old.status in ('fulfilled','cancelled') and
     (new.status <> old.status or new.fulfilment_ref is distinct from old.fulfilment_ref or new.code_id is distinct from old.code_id) then
    raise exception 'REDEMPTION_FINAL';
  end if;
  return new;
end $$;
create trigger redemptions_guard before update or delete on public.redemptions for each row execute function public.guard_redemption();
create trigger redemption_events_no_mutation before update or delete on public.redemption_events for each row execute function public.forbid_mutation();

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid, action text not null, target_type text, target_id text,
  before jsonb, after jsonb, created_at timestamptz not null default now());
create trigger audit_no_mutation before update or delete on public.audit_log for each row execute function public.forbid_mutation();

create table public.client_signals (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles(id), ip_hash text not null, kind text not null,
  created_at timestamptz not null default now());
create index client_signals_idx on public.client_signals (ip_hash, created_at);

create table public.risk_flags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id), kind text not null, detail jsonb not null default '{}'::jsonb,
  flagged_on date not null default current_date, created_at timestamptz not null default now(),
  reviewed_at timestamptz, reviewed_by uuid, review_note text,
  unique (user_id, kind, flagged_on));

create table public.data_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  kind text not null check (kind in ('export','deletion')),
  status text not null default 'open' check (status in ('open','done')),
  created_at timestamptz not null default now(), handled_at timestamptz);

alter table public.app_config enable row level security;
alter table public.app_secrets enable row level security;
alter table public.rate_limit_hits enable row level security;
alter table public.user_roles enable row level security;
alter table public.profiles enable row level security;
alter table public.rounds enable row level security;
alter table public.check_ins enable row level security;
alter table public.credit_ledger enable row level security;
alter table public.partners enable row level security;
alter table public.partner_contacts enable row level security;
alter table public.rewards enable row level security;
alter table public.reward_codes enable row level security;
alter table public.redemptions enable row level security;
alter table public.redemption_events enable row level security;
alter table public.audit_log enable row level security;
alter table public.client_signals enable row level security;
alter table public.risk_flags enable row level security;
alter table public.data_requests enable row level security;

create policy cfg_read on public.app_config for select to authenticated using (true);
create policy roles_read on public.user_roles for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create policy profiles_read on public.profiles for select to authenticated using (id = (select auth.uid()) or public.is_admin());
create policy rounds_read on public.rounds for select to anon, authenticated using (true);
create policy checkins_read on public.check_ins for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create policy ledger_read on public.credit_ledger for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create policy partners_read on public.partners for select to anon, authenticated using (active or public.is_admin());
create policy partner_contacts_admin on public.partner_contacts for select to authenticated using (public.is_admin());
create policy rewards_read on public.rewards for select to anon, authenticated using (
  public.is_admin() or (active and (partner_id is null or exists (select 1 from public.partners p where p.id = partner_id and p.active))));
create policy codes_admin on public.reward_codes for select to authenticated using (public.is_admin());
create policy redemptions_read on public.redemptions for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create policy redemption_events_read on public.redemption_events for select to authenticated using (
  public.is_admin() or exists (select 1 from public.redemptions r where r.id = redemption_id and r.user_id = (select auth.uid())));
create policy audit_admin on public.audit_log for select to authenticated using (public.is_admin());
create policy signals_admin on public.client_signals for select to authenticated using (public.is_admin());
create policy flags_admin on public.risk_flags for select to authenticated using (public.is_admin());
create policy data_requests_read on public.data_requests for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.rounds, public.rewards, public.partners to anon, authenticated;
grant select on public.profiles, public.check_ins, public.credit_ledger, public.redemptions, public.redemption_events,
  public.user_roles, public.data_requests, public.app_config, public.audit_log, public.risk_flags,
  public.client_signals, public.reward_codes, public.partner_contacts to authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.round_status(public.rounds) to anon, authenticated;