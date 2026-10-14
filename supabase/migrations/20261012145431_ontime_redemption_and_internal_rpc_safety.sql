-- ON-TIME closure hardening: keep redemption unavailable until a real OTP
-- verification backend exists; the previous direct setter was revoked.
UPDATE public.app_config
SET value = 'false'::jsonb
WHERE key = 'phone_otp_enabled';

-- Explicitly prevent public reads of internal secret/rate-limit tables.
REVOKE ALL ON TABLE public.app_secrets FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.rate_limit_hits FROM PUBLIC, anon, authenticated;

-- Make the eligibility helper internal. This remains callable by trusted
-- SECURITY DEFINER functions owned by the database owner.
REVOKE EXECUTE ON FUNCTION public.is_eligible_day(date,text) FROM PUBLIC, anon, authenticated;

-- Ensure the exposed user-facing authorization predicate is safe for RLS
-- and never callable anonymously.
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- No broad execution of internal profile anonymization or streak advancement.
REVOKE EXECUTE ON FUNCTION public.anonymize_user(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.advance_streak(uuid,timestamptz) FROM PUBLIC, anon, authenticated;
