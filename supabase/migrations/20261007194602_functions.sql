create function public.cfg_int(k text) returns integer language sql stable security definer set search_path = '' as
$$ select (value #>> '{}')::integer from public.app_config where key = k $$;
create function public.cfg_bool(k text) returns boolean language sql stable security definer set search_path = '' as
$$ select (value #>> '{}')::boolean from public.app_config where key = k $$;

create function public.request_ip() returns text language sql stable set search_path = '' as
$$ select nullif(btrim(split_part(coalesce((nullif(current_setting('request.headers', true), '')::json)->>'x-forwarded-for', ''), ',', 1)), '') $$;

create function public.hash_ip(p_ip text) returns text language sql stable security definer set search_path = '' as
$$ select encode(extensions.digest(coalesce(p_ip, 'unknown') || (select value from public.app_secrets where key = 'ip_hash_salt'), 'sha256'), 'hex') $$;

create function public.consume_rate_limit(p_key text, p_max integer, p_secs integer) returns boolean
language plpgsql security definer set search_path = '' as $$
declare w timestamptz := to_timestamp(floor(extract(epoch from now()) / p_secs) * p_secs); h integer;
begin
  insert into public.rate_limit_hits (key, window_start, hits) values (p_key, w, 1)
  on conflict (key, window_start) do update set hits = public.rate_limit_hits.hits + 1 returning hits into h;
  if random() < 0.01 then delete from public.rate_limit_hits where window_start < now() - interval '1 day'; end if;
  return h <= p_max;
end $$;

create function public.is_eligible_day(p_day date, p_tz text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.rounds r
    where r.cancelled_at is null
      and least(r.participation_close_at, ((p_day + 1)::timestamp at time zone p_tz))
        - greatest(r.participation_open_at, (p_day::timestamp at time zone p_tz))
        >= make_interval(mins => public.cfg_int('streak_min_window_minutes'))) $$;

create function public.advance_streak(p_user uuid) returns void language plpgsql security definer set search_path = '' as $$
declare p public.profiles; d date; today date; cur integer;
begin
  select * into p from public.profiles where id = p_user for update;
  today := (now() at time zone p.timezone)::date;
  cur := p.current_streak;
  d := p.streak_evaluated_through + 1;
  while cur > 0 and d < today loop
    if public.is_eligible_day(d, p.timezone)
       and not exists (select 1 from public.check_ins c where c.user_id = p_user and c.local_day = d) then
      cur := 0;
    end if;
    d := d + 1;
  end loop;
  update public.profiles set current_streak = cur, streak_evaluated_through = greatest(streak_evaluated_through, today - 1) where id = p_user;
end $$;

create function public._check_in_core(p_user uuid, p_round uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.profiles; r public.rounds; ld date; used integer; ns integer; sq integer; bonus integer := 0; b integer; lat integer;
begin
  select * into p from public.profiles where id = p_user and anonymized_at is null for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'NO_PROFILE'); end if;
  perform public.advance_streak(p_user);
  select * into p from public.profiles where id = p_user;
  select * into r from public.rounds where id = p_round;
  if not found then return jsonb_build_object('ok', false, 'code', 'ROUND_NOT_FOUND'); end if;
  case public.round_status(r)
    when 'scheduled' then return jsonb_build_object('ok', false, 'code', 'ROUND_NOT_OPEN');
    when 'closed' then return jsonb_build_object('ok', false, 'code', 'ROUND_CLOSED');
    when 'cancelled' then return jsonb_build_object('ok', false, 'code', 'ROUND_CLOSED');
    else null;
  end case;
  if exists (select 1 from public.check_ins where user_id = p_user and round_id = p_round) then
    return jsonb_build_object('ok', false, 'code', 'ALREADY_CHECKED_IN');
  end if;
  ld := (now() at time zone p.timezone)::date;
  select coalesce(sum(amount), 0) into used from public.credit_ledger
   where user_id = p_user and type = 'ROUND_PARTICIPATION' and (created_at at time zone p.timezone)::date = ld;
  if used + r.credit_award > public.cfg_int('daily_participation_cap') then
    return jsonb_build_object('ok', false, 'code', 'DAILY_CAP_REACHED');
  end if;
  lat := (extract(epoch from (now() - r.participation_open_at)) * 1000)::integer;
  insert into public.check_ins (user_id, round_id, local_day, latency_ms) values (p_user, p_round, ld, lat);
  insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description)
  values (p_user, r.credit_award, 'ROUND_PARTICIPATION', p_round, 'ROUND_PARTICIPATION:' || p_round || ':' || p_user, 'Round participation');
  if public.is_eligible_day(ld, p.timezone) and p.streak_last_day is distinct from ld then
    ns := p.current_streak + 1;
    sq := p.streak_seq + case when p.current_streak = 0 then 1 else 0 end;
    update public.profiles set current_streak = ns, longest_streak = greatest(longest_streak, ns), streak_seq = sq, streak_last_day = ld where id = p_user;
    if ns = 7 then
      insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description)
      values (p_user, public.cfg_int('streak_bonus_7'), 'STREAK_BONUS', p_round, 'STREAK_BONUS:' || p_user || ':' || sq || ':7', '7-day streak bonus')
      on conflict (idempotency_key) do nothing returning amount into b;
      if found then bonus := bonus + b; end if;
    elsif ns = 30 then
      insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description)
      values (p_user, public.cfg_int('streak_bonus_30'), 'STREAK_BONUS', p_round, 'STREAK_BONUS:' || p_user || ':' || sq || ':30', '30-day streak bonus')
      on conflict (idempotency_key) do nothing returning amount into b;
      if found then bonus := bonus + b; end if;
    end if;
  end if;
  insert into public.client_signals (user_id, ip_hash, kind) values (p_user, public.hash_ip(public.request_ip()), 'checkin');
  select * into p from public.profiles where id = p_user;
  return jsonb_build_object('ok', true, 'awarded', r.credit_award, 'bonus', bonus, 'balance', p.credit_balance,
    'streak', p.current_streak, 'longest_streak', p.longest_streak);
end $$;

create function public.check_in(p_round_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED'); end if;
  if not public.consume_rate_limit('ci:u:' || uid, public.cfg_int('rl_checkin_user_per_min'), 60)
     or not public.consume_rate_limit('ci:ip:' || public.hash_ip(public.request_ip()), public.cfg_int('rl_checkin_ip_per_min'), 60) then
    return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED');
  end if;
  if not exists (select 1 from auth.users where id = uid and email_confirmed_at is not null) then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_NOT_VERIFIED');
  end if;
  return public._check_in_core(uid, p_round_id);
end $$;

create function public._redeem_core(p_user uuid, p_reward uuid, p_key text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.profiles; rw public.rewards; red public.redemptions; cd public.reward_codes; rid uuid := gen_random_uuid(); st text; avail timestamptz;
begin
  if p_key is null or char_length(p_key) not between 8 and 100 then return jsonb_build_object('ok', false, 'code', 'BAD_IDEMPOTENCY_KEY'); end if;
  select * into p from public.profiles where id = p_user and anonymized_at is null for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'NO_PROFILE'); end if;
  select * into red from public.redemptions where user_id = p_user and idempotency_key = p_key;
  if found then return jsonb_build_object('ok', true, 'replay', true, 'redemption', to_jsonb(red)); end if;
  if public.cfg_bool('phone_otp_enabled') then
    if p.phone_verified_at is null then return jsonb_build_object('ok', false, 'code', 'PHONE_REQUIRED'); end if;
  elsif (select count(*) from public.redemptions where user_id = p_user and status <> 'cancelled' and created_at > now() - interval '7 days')
        >= public.cfg_int('weekly_redemption_cap_no_phone') then
    return jsonb_build_object('ok', false, 'code', 'WEEKLY_LIMIT');
  end if;
  avail := p.created_at + make_interval(hours => public.cfg_int('redemption_hold_hours'));
  if now() < avail then return jsonb_build_object('ok', false, 'code', 'NEW_ACCOUNT_HOLD', 'available_at', avail); end if;
  select * into rw from public.rewards where id = p_reward for update;
  if not found or not rw.active or (rw.expires_at is not null and rw.expires_at <= now())
     or (rw.partner_id is not null and not exists (select 1 from public.partners where id = rw.partner_id and active)) then
    return jsonb_build_object('ok', false, 'code', 'REWARD_UNAVAILABLE');
  end if;
  if rw.stock is not null and rw.stock <= 0 then return jsonb_build_object('ok', false, 'code', 'OUT_OF_STOCK'); end if;
  if p.credit_balance < rw.cost then
    return jsonb_build_object('ok', false, 'code', 'INSUFFICIENT_CREDITS', 'needed', rw.cost - p.credit_balance);
  end if;
  if rw.fulfilment_type = 'code_pool' then
    select * into cd from public.reward_codes where reward_id = rw.id and status = 'available' order by created_at, id limit 1 for update skip locked;
    if not found then return jsonb_build_object('ok', false, 'code', 'OUT_OF_STOCK'); end if;
    st := 'fulfilled';
  else st := 'pending'; end if;
  insert into public.redemptions (id, user_id, reward_id, cost, status, idempotency_key, fulfilment_ref, code_id, fulfilled_at)
  values (rid, p_user, rw.id, rw.cost, st, p_key, case when st = 'fulfilled' then cd.code end, cd.id, case when st = 'fulfilled' then now() end)
  returning * into red;
  insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description)
  values (p_user, -rw.cost, 'REWARD_REDEMPTION', rid, 'REWARD_REDEMPTION:' || rid, 'Redeemed: ' || rw.title);
  if rw.stock is not null then update public.rewards set stock = stock - 1 where id = rw.id; end if;
  if cd.id is not null then update public.reward_codes set status = 'assigned', redemption_id = rid, assigned_at = now() where id = cd.id; end if;
  insert into public.redemption_events (redemption_id, status, actor, note) values (rid, st, p_user, 'created');
  return jsonb_build_object('ok', true, 'replay', false, 'redemption', to_jsonb(red));
end $$;

create function public.redeem_reward(p_reward_id uuid, p_idempotency_key text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED'); end if;
  if not public.consume_rate_limit('rd:u:' || uid, public.cfg_int('rl_redeem_user_per_min'), 60)
     or not public.consume_rate_limit('rd:ip:' || public.hash_ip(public.request_ip()), public.cfg_int('rl_redeem_ip_per_min'), 60) then
    return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED');
  end if;
  if not exists (select 1 from auth.users where id = uid and email_confirmed_at is not null) then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_NOT_VERIFIED');
  end if;
  return public._redeem_core(uid, p_reward_id, p_idempotency_key);
end $$;

create function public.my_dashboard() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); p public.profiles;
begin
  if uid is null then return null; end if;
  perform public.advance_streak(uid);
  select * into p from public.profiles where id = uid;
  return jsonb_build_object('balance', p.credit_balance, 'streak', p.current_streak, 'longest_streak', p.longest_streak,
    'timezone', p.timezone, 'display_name', p.display_name, 'phone_verified', p.phone_verified_at is not null,
    'rounds_participated', (select count(*) from public.check_ins where user_id = uid),
    'activity', (select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at desc), '[]'::jsonb)
                 from (select id, amount, type, description, created_at from public.credit_ledger where user_id = uid order by created_at desc limit 20) l),
    'redemptions', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
                 from (select d.id, d.status, d.cost, d.fulfilment_ref, d.created_at, w.title, w.is_demo
                       from public.redemptions d join public.rewards w on w.id = d.reward_id where d.user_id = uid order by d.created_at desc limit 50) x));
end $$;

create function public.update_profile(p_display_name text, p_timezone text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED'); end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then return jsonb_build_object('ok', false, 'code', 'INVALID_TIMEZONE'); end if;
  perform public.advance_streak(uid);
  update public.profiles set display_name = left(nullif(btrim(p_display_name), ''), 60), timezone = p_timezone where id = uid;
  return jsonb_build_object('ok', true);
end $$;

create function public.request_data_action(p_kind text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or p_kind not in ('export', 'deletion') then return jsonb_build_object('ok', false, 'code', 'BAD_REQUEST'); end if;
  insert into public.data_requests (user_id, kind) values (uid, p_kind);
  return jsonb_build_object('ok', true);
end $$;

create function public.export_my_data() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return null; end if;
  return jsonb_build_object(
    'profile', (select to_jsonb(p) - 'anonymized_at' from public.profiles p where id = uid),
    'check_ins', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.check_ins c where user_id = uid),
    'ledger', (select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb) from public.credit_ledger l where user_id = uid),
    'redemptions', (select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb) from public.redemptions d where user_id = uid));
end $$;

create function public.public_round_history() returns table (round_id uuid, title text, start_at timestamptz, credit_award integer, status text, participation text)
language sql stable security definer set search_path = '' as $$
  select r.id, r.title, r.start_at, r.credit_award, public.round_status(r),
         case when c.n < public.cfg_int('history_mask_threshold') then '<' || public.cfg_int('history_mask_threshold')::text else c.n::text end
  from public.rounds r cross join lateral (select count(*) n from public.check_ins ci where ci.round_id = r.id) c
  where r.cancelled_at is not null or now() >= r.participation_open_at
  order by r.start_at desc limit 100 $$;

create function public.next_round_info() returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(x) from (
    select r.id, r.title, r.start_at, r.participation_open_at, r.participation_close_at, r.credit_award,
           public.round_status(r) as status, now() as server_now
    from public.rounds r where r.cancelled_at is null and r.participation_close_at > now()
    order by r.participation_open_at limit 1) x $$;

create function public.require_admin() returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null or not exists (select 1 from public.user_roles where user_id = u and role = 'admin') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return u;
end $$;

create function public.write_audit(p_actor uuid, p_action text, p_type text, p_target text, p_before jsonb, p_after jsonb) returns void
language sql security definer set search_path = '' as
$$ insert into public.audit_log (actor_id, action, target_type, target_id, before, after) values (p_actor, p_action, p_type, p_target, p_before, p_after) $$;

create function public.admin_upsert_round(p_id uuid, p_title text, p_start timestamptz, p_open timestamptz, p_close timestamptz, p_award integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); old public.rounds; nr public.rounds;
begin
  if p_id is null then
    insert into public.rounds (title, start_at, participation_open_at, participation_close_at, credit_award, created_by)
    values (coalesce(p_title, 'ON-TIME Round'), p_start, p_open, p_close, coalesce(p_award, 10), a) returning * into nr;
    perform public.write_audit(a, 'round.create', 'round', nr.id::text, null, to_jsonb(nr));
  else
    select * into old from public.rounds where id = p_id for update;
    if not found then raise exception 'ROUND_NOT_FOUND'; end if;
    if public.round_status(old) <> 'scheduled' then raise exception 'ROUND_LOCKED'; end if;
    update public.rounds set title = coalesce(p_title, title), start_at = coalesce(p_start, start_at),
      participation_open_at = coalesce(p_open, participation_open_at), participation_close_at = coalesce(p_close, participation_close_at),
      credit_award = coalesce(p_award, credit_award) where id = p_id returning * into nr;
    perform public.write_audit(a, 'round.update', 'round', p_id::text, to_jsonb(old), to_jsonb(nr));
  end if;
  return to_jsonb(nr);
end $$;

create function public.admin_round_action(p_id uuid, p_action text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); old public.rounds; nr public.rounds; s text;
begin
  select * into old from public.rounds where id = p_id for update;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  s := public.round_status(old);
  if p_action = 'open' then
    if s <> 'scheduled' then raise exception 'INVALID_TRANSITION'; end if;
    if old.participation_close_at <= clock_timestamp() then raise exception 'INVALID_TRANSITION'; end if;
    update public.rounds set participation_open_at = least(participation_open_at, clock_timestamp()) where id = p_id returning * into nr;
  elsif p_action = 'close' then
    if s <> 'open' then raise exception 'INVALID_TRANSITION'; end if;
    update public.rounds set participation_close_at = greatest(clock_timestamp(), participation_open_at + interval '1 millisecond') where id = p_id returning * into nr;
  elsif p_action = 'cancel' then
    if s = 'cancelled' then raise exception 'INVALID_TRANSITION'; end if;
    update public.rounds set cancelled_at = now() where id = p_id returning * into nr;
  else raise exception 'UNKNOWN_ACTION'; end if;
  perform public.write_audit(a, 'round.' || p_action, 'round', p_id::text, to_jsonb(old), to_jsonb(nr));
  return to_jsonb(nr);
end $$;

create function public.admin_upsert_partner(p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); old public.partners; np public.partners;
begin
  if p_id is null then
    insert into public.partners (name, description, logo_url, active)
    values (p->>'name', coalesce(p->>'description', ''), nullif(p->>'logo_url', ''), coalesce((p->>'active')::boolean, true)) returning * into np;
    perform public.write_audit(a, 'partner.create', 'partner', np.id::text, null, to_jsonb(np));
  else
    select * into old from public.partners where id = p_id for update;
    if not found then raise exception 'PARTNER_NOT_FOUND'; end if;
    update public.partners set name = case when p ? 'name' then p->>'name' else name end,
      description = case when p ? 'description' then coalesce(p->>'description', '') else description end,
      logo_url = case when p ? 'logo_url' then nullif(p->>'logo_url', '') else logo_url end,
      active = case when p ? 'active' then (p->>'active')::boolean else active end where id = p_id returning * into np;
    perform public.write_audit(a, 'partner.update', 'partner', p_id::text, to_jsonb(old), to_jsonb(np));
  end if;
  if p ? 'contact' then
    insert into public.partner_contacts (partner_id, contact_name, email, phone, notes)
    values (np.id, p->'contact'->>'name', p->'contact'->>'email', p->'contact'->>'phone', p->'contact'->>'notes')
    on conflict (partner_id) do update set contact_name = excluded.contact_name, email = excluded.email, phone = excluded.phone, notes = excluded.notes;
  end if;
  return to_jsonb(np);
end $$;

create function public.admin_upsert_reward(p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); old public.rewards; nw public.rewards;
begin
  if p_id is null then
    insert into public.rewards (title, description, category, cost, stock, instructions, expires_at, image_url, active, fulfilment_type, partner_id, is_demo)
    values (p->>'title', coalesce(p->>'description', ''), p->>'category', (p->>'cost')::integer, nullif(p->>'stock', '')::integer,
            coalesce(p->>'instructions', ''), nullif(p->>'expires_at', '')::timestamptz, nullif(p->>'image_url', ''),
            coalesce((p->>'active')::boolean, false), p->>'fulfilment_type', nullif(p->>'partner_id', '')::uuid, coalesce((p->>'is_demo')::boolean, true))
    returning * into nw;
    perform public.write_audit(a, 'reward.create', 'reward', nw.id::text, null, to_jsonb(nw));
  else
    select * into old from public.rewards where id = p_id for update;
    if not found then raise exception 'REWARD_NOT_FOUND'; end if;
    update public.rewards set
      title = case when p ? 'title' then p->>'title' else title end,
      description = case when p ? 'description' then coalesce(p->>'description', '') else description end,
      category = case when p ? 'category' then p->>'category' else category end,
      cost = case when p ? 'cost' then (p->>'cost')::integer else cost end,
      stock = case when p ? 'stock' then nullif(p->>'stock', '')::integer else stock end,
      instructions = case when p ? 'instructions' then coalesce(p->>'instructions', '') else instructions end,
      expires_at = case when p ? 'expires_at' then nullif(p->>'expires_at', '')::timestamptz else expires_at end,
      image_url = case when p ? 'image_url' then nullif(p->>'image_url', '') else image_url end,
      active = case when p ? 'active' then (p->>'active')::boolean else active end,
      partner_id = case when p ? 'partner_id' then nullif(p->>'partner_id', '')::uuid else partner_id end,
      is_demo = case when p ? 'is_demo' then (p->>'is_demo')::boolean else is_demo end
    where id = p_id returning * into nw;
    perform public.write_audit(a, 'reward.update', 'reward', p_id::text, to_jsonb(old), to_jsonb(nw));
  end if;
  return to_jsonb(nw);
end $$;

create function public.admin_load_codes(p_reward uuid, p_codes text[]) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); rw public.rewards; n integer;
begin
  select * into rw from public.rewards where id = p_reward;
  if not found or rw.fulfilment_type <> 'code_pool' then raise exception 'NOT_A_CODE_POOL'; end if;
  insert into public.reward_codes (reward_id, code)
  select p_reward, btrim(c) from unnest(p_codes) c where char_length(btrim(c)) between 1 and 200 on conflict (reward_id, code) do nothing;
  get diagnostics n = row_count;
  perform public.write_audit(a, 'reward.load_codes', 'reward', p_reward::text, null, jsonb_build_object('inserted', n));
  return jsonb_build_object('inserted', n);
end $$;

create function public.admin_fulfil_redemption(p_id uuid, p_ref text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); r public.redemptions; nr public.redemptions;
begin
  select * into r from public.redemptions where id = p_id for update;
  if not found then raise exception 'REDEMPTION_NOT_FOUND'; end if;
  if r.status <> 'pending' then raise exception 'NOT_PENDING'; end if;
  if char_length(btrim(coalesce(p_ref, ''))) = 0 then raise exception 'REFERENCE_REQUIRED'; end if;
  update public.redemptions set status = 'fulfilled', fulfilment_ref = btrim(p_ref), fulfilled_at = now() where id = p_id returning * into nr;
  insert into public.redemption_events (redemption_id, status, actor, note) values (p_id, 'fulfilled', a, 'fulfilled by admin');
  perform public.write_audit(a, 'redemption.fulfil', 'redemption', p_id::text, to_jsonb(r), to_jsonb(nr));
  return to_jsonb(nr);
end $$;

create function public.admin_cancel_redemption(p_id uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); r public.redemptions; nr public.redemptions;
begin
  select * into r from public.redemptions where id = p_id for update;
  if not found then raise exception 'REDEMPTION_NOT_FOUND'; end if;
  if r.status <> 'pending' then raise exception 'NOT_PENDING'; end if;
  update public.redemptions set status = 'cancelled' where id = p_id returning * into nr;
  insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description, created_by)
  values (r.user_id, r.cost, 'REDEMPTION_REFUND', p_id, 'REDEMPTION_REFUND:' || p_id, 'Refund: redemption cancelled', a)
  on conflict (idempotency_key) do nothing;
  update public.rewards set stock = stock + 1 where id = r.reward_id and stock is not null;
  if r.code_id is not null then
    update public.reward_codes set status = 'available', redemption_id = null, assigned_at = null where id = r.code_id;
  end if;
  insert into public.redemption_events (redemption_id, status, actor, note) values (p_id, 'cancelled', a, coalesce(p_reason, ''));
  perform public.write_audit(a, 'redemption.cancel', 'redemption', p_id::text, to_jsonb(r), jsonb_build_object('reason', p_reason));
  return to_jsonb(nr);
end $$;

create function public.admin_adjust_credits(p_user uuid, p_amount integer, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); p public.profiles; lid uuid := gen_random_uuid();
begin
  if p_amount is null or p_amount = 0 then return jsonb_build_object('ok', false, 'code', 'BAD_AMOUNT'); end if;
  if char_length(btrim(coalesce(p_reason, ''))) = 0 then return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED'); end if;
  select * into p from public.profiles where id = p_user for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'NO_PROFILE'); end if;
  if p.credit_balance + p_amount < 0 then return jsonb_build_object('ok', false, 'code', 'WOULD_GO_NEGATIVE'); end if;
  insert into public.credit_ledger (id, user_id, amount, type, reference_id, idempotency_key, description, created_by)
  values (lid, p_user, p_amount, 'ADMIN_ADJUSTMENT', lid, 'ADMIN_ADJUSTMENT:' || lid, btrim(p_reason), a);
  perform public.write_audit(a, 'credits.adjust', 'profile', p_user::text, jsonb_build_object('balance', p.credit_balance), jsonb_build_object('amount', p_amount, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'balance', p.credit_balance + p_amount);
end $$;

create function public.admin_scan_risk_flags() returns integer language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin(); n1 integer; n2 integer;
begin
  insert into public.risk_flags (user_id, kind, detail)
  select s.user_id, 'IP_CLUSTER', jsonb_build_object('ip_hash', s.ip_hash, 'accounts', c.n)
  from (select distinct user_id, ip_hash from public.client_signals where created_at > now() - interval '24 hours' and user_id is not null) s
  join (select ip_hash, count(distinct user_id) n from public.client_signals where created_at > now() - interval '24 hours' group by 1 having count(distinct user_id) >= 5) c using (ip_hash)
  on conflict (user_id, kind, flagged_on) do nothing;
  get diagnostics n1 = row_count;
  insert into public.risk_flags (user_id, kind, detail)
  select user_id, 'UNIFORM_LATENCY', jsonb_build_object('checkins', n, 'stddev_ms', sd, 'avg_ms', av)
  from (select user_id, count(*) n, stddev_pop(latency_ms) sd, avg(latency_ms) av from public.check_ins group by 1
        having count(*) >= 5 and stddev_pop(latency_ms) < 500 and avg(latency_ms) < 5000) t
  on conflict (user_id, kind, flagged_on) do nothing;
  get diagnostics n2 = row_count;
  perform public.write_audit(a, 'risk.scan', 'risk_flags', null, null, jsonb_build_object('new_flags', n1 + n2));
  return n1 + n2;
end $$;

create function public.admin_review_flag(p_id uuid, p_note text) returns void language plpgsql security definer set search_path = '' as $$
declare a uuid := public.require_admin();
begin
  update public.risk_flags set reviewed_at = now(), reviewed_by = a, review_note = p_note where id = p_id;
  perform public.write_audit(a, 'risk.review', 'risk_flag', p_id::text, null, jsonb_build_object('note', p_note));
end $$;

create function public.ledger_reconciliation() returns table (user_id uuid, cached integer, derived bigint)
language sql stable security definer set search_path = '' as $$
  select p.id, p.credit_balance, coalesce(l.s, 0) from public.profiles p
  left join (select user_id, sum(amount) s from public.credit_ledger group by 1) l on l.user_id = p.id
  where p.credit_balance <> coalesce(l.s, 0) $$;

create function public.admin_stats() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'check_ins', (select count(*) from public.check_ins),
    'credits_issued', (select coalesce(sum(amount), 0) from public.credit_ledger where amount > 0),
    'credits_redeemed', (select coalesce(-sum(amount), 0) from public.credit_ledger where type = 'REWARD_REDEMPTION'),
    'redemptions_pending', (select count(*) from public.redemptions where status = 'pending'),
    'redemptions_pending_over_7d', (select count(*) from public.redemptions where status = 'pending' and created_at < now() - interval '7 days'),
    'open_risk_flags', (select count(*) from public.risk_flags where reviewed_at is null),
    'ledger_mismatches', (select count(*) from public.ledger_reconciliation()));
end $$;

create function public.set_verified_phone(p_user uuid, p_e164 text) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles set phone_e164 = p_e164, phone_verified_at = now() where id = p_user;
  return jsonb_build_object('ok', true);
exception when unique_violation then return jsonb_build_object('ok', false, 'code', 'PHONE_IN_USE');
         when check_violation then return jsonb_build_object('ok', false, 'code', 'PHONE_INVALID');
end $$;

create function public.anonymize_user(p_user uuid) returns void language sql security definer set search_path = '' as $$
  update public.profiles set email = null, display_name = null, phone_e164 = null, phone_verified_at = null, anonymized_at = now() where id = p_user $$;

grant execute on function public.check_in(uuid), public.redeem_reward(uuid, text), public.my_dashboard(), public.update_profile(text, text),
  public.request_data_action(text), public.export_my_data(), public.admin_upsert_round(uuid, text, timestamptz, timestamptz, timestamptz, integer),
  public.admin_round_action(uuid, text), public.admin_upsert_partner(uuid, jsonb), public.admin_upsert_reward(uuid, jsonb),
  public.admin_load_codes(uuid, text[]), public.admin_fulfil_redemption(uuid, text), public.admin_cancel_redemption(uuid, text),
  public.admin_adjust_credits(uuid, integer, text), public.admin_scan_risk_flags(), public.admin_review_flag(uuid, text), public.admin_stats()
  to authenticated;
grant execute on function public.public_round_history(), public.next_round_info() to anon, authenticated;
grant execute on function public.set_verified_phone(uuid, text), public.anonymize_user(uuid), public.ledger_reconciliation() to service_role;

do $$
declare rid uuid; spec record;
begin
  for spec in select * from (values
    ('Demo reward: 1GB data bundle', 'Connectivity', 120, 'code_pool', 'Demo only. Not a real partner offer.'),
    ('Demo reward: 10% meal discount', 'Food', 80, 'code_pool', 'Demo only. Not a real partner offer.'),
    ('Demo reward: shopping voucher', 'Shopping', 150, 'code_pool', 'Demo only. Not a real partner offer.'),
    ('Demo reward: event access', 'Events', 200, 'manual', 'Demo only. An admin will confirm manually.'),
    ('Demo reward: starter course', 'Education', 150, 'manual', 'Demo only. An admin will confirm manually.'),
    ('Demo reward: digital pack', 'Digital', 60, 'code_pool', 'Demo only. Not a real partner offer.'),
    ('Demo reward: service consult', 'Services', 100, 'manual', 'Demo only. An admin will confirm manually.')
  ) as t(title, category, cost, ftype, note)
  loop
    insert into public.rewards (title, description, category, cost, instructions, active, fulfilment_type, is_demo, stock)
    values (spec.title, 'Demo reward. No real partner yet.', spec.category, spec.cost, spec.note, true, spec.ftype, true,
            case when spec.ftype = 'manual' then 25 end) returning id into rid;
    if spec.ftype = 'code_pool' then
      insert into public.reward_codes (reward_id, code)
      select rid, 'DEMO-' || upper(substr(md5(random()::text || g::text), 1, 8)) from generate_series(1, 25) g;
    end if;
  end loop;
end $$;