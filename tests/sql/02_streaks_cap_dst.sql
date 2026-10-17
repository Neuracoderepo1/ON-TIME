-- 02: 7-day milestone (once), cron batch idempotency, streak reset after a missed eligible day,
-- daily cap, DST (America/New_York, 2026-11-01), local-day boundary. Rollback-only.
-- Note: finalize_streaks_batch() uses the real clock, so it is run AFTER the simulated-time check-ins.
do $t$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); un uuid := gen_random_uuid(); un2 uuid := gen_random_uuid();
  d0 date := (now() at time zone 'UTC')::date - 40; i int; rids uuid[] := '{}'; rid uuid; res jsonb; log text := ''; p public.profiles; n int; bal0 int; bal1 int; str0 int; ts timestamptz; ld date;
begin
  insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data,aud,role)
  select x, x::text||'@test.invalid', now(), '{"age_confirmed":true,"consent":true}'::jsonb, 'authenticated','authenticated' from unnest(array[ua,ub,uc]) x;
  insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data,aud,role)
  select x, x::text||'@test.invalid', now(), '{"age_confirmed":true,"consent":true,"timezone":"America/New_York"}'::jsonb, 'authenticated','authenticated' from unnest(array[un,un2]) x;
  update public.profiles set streak_evaluated_through = d0 - 1 where id in (ua,ub,uc);
  update public.profiles set streak_evaluated_through = date '2026-10-30' where id in (un,un2);

  for i in 0..7 loop
    insert into public.rounds (title,start_at,participation_open_at,participation_close_at,credit_award)
    values ('rb day '||i, ((d0+i)::timestamp + interval '10 hours') at time zone 'UTC', ((d0+i)::timestamp + interval '10 hours') at time zone 'UTC', ((d0+i)::timestamp + interval '14 hours') at time zone 'UTC', 10) returning id into rid;
    rids := rids || rid;
  end loop;

  -- ub: check in day 0,1, skip eligible day 2, check in day 3 -> streak resets to 1, longest stays 2
  perform public._check_in_core(ub, rids[1], ((d0)::timestamp + interval '12 hours') at time zone 'UTC');
  perform public._check_in_core(ub, rids[2], ((d0+1)::timestamp + interval '12 hours') at time zone 'UTC');
  res := public._check_in_core(ub, rids[4], ((d0+3)::timestamp + interval '12 hours') at time zone 'UTC');
  select * into p from public.profiles where id=ub;
  log := log || 'reset_after_miss: streak=' || p.current_streak || ' longest=' || p.longest_streak || E'\n';

  -- ua: 7 consecutive days -> bonus once
  for i in 0..6 loop
    ts := ((d0+i)::timestamp + interval '12 hours') at time zone 'UTC';
    res := public._check_in_core(ua, rids[i+1], ts);
  end loop;
  log := log || 'day7_result=' || res::text || E'\n';
  res := public._check_in_core(ua, rids[7], ((d0+6)::timestamp + interval '12 hours') at time zone 'UTC');
  log := log || 'day7_repeat=' || res::text || E'\n';
  select count(*) into n from public.credit_ledger where user_id=ua and type='STREAK_BONUS';
  log := log || 'streak_bonus_rows=' || n || E'\n';

  -- cron batch run twice: balance must not change (streak resets because eligible day d0+7 had no check-in)
  perform public.finalize_streaks_batch();
  select credit_balance, current_streak into bal0, str0 from public.profiles where id=ua;
  perform public.finalize_streaks_batch();
  select credit_balance into bal1 from public.profiles where id=ua;
  select * into p from public.profiles where id=ua;
  log := log || 'cron_second_run: balance ' || bal0 || '->' || bal1 || ' streak ' || str0 || '->' || p.current_streak || E'\n';

  -- daily cap (30): 3 ok, 4th rejected
  for i in 1..4 loop
    insert into public.rounds (title,start_at,participation_open_at,participation_close_at,credit_award)
    values ('rb cap '||i, ((d0+20)::timestamp + interval '10 hours') at time zone 'UTC', ((d0+20)::timestamp + interval '10 hours') at time zone 'UTC', ((d0+20)::timestamp + interval '14 hours') at time zone 'UTC', 10) returning id into rid;
    res := public._check_in_core(uc, rid, ((d0+20)::timestamp + interval '12 hours') at time zone 'UTC');
    log := log || 'cap_' || i || '=' || coalesce(res->>'code','ok') || E'\n';
  end loop;
  select credit_balance, current_streak into bal0, str0 from public.profiles where id=uc;
  log := log || 'cap_final_balance=' || bal0 || ' streak=' || str0 || E'\n';

  for i in 0..2 loop
    ld := date '2026-10-31' + i;
    insert into public.rounds (title,start_at,participation_open_at,participation_close_at,credit_award)
    values ('rb dst '||i, (ld + time '09:00') at time zone 'America/New_York', (ld + time '09:00') at time zone 'America/New_York', (ld + time '17:00') at time zone 'America/New_York', 10) returning id into rid;
    res := public._check_in_core(un, rid, (ld + time '12:00') at time zone 'America/New_York');
  end loop;
  select * into p from public.profiles where id=un;
  log := log || 'dst_streak=' || p.current_streak || ' days=' || (select string_agg(local_day::text, ',' order by local_day) from public.check_ins where user_id=un) || E'\n';

  insert into public.rounds (title,start_at,participation_open_at,participation_close_at,credit_award)
  values ('rb boundary', timestamp '2026-10-31 23:00' at time zone 'America/New_York', timestamp '2026-10-31 23:00' at time zone 'America/New_York', timestamp '2026-11-01 00:30' at time zone 'America/New_York', 10) returning id into rid;
  perform public._check_in_core(un2, rid, timestamp '2026-10-31 23:30' at time zone 'America/New_York');
  log := log || 'boundary_local_day=' || (select local_day::text from public.check_ins where user_id=un2) || E'\n';

  select count(*) into n from public.ledger_reconciliation() where cached <> derived;
  log := log || 'reconciliation_mismatches=' || n || E'\n';
  raise exception E'ROLLBACK_REPORT\n%', log;
end $t$;
