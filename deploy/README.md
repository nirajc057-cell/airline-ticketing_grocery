# Staged Flutter + Dart deployment (not live yet)

This directory prepares a **new** Coolify Docker Compose application. It does
not replace the old root `Dockerfile` or touch the existing VPS. The web
container serves Flutter and proxies `/api/` to the Dart backend under the
same HTTPS hostname; the Dart backend alone connects to PostgreSQL. No SQL
port or API container port should be published to the Internet.

## Before deployment

1. Confirm which records are authoritative: old VPS PostgreSQL, local
   PostgreSQL, or a carefully reviewed merge. Do not overwrite either source.
2. Back up the old VPS PostgreSQL database **and** its `/app/data` volume.
   Verify the backup can be restored to a separate database. Keep the old
   deployment running while validating the copy.
3. If the source has only the legacy `app_state` table, restore it to a new
   private PostgreSQL database and run the workspace migration there. The
   migration is one-time and refuses to overwrite an existing tenant database.
   Do not run it against the original production database.
4. Confirm the restored database has `tenant_workspaces`, `tenant_state`,
   `tenant_users`, and the expected counts. Only then start the new API.
5. Rotate any account or database password that has appeared in notes,
   screenshots, or chat before public access. Never commit `.env.local`,
   `backend/.local-login.txt`, `test.txt`, or database backups.

The backend deliberately fails to start when workspace data has not been
migrated. The containers do **not** create sample users or migrate records on
startup.

## Coolify staging

Create a **new** Docker Compose application from this repository, using
`deploy/compose.yaml`. Set `DATABASE_URL` as a secret to the restored private
PostgreSQL resource's Internal URL. In **Advanced**, enable **Connect To
Predefined Network** so this Compose application can reach the separate
PostgreSQL resource on the same Coolify destination. Verify the database
hostname in its Internal URL resolves from the `api` container. Expose only
the `web` service through
Coolify's HTTPS domain, initially a staging subdomain. Do not map host ports
for `api` or PostgreSQL. The web service listens on container port `80`.

After deployment, check `https://STAGING-DOMAIN/api/health`, sign in through
the staging website, and verify record counts and real workflows. Test from a
phone on mobile data. Staging data can become stale while the old system keeps
accepting writes. For the final cutover, schedule a short maintenance window,
stop writes to the old app, take a final backup, restore/migrate that final
snapshot, recheck counts, and only then move the production domain. Keep the
old resource available for rollback until the new one is accepted.

Do not push this repository's removal of `public/` to an auto-deploying old
Coolify application before the new deployment is ready. The old Dockerfile
still belongs to that application.

## Native clients

Build native clients against the final HTTPS hostname, for example:

```powershell
cd flutter_app
flutter build apk --release --dart-define=API_BASE_URL=https://app.example.com
flutter build windows --release --dart-define=API_BASE_URL=https://app.example.com
```

Flutter web uses its own hostname as the API base. The Android emulator and
local defaults are not suitable for release devices. Linux builds require a
Linux build environment; iOS builds require macOS/Xcode and Apple signing.
No native build should contain a PostgreSQL password. Installing or
publishing apps is a separate step after the endpoint and signing are ready.

Before distributing Android, replace the template
`com.example.aerodesk_client` application ID and configure a private release
signing key. The current Android project still signs release builds with a
debug key, so a smoke-test APK is **not** a production distribution. iOS
requires a real bundle ID and Apple signing. The current Dart backend rejects
two-factor accounts rather than handling their login, so confirm the account
policy and complete a security review before offering public access.
