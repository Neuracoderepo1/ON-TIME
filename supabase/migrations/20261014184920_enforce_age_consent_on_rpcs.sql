-- Enforce the existing signup age and consent attestations at the server RPC boundary.
-- Keeps authenticated users from bypassing the UI by calling participation/redemption RPCs directly.

CREATE OR REPLACE FUNCTION public.check_in(p_round_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  age_ok boolean;
  consent_ok boolean;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  END IF;

  IF NOT public.consume_rate_limit('ci:u:' || uid, public.cfg_int('rl_checkin_user_per_min'), 60)
     OR NOT public.consume_rate_limit('ci:ip:' || public.hash_ip(public.request_ip()), public.cfg_int('rl_checkin_ip_per_min'), 60) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'RATE_LIMITED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = uid AND email_confirmed_at IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'EMAIL_NOT_VERIFIED');
  END IF;

  SELECT p.age_confirmed_at IS NOT NULL, p.consent_at IS NOT NULL
    INTO age_ok, consent_ok
    FROM public.profiles p
   WHERE p.id = uid AND p.anonymized_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NO_PROFILE');
  END IF;
  IF NOT age_ok THEN
    RETURN jsonb_build_object('ok', false, 'code', 'AGE_CONFIRMATION_REQUIRED');
  END IF;
  IF NOT consent_ok THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CONSENT_REQUIRED');
  END IF;

  RETURN public._check_in_core(uid, p_round_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.redeem_reward(p_reward_id uuid, p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  age_ok boolean;
  consent_ok boolean;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  END IF;

  IF NOT public.consume_rate_limit('rd:u:' || uid, public.cfg_int('rl_redeem_user_per_min'), 60)
     OR NOT public.consume_rate_limit('rd:ip:' || public.hash_ip(public.request_ip()), public.cfg_int('rl_redeem_ip_per_min'), 60) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'RATE_LIMITED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = uid AND email_confirmed_at IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'EMAIL_NOT_VERIFIED');
  END IF;

  SELECT p.age_confirmed_at IS NOT NULL, p.consent_at IS NOT NULL
    INTO age_ok, consent_ok
    FROM public.profiles p
   WHERE p.id = uid AND p.anonymized_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NO_PROFILE');
  END IF;
  IF NOT age_ok THEN
    RETURN jsonb_build_object('ok', false, 'code', 'AGE_CONFIRMATION_REQUIRED');
  END IF;
  IF NOT consent_ok THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CONSENT_REQUIRED');
  END IF;

  RETURN public._redeem_core(uid, p_reward_id, p_idempotency_key);
END
$function$;