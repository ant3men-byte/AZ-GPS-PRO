# Recoverable license codes

Apply `migrations/003_recoverable_license_keys.sql` in the Supabase SQL editor **before deploying this backend**. It is transactional and safe to rerun after migration 002. Existing licenses and activation remain unchanged. No new environment variable is required.

New codes are encrypted with AES-256-GCM and a random 96-bit nonce. A separate encryption key is derived using HKDF-SHA-256 from the existing server-only `LICENSE_KEY_PEPPER` with a dedicated context. The license hash is authenticated as additional data. Preserve the existing pepper: changing or losing it breaks lookup and recovery. Ciphertext lives in a separate RLS-protected table and is never included in list responses, lease responses or audit details.

Creation and encrypted storage commit in one database transaction. Approved administrators can view and copy the full code in Details after reload or signing in again. Each retrieval records a `key_reveal` audit event without the code. Codes created before deployment have no recoverable copy; Details explains this instead of pretending a masked code is usable. Closing the dialog or signing out clears its code field. Codes are not saved in browser storage.

Validation: run `node --test tests/*.test.mjs` and `node --check admin/app.mjs`. In a test database with an approved admin, run `tests/key-retrieval.sql` after the migrations; it rolls back its test data. After deployment, issue a test license, close Details, reload and sign in again, then verify Details shows the same code and the copy button works. Confirm an old license shows the legacy message.
