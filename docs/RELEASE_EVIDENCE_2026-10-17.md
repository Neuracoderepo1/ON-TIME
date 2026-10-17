# ON-TIME release evidence — 2026-10-17

Project `pawhbqfiitrnoksfftzx` (eu-west-1). Production deployment `dpl_J7Kb72fbKiRQMoEHf5YtPubrEScF`, commit `d9e5f9e`, READY.

## Phase A — baseline
- 12 migrations applied in production; all 12 are tracked in `supabase/migrations/` (this PR, md5-verified earlier against `schema_migrations`).
- 18 public tables, RLS enabled on all. Client grants are SELECT-only (anon: `partners`, `rewards`, `rounds`). `app_secrets` and `rate_limit_hits` have no client grants.
- 41 public functions, all with `search_path=""`. anon can execute only `request_ip` and `round_status`.
- Not enabled: FORCE RLS. Table owner is a BYPASSRLS role and all writes go through SECURITY DEFINER functions, so FORCE would add no protection. Direct client writes are blocked by grants.

## Phase B — 20 advisor findings (lint 0029), all dispositioned
| Class | Functions | Disposition |
|---|---|---|
| Admin-only (11) | admin_adjust_credits, admin_cancel_redemption, admin_fulfil_redemption, admin_load_codes, admin_review_flag, admin_round_action, admin_scan_risk_flags, admin_stats, admin_upsert_partner, admin_upsert_reward, admin_upsert_round | Accepted. The dashboard calls them with the admin's JWT, so `authenticated` must keep EXECUTE. Each calls `require_admin()` first. |
| Member (7) | check_in, redeem_reward, update_profile, my_dashboard, export_my_data, request_data_action, is_admin | Accepted. Identity comes from `auth.uid()`; no user-id parameter. |
| Authenticated read (2) | next_round_info, public_round_history | Accepted. Non-sensitive aggregates. |

Static review: no dynamic SQL in any of them. Behavioural test (rollback-only, 2026-10-17):
- anon: 42501 on all 40 non-public functions tried (admin, internal, member).
- non-admin member (`is_admin()=false`): all 11 admin RPCs return `FORBIDDEN`; all internal functions 42501.
- direct writes as member denied (42501): update `profiles.credit_balance`, insert `credit_ledger`, insert/delete `check_ins`, write `user_roles`, read `app_secrets`/`rate_limit_hits`, update `rewards`.
- admin: `admin_stats`, `admin_scan_risk_flags` succeed; internal `require_admin()` denied.
No grant change was needed. The advisor will keep listing these 20 warnings by design.

## Phase C — leaked-password protection: BLOCKED (action needed)
Still reported disabled by the security advisor. The available tools cannot change Auth settings, and HaveIBeenPwned checking is a Pro-plan feature. Action: Supabase Dashboard → Authentication → Sign In / Providers → Email → enable "Prevent use of leaked passwords" (owner/admin permission; Pro plan or above). Until then rely on the minimum-length policy.

## Phase D — credit invariants
Rule: the daily cap (`daily_participation_cap`, 30) counts only `ROUND_PARTICIPATION` credits per local day. Streak bonuses (`STREAK_BONUS`) are separate ledger rows keyed `STREAK_BONUS:<user>:<seq>:<n>`; they sit on top of the cap and can fire once per streak.
Concurrency primitives: per-user `profiles ... FOR UPDATE` serialises check-in/streak/cap; `unique(user_id, round_id)` on check-ins; unique ledger `idempotency_key`; redemption `unique(user_id, idempotency_key)`; reward row `FOR UPDATE`; codes `FOR UPDATE SKIP LOCKED`; refunds lock the redemption row and are keyed.
Rollback tests in `tests/sql/` cover single-session behaviour (duplicate, cap, DST, replay, sold-out, refund, reconciliation = 0 mismatches).
**Gap:** multi-connection races were NOT executed. They need an isolated database (branching/second project is unavailable on the current plan). The guarantee above rests on design review only.

## Phase E — secrets
No `service_role`/`sb_secret` keys or JWT-shaped tokens in repo, git history or the built bundle (the only match is supabase-js's own key-prefix check). The app reads only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Vercel env var values could not be inspected (connector returns 403 for the team scope).

## Phase G — local gate (this branch)
typecheck, lint, 21 unit tests, `npm audit` (0 vulnerabilities), build, 12 e2e (desktop + mobile): all pass.
