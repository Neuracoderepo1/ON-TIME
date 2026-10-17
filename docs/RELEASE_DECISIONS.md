# Release decisions

## MVP exception: email-only redemption (no phone verification)

**Status:** accepted by the product owner for the MVP. This is a deliberate exception, **not** full compliance with the original requirement that redemption needs a verified E.164 phone number.

Live configuration (verified in `app_config`): `phone_otp_enabled=false`, `redemption_hold_hours=24`, `weekly_redemption_cap_no_phone=1`.

Controls that apply instead:
- Email must be confirmed before check-in or redemption.
- New accounts wait 24 hours before their first redemption.
- Members without a verified phone are limited to one redemption per rolling 7 days.
- Risk flags and server-side redemption authorisation remain enforced; `set_verified_phone` is not callable by clients.

User-facing copy that discloses this: Rewards page notice, Account page, and Eligibility page (`src/pages/Legal.tsx`).

**Reversal condition:** if phone verification is a non-negotiable launch requirement, redemption must stay unavailable until an OTP provider is configured and tested, then `phone_otp_enabled` may be set to `true`.

## Age verification
18+ is an attestation (checkbox) enforced server-side at signup and, since migration `20261014184920`, inside `check_in` and `redeem_reward`. There is no date-of-birth or identity check.

## Production branch
`feat/on-time-app` is the production branch. The default branch (`preflight-test`) is unchanged until migration reconciliation is complete.

## Migrations
`supabase/migrations/` mirrors `supabase_migrations.schema_migrations` in project `pawhbqfiitrnoksfftzx`. Each file is byte-identical to the statement recorded there (verify with `md5(statements[1])`).
