-- Close direct RPC privilege escalation paths discovered in live review.
-- Phone verification must only be set by a trusted OTP-verification backend,
-- not by a client-supplied user ID.
REVOKE EXECUTE ON FUNCTION public.set_verified_phone(uuid,text) FROM PUBLIC, anon, authenticated;
-- Reconciliation returns profile IDs and balances; keep it internal to trusted ops.
REVOKE EXECUTE ON FUNCTION public.ledger_reconciliation() FROM PUBLIC, anon, authenticated;
-- Eligibility is an internal streak rule and should not be an exposed RPC.
REVOKE EXECUTE ON FUNCTION public.is_eligible_day(date,text) FROM PUBLIC, anon, authenticated;
