# Concurrency and live-path verification — 2026-10-18

Production project `pawhbqfiitrnoksfftzx`, release commit `ede9d06`.

## Method
- 8 dedicated test accounts (`release-test-1..8@example.invalid`, 300 credits each via the audited `admin_adjust_credits` path, profiles back-dated 3 days to clear the 24h new-account hold).
- Tokens obtained by real password sign-in against `/auth/v1/token`; all calls made as `authenticated` JWTs through the production PostgREST endpoint (`/rest/v1/rpc/...`), i.e. the same path the app uses.
- 24 requests dispatched in one batch via `pg_net`; all arrived within the same millisecond (12:50:02.238 UTC).
- A first attempt using parallel tool calls was NOT concurrent (the tool serialises them) and is not counted as evidence.

## Results (all as expected)
| Race | Requests | Outcome | Database ground truth |
|---|---|---|---|
| Same-user check-in | 6 | 1 OK, 5 ALREADY_CHECKED_IN | 1 check-in, 1 ledger row, balance +10 |
| Same-user redeem, 6 different keys | 6 | 1 OK, 5 WEEKLY_LIMIT | 1 redemption, balance -60 |
| Same-user redeem, same key | 6 | 1 created, 5 replays | 1 redemption, 1 ledger debit |
| Stock-1 reward, 3 users x 2 attempts | 6 | 1 OK, 4 OUT_OF_STOCK, 1 WEEKLY_LIMIT | 1 live redemption, stock 0 |
| Refund (admin cancel) | 2 sequential | 1st OK, 2nd NOT_PENDING | 1 refund row, balance restored, stock restored |

Global checks afterwards: 0 balance/ledger mismatches, 0 negative balances, 0 duplicate idempotency keys, `ledger_reconciliation()` returns 0 rows.
Also confirmed: real email/password sign-in works through the production auth API.

## Side effects left in production (test data)
- 8 anonymised, banned test profiles (`auth.users` rows remain; ledger is append-only).
- 2,400 credits of `ADMIN_ADJUSTMENT` ledger rows described "TEST ACCOUNT release verification".
- 4 demo `digital pack` codes consumed (21 remain). One inactive `ZZ TEST stock-1 (internal)` reward and one cancelled `ZZ release test round`.
- `pg_net` extension was installed for the test and could not be dropped by the tooling. `net` is not an exposed API schema (PostgREST returns PGRST106), so it is not client-reachable. Disable it in Dashboard → Database → Extensions.

## Still not covered
Concurrent admin cancel vs. member redemption; multi-instance cron overlap; load beyond 6-way contention; leaked-password protection (Pro plan).
