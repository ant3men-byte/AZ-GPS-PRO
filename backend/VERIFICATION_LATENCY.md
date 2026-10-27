# Faster license verification

Apply `migrations/004_verification_activation_time.sql` in Supabase SQL Editor before promoting this branch to `licensing/system`. It adds a numeric epoch `activated_at` to successful verification results, with no table changes. Fresh installations get the same response from schema.sql. Existing activation dates, expiry, revision, device/app binding, challenge consumption and signature checks are preserved. No iOS rebuild or reinstall is needed.

The server uses this field directly and skips the admin Details lookup (including its installations and audit history). Successful challenge + verification now uses 5 database HTTP calls instead of 6. Existing databases without the added field use the previous lookup during rollout/rollback. Invalid provided timestamps are rejected rather than silently accepted. Response signing and the client lease format remain unchanged.

Rollout: run migration 004, confirm Success in Supabase, then deploy the server branch. The old server tolerates the added field, so applying SQL first is backward compatible. Rolling back the server also works without undoing the SQL migration. No speedup in seconds has been measured.

Validation: Node API/crypto tests include exact call sequences for verify/refresh/status, old-database compatibility, rejection and signature preservation. PostgreSQL lifecycle tests run on the fresh schema and again after applying migration 004 twice, checking unchanged activation time and existing replay, device, app, suspension, transfer, expiration and revocation behavior.
