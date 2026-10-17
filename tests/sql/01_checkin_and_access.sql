-- 01: signup gate, check-in outcomes, RLS isolation, direct-mutation and privilege denial. Rollback-only.
do $t$
declare
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
  r1 uuid; r2 uuid; res jsonb; bal int; n int; rw uuid; k text;
  log text := '';
begin
  insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role)
  values (u1, 'rb1@test.invalid', now(), '{"age_confirmed":true,"consent":true,"timezone":"Africa/Accra"}', 'authenticated', 'authenticated'),
         (u2, 'rb2@test.invalid', now(), '{"age_confirmed":true,"consent":true}', 'authenticated', 'authenticated');
  select count(*) into n from public.profiles where id in (u1,u2);
  log := log || 'profiles_created_by_trigger=' || n || E'\n';

  begin
    insert into auth.users (id, email, raw_user_meta_data, aud, role) values (gen_random_uuid(), 'rb3@test.invalid', '{}', 'authenticated','authenticated');
    log := log || 'age_gate=FAIL(no exception)' || E'\n';
  exception when others then log := log || 'age_gate=ok(' || sqlerrm || ')' || E'\n'; end;

  insert into public.rounds (title, start_at, participation_open_at, participation_close_at, credit_award)
  values ('rb open', now(), now() - interval '5 min', now() + interval '55 min', 10) returning id into r1;
  insert into public.rounds (title, start_at, participation_open_at, participation_close_at, credit_award)
  values ('rb future', now()+interval '2 hour', now() + interval '2 hour', now() + interval '3 hour', 10) returning id into r2;

  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role','authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  res := public.check_in(r1);  log := log || 'checkin_valid=' || res::text || E'\n';
  res := public.check_in(r1);  log := log || 'checkin_duplicate=' || res::text || E'\n';
  res := public.check_in(r2);  log := log || 'checkin_not_open=' || res::text || E'\n';
  res := public.check_in(gen_random_uuid()); log := log || 'checkin_unknown_round=' || res::text || E'\n';

  select credit_balance into bal from public.profiles where id = u1;
  log := log || 'balance_after=' || bal || E'\n';

  select count(*) into n from public.credit_ledger where user_id = u2;
  log := log || 'cross_user_ledger_rows_visible=' || n || E'\n';
  select count(*) into n from public.profiles;
  log := log || 'profiles_visible_to_u1=' || n || E'\n';

  begin update public.profiles set credit_balance = 999999 where id = u1; get diagnostics n = row_count; log := log || 'direct_balance_update=rows:' || n || E'\n';
  exception when others then log := log || 'direct_balance_update=denied(' || sqlerrm || ')' || E'\n'; end;
  begin insert into public.credit_ledger (user_id, amount, type, idempotency_key) values (u1, 500, 'ADMIN_ADJUSTMENT', 'x'||gen_random_uuid());
    log := log || 'direct_ledger_insert=FAIL(allowed)' || E'\n';
  exception when others then log := log || 'direct_ledger_insert=denied(' || sqlerrm || ')' || E'\n'; end;
  begin perform public.admin_adjust_credits(u1, 100, 'x'); log := log || 'admin_rpc_as_member=FAIL(allowed)' || E'\n';
  exception when others then log := log || 'admin_rpc_as_member=denied(' || sqlerrm || ')' || E'\n'; end;
  begin perform public._check_in_core(u1, r1); log := log || 'internal_core_as_member=FAIL(allowed)' || E'\n';
  exception when others then log := log || 'internal_core_as_member=denied(' || sqlerrm || ')' || E'\n'; end;

  select id into rw from public.rewards where title like '%digital pack%';
  k := 'rb-key-' || gen_random_uuid();
  res := public.redeem_reward(rw, k); log := log || 'redeem_new_account=' || res::text || E'\n';
  res := public.redeem_reward(rw, 'short'); log := log || 'redeem_bad_key=' || res::text || E'\n';

  perform set_config('role', 'postgres', true);
  raise exception E'ROLLBACK_REPORT\n%', log;
end $t$;
