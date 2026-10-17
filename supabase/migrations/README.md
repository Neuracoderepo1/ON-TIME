# Supabase migrations

Mirror of `supabase_migrations.schema_migrations` for project `pawhbqfiitrnoksfftzx` (12 migrations). Each file is byte-identical to the statement recorded in production; verify with `select version, md5(statements[1]) from supabase_migrations.schema_migrations`.

Notes:
- `20261007194602_functions.sql` also seeds 7 **demo rewards** (`is_demo = true`, active, with `DEMO-` codes). Replaying it on a fresh project creates them; deactivate or replace them before opening real redemptions.
- `20261012145431_*` sets `phone_otp_enabled=false` (see `docs/RELEASE_DECISIONS.md`).
- Apply to a fresh or branch project only. Never replay against production.
