# ON-TIME backend contracts (read from the deployed Supabase project, 2026-10-13)

Project `pawhbqfiitrnoksfftzx` (eu-west-1). Contracts below come from `pg_get_functiondef`, not from names.

## Member RPCs (authenticated; `auth.uid()` is taken from the JWT, never a parameter)
| RPC | Args | Returns |
|---|---|---|
| `my_dashboard()` | none | jsonb `{balance, streak, longest_streak, timezone, display_name, phone_verified, rounds_participated, activity[20], redemptions[50]}`; `null` if unauthenticated |
| `next_round_info()` | none | jsonb round `{id,title,start_at,participation_open_at,participation_close_at,credit_award,status,server_now}` or `null` |
| `check_in(p_round_id uuid)` | round id | `{ok:true,awarded,bonus,balance,streak,longest_streak}` or `{ok:false,code}` (codes: NOT_AUTHENTICATED, RATE_LIMITED, EMAIL_NOT_VERIFIED, NO_PROFILE, ROUND_NOT_FOUND, ROUND_NOT_OPEN, ROUND_CLOSED, ALREADY_CHECKED_IN, DAILY_CAP_REACHED) |
| `redeem_reward(p_reward_id uuid, p_idempotency_key text)` | key must be 8–100 chars | `{ok:true,replay,redemption{...}}` or `{ok:false,code[,needed|available_at]}` (PHONE_REQUIRED, WEEKLY_LIMIT, NEW_ACCOUNT_HOLD, REWARD_UNAVAILABLE, OUT_OF_STOCK, INSUFFICIENT_CREDITS, BAD_IDEMPOTENCY_KEY, …) |
| `update_profile(p_display_name, p_timezone)` | validated against `pg_timezone_names` | `{ok:true}` / `{ok:false,code}` |
| `public_round_history()` | none | table of past rounds with masked participation counts |
| `export_my_data()`, `request_data_action(p_kind)` | | own data export / deletion request |

## Direct table reads (RLS)
`rounds`, `rewards` (active only, active partner), `partners` (active) are readable by anon and authenticated.
`check_ins`, `credit_ledger`, `redemptions`, `profiles`, `data_requests` are readable only for the caller's own rows (admins read all).
`reward_codes`, `partner_contacts`, `audit_log`, `risk_flags`, `client_signals` are admin-only. `app_secrets` and `rate_limit_hits` deny all client access.
No table has INSERT/UPDATE/DELETE grants for `anon` or `authenticated`.

## Signup / eligibility
`on_auth_user_created` → `handle_new_user()` creates the profile and **raises** `AGE_CONFIRMATION_REQUIRED` / `CONSENT_REQUIRED` unless the signup metadata carries `age_confirmed` and `consent` = true. This is server-side enforcement of an **attestation**; there is no date-of-birth or identity verification. `check_in` and `redeem_reward` additionally require a confirmed email. `phone_otp_enabled=false`, so redemptions fall back to: 1 per rolling 7 days and a 24h new-account hold. This is an accepted MVP exception; see `docs/RELEASE_DECISIONS.md`.

## Admin RPCs
All 11 `admin_*` functions call `require_admin()` (checks `user_roles` for the JWT user) as the first statement. `user_roles` has no client write grants. Admin is granted only by a database owner inserting a `user_roles` row.

## Streaks / cron
`pg_cron` job `ontime-finalize-streaks` runs `select public.finalize_streaks_batch();` every 15 minutes. It calls `advance_streak(user, clock_timestamp())` for each profile.

## Not in the backend (gaps)
- Rounds have no `description` column, so the UI shows title/time/credits only.
- No server-side phone OTP provider is configured.
