drop function public.advance_streak(uuid);
create function public.advance_streak(p_user uuid, p_now timestamptz default now()) returns void language plpgsql security definer set search_path = '' as $$
declare p public.profiles; d date; today date; cur integer;
begin
  select * into p from public.profiles where id = p_user for update;
  today := (p_now at time zone p.timezone)::date;
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

drop function public._check_in_core(uuid, uuid);
create function public._check_in_core(p_user uuid, p_round uuid, p_now timestamptz default now()) returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.profiles; r public.rounds; ld date; used integer; ns integer; sq integer; bonus integer := 0; b integer; lat integer; s text;
begin
  select * into p from public.profiles where id = p_user and anonymized_at is null for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'NO_PROFILE'); end if;
  perform public.advance_streak(p_user, p_now);
  select * into p from public.profiles where id = p_user;
  select * into r from public.rounds where id = p_round;
  if not found then return jsonb_build_object('ok', false, 'code', 'ROUND_NOT_FOUND'); end if;
  s := case when r.cancelled_at is not null then 'cancelled' when p_now < r.participation_open_at then 'scheduled'
            when p_now < r.participation_close_at then 'open' else 'closed' end;
  if s = 'scheduled' then return jsonb_build_object('ok', false, 'code', 'ROUND_NOT_OPEN'); end if;
  if s in ('closed', 'cancelled') then return jsonb_build_object('ok', false, 'code', 'ROUND_CLOSED'); end if;
  if exists (select 1 from public.check_ins where user_id = p_user and round_id = p_round) then
    return jsonb_build_object('ok', false, 'code', 'ALREADY_CHECKED_IN');
  end if;
  ld := (p_now at time zone p.timezone)::date;
  select coalesce(sum(amount), 0) into used from public.credit_ledger
   where user_id = p_user and type = 'ROUND_PARTICIPATION' and (created_at at time zone p.timezone)::date = ld;
  if used + r.credit_award > public.cfg_int('daily_participation_cap') then
    return jsonb_build_object('ok', false, 'code', 'DAILY_CAP_REACHED');
  end if;
  lat := (extract(epoch from (p_now - r.participation_open_at)) * 1000)::integer;
  insert into public.check_ins (user_id, round_id, checked_in_at, local_day, latency_ms) values (p_user, p_round, p_now, ld, lat);
  insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description, created_at)
  values (p_user, r.credit_award, 'ROUND_PARTICIPATION', p_round, 'ROUND_PARTICIPATION:' || p_round || ':' || p_user, 'Round participation', p_now);
  if public.is_eligible_day(ld, p.timezone) and p.streak_last_day is distinct from ld then
    ns := p.current_streak + 1;
    sq := p.streak_seq + case when p.current_streak = 0 then 1 else 0 end;
    update public.profiles set current_streak = ns, longest_streak = greatest(longest_streak, ns), streak_seq = sq, streak_last_day = ld where id = p_user;
    if ns = 7 then
      insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description, created_at)
      values (p_user, public.cfg_int('streak_bonus_7'), 'STREAK_BONUS', p_round, 'STREAK_BONUS:' || p_user || ':' || sq || ':7', '7-day streak bonus', p_now)
      on conflict (idempotency_key) do nothing returning amount into b;
      if found then bonus := bonus + b; end if;
    elsif ns = 30 then
      insert into public.credit_ledger (user_id, amount, type, reference_id, idempotency_key, description, created_at)
      values (p_user, public.cfg_int('streak_bonus_30'), 'STREAK_BONUS', p_round, 'STREAK_BONUS:' || p_user || ':' || sq || ':30', '30-day streak bonus', p_now)
      on conflict (idempotency_key) do nothing returning amount into b;
      if found then bonus := bonus + b; end if;
    end if;
  end if;
  insert into public.client_signals (user_id, ip_hash, kind, created_at) values (p_user, public.hash_ip(public.request_ip()), 'checkin', p_now);
  select * into p from public.profiles where id = p_user;
  return jsonb_build_object('ok', true, 'awarded', r.credit_award, 'bonus', bonus, 'balance', p.credit_balance,
    'streak', p.current_streak, 'longest_streak', p.longest_streak);
end $$;