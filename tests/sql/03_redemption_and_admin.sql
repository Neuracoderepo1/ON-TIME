-- 03: redemption success/replay/limits/sold-out/insufficient/code-pool, member denial of admin RPCs,
-- admin cancel + refund + stock restore, ledger reconciliation, audit trail. Rollback-only.
do $t$
declare
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); uc uuid := gen_random_uuid(); ud uuid := gen_random_uuid(); adm uuid := gen_random_uuid();
  rm uuid; rcp uuid; res jsonb; log text := ''; bal int; stk int; n int; n2 int; k1 text := 'rb-key-'||gen_random_uuid(); red uuid; avail int;
begin
  insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data,aud,role)
  select x, x::text||'@test.invalid', now(), '{"age_confirmed":true,"consent":true}'::jsonb, 'authenticated','authenticated' from unnest(array[ua,ub,uc,ud,adm]) x;
  update public.profiles set created_at = now() - interval '3 days' where id in (ua,ub,uc,ud,adm);
  insert into public.credit_ledger (user_id, amount, type, idempotency_key, description, created_by) values
    (ua,100,'ADMIN_ADJUSTMENT','rbfix:'||ua,'fix',adm),(ub,100,'ADMIN_ADJUSTMENT','rbfix:'||ub,'fix',adm),(uc,10,'ADMIN_ADJUSTMENT','rbfix:'||uc,'fix',adm),(ud,200,'ADMIN_ADJUSTMENT','rbfix:'||ud,'fix',adm);
  insert into public.user_roles (user_id, role) values (adm,'admin');
  insert into public.rewards (title,category,cost,stock,fulfilment_type,active,is_demo) values ('rb manual','Digital',50,1,'manual',true,true) returning id into rm;
  insert into public.rewards (title,category,cost,stock,fulfilment_type,active,is_demo) values ('rb codes','Digital',30,null,'code_pool',true,true) returning id into rcp;
  insert into public.reward_codes (reward_id, code) values (rcp,'RB-CODE-1'),(rcp,'RB-CODE-2');

  perform set_config('request.jwt.claims', json_build_object('sub', ua,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
  res := public.redeem_reward(rm, k1);  log := log || 'redeem_ok=' || (res->>'ok') || ' replay=' || (res->>'replay') || ' status=' || (res->'redemption'->>'status') || E'\n';
  res := public.redeem_reward(rm, k1);  log := log || 'redeem_replay_ok=' || (res->>'ok') || ' replay=' || (res->>'replay') || E'\n';
  res := public.redeem_reward(rm, 'rb-key-'||gen_random_uuid()); log := log || 'redeem_second_new_key=' || coalesce(res->>'code','ok') || E'\n';
  perform set_config('role','postgres',true);
  select credit_balance into bal from public.profiles where id=ua; select stock into stk from public.rewards where id=rm;
  select count(*) into n from public.credit_ledger where user_id=ua and type='REWARD_REDEMPTION'; select count(*) into n2 from public.redemptions where user_id=ua;
  log := log || 'ua balance=' || bal || ' stock=' || stk || ' redemption_ledger_rows=' || n || ' redemptions=' || n2 || E'\n';

  perform set_config('request.jwt.claims', json_build_object('sub', ub,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
  res := public.redeem_reward(rm, 'rb-key-'||gen_random_uuid()); log := log || 'sold_out=' || coalesce(res->>'code','ok') || E'\n';
  perform set_config('role','postgres',true);
  select credit_balance into bal from public.profiles where id=ub; select count(*) into n from public.credit_ledger where user_id=ub and type='REWARD_REDEMPTION'; select count(*) into n2 from public.redemptions where user_id=ub;
  log := log || 'ub balance=' || bal || ' ledger_rows=' || n || ' redemptions=' || n2 || E'\n';

  perform set_config('request.jwt.claims', json_build_object('sub', uc,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
  res := public.redeem_reward(rcp, 'rb-key-'||gen_random_uuid()); log := log || 'insufficient=' || coalesce(res::text,'null') || E'\n';
  perform set_config('role','postgres',true);

  perform set_config('request.jwt.claims', json_build_object('sub', ud,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
  res := public.redeem_reward(rcp, 'rb-key-'||gen_random_uuid()); log := log || 'codepool_status=' || (res->'redemption'->>'status') || ' has_code=' || ((res->'redemption'->>'fulfilment_ref') is not null)::text || E'\n';
  select count(*) into n from public.reward_codes; log := log || 'member_visible_reward_codes=' || n || E'\n';
  perform set_config('role','postgres',true);
  select count(*) into avail from public.reward_codes where reward_id=rcp and status='available'; select credit_balance into bal from public.profiles where id=ud;
  log := log || 'codes_available=' || avail || ' ud_balance=' || bal || E'\n';

  perform set_config('request.jwt.claims', json_build_object('sub', ub,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
  begin perform public.admin_cancel_redemption((select id from public.redemptions limit 1), 'x'); log := log || 'member_cancel=FAIL' || E'\n'; exception when others then log := log || 'member_cancel=denied(' || sqlerrm || ')' || E'\n'; end;
  perform set_config('role','postgres',true);

  select id into red from public.redemptions where user_id=ua;
  perform set_config('request.jwt.claims', json_build_object('sub', adm,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
  res := public.admin_cancel_redemption(red, 'rb test'); log := log || 'admin_cancel_status=' || (res->>'status') || E'\n';
  begin perform public.admin_cancel_redemption(red, 'again'); log := log || 'double_cancel=FAIL' || E'\n'; exception when others then log := log || 'double_cancel=denied(' || sqlerrm || ')' || E'\n'; end;
  begin perform public.admin_cancel_redemption((select id from public.redemptions where user_id=ud), 'x'); log := log || 'cancel_fulfilled=FAIL' || E'\n'; exception when others then log := log || 'cancel_fulfilled=denied(' || sqlerrm || ')' || E'\n'; end;
  res := public.admin_stats(); log := log || 'admin_stats_ledger_mismatches=' || (res->>'ledger_mismatches') || E'\n';
  perform set_config('role','postgres',true);
  select credit_balance into bal from public.profiles where id=ua; select stock into stk from public.rewards where id=rm; select count(*) into n from public.credit_ledger where user_id=ua and type='REDEMPTION_REFUND';
  log := log || 'after_cancel ua balance=' || bal || ' stock=' || stk || ' refund_rows=' || n || E'\n';
  select count(*) into n from public.ledger_reconciliation() where cached <> derived; log := log || 'reconciliation_mismatches=' || n || E'\n';
  select count(*) into n from public.audit_log where actor_id=adm; log := log || 'audit_rows_for_admin=' || n || E'\n';
  raise exception E'ROLLBACK_REPORT\n%', log;
end $t$;
