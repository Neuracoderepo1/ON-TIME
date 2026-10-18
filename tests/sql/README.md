# Database tests (rollback-only)

Each script builds its own fixtures (auth users, rounds, rewards), exercises the deployed RPCs, then ends with
`RAISE EXCEPTION 'ROLLBACK_REPORT ...'`. That exception rolls the whole transaction back, so **nothing persists**; the
"error" text is the test report. Run with `psql -f` or the Supabase SQL editor / MCP `execute_sql`.

Do not remove the final `RAISE EXCEPTION`. These scripts are for a dev/test project; they were run against production
only because no isolated project was available, and verified to leave row counts unchanged.

Not covered here: true multi-connection concurrency (50 parallel check-ins, parallel redemptions on limited stock,
parallel use of one idempotency key). That needs an isolated project with committed fixtures.
