-- ON-TIME focused security grant hardening
-- Keep authenticated admin RPCs available because each calls require_admin();
-- remove direct anonymous access to privileged RPCs and direct client execution
-- of internal SECURITY DEFINER helpers.
REVOKE EXECUTE ON FUNCTION public._check_in_core(uuid,uuid,timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._redeem_core(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.require_admin() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.write_audit(uuid,text,text,text,jsonb,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.advance_streak(uuid,timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.anonymize_user(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cfg_bool(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cfg_int(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.consume_rate_limit(text,integer,integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.hash_ip(text) FROM PUBLIC, anon, authenticated;

-- Administrative RPCs remain callable only by authenticated sessions; their
-- implementations invoke require_admin() before performing privileged work.
REVOKE EXECUTE ON FUNCTION public.admin_adjust_credits(uuid,integer,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_cancel_redemption(uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_fulfil_redemption(uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_load_codes(uuid,text[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_review_flag(uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_round_action(uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_scan_risk_flags() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_stats() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_partner(uuid,jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_reward(uuid,jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_round(uuid,text,timestamptz,timestamptz,timestamptz,integer) FROM PUBLIC, anon;

-- Ensure the day-eligibility helper remains STABLE, not IMMUTABLE.
ALTER FUNCTION public.is_eligible_day(date,text) STABLE;
