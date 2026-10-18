
-- ON-TIME targeted RPC privilege hardening.
-- Keep authenticated admin RPC wrappers available so their in-function require_admin()
-- checks continue to protect legitimate administrators. Remove anonymous access.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND p.proname LIKE 'admin\_%' ESCAPE '\'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;

  -- Internal implementation helpers must not be callable directly through the API.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND (
        p.proname LIKE '\_%' ESCAPE '\'
        OR p.proname IN (
          'advance_streak',
          'anonymize_user',
          'consume_rate_limit',
          'hash_ip',
          'require_admin',
          'write_audit',
          'apply_ledger_to_balance'
        )
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $$;

-- Reassert intentional authenticated RPC access while eliminating implicit PUBLIC grants.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'check_in', 'redeem_reward', 'my_dashboard', 'next_round_info',
        'public_round_history', 'update_profile', 'export_my_data',
        'request_data_action', 'set_verified_phone', 'is_admin',
        'is_eligible_day'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;
