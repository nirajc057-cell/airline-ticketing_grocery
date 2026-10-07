# Flutter + local PostgreSQL

The Flutter client talks to this Dart API on port `4783`. The API is a network
adapter for PostgreSQL, not a second data store: accounts, login sessions and
workspace records are stored in SQL. The Flutter app does **not** use the old
Node web server or JSON file. A direct Flutter-to-PostgreSQL connection would
expose the database password in every APK/browser build, so the small Dart API
is required for authentication and workspace isolation.

## Start locally on this Windows computer

In PowerShell terminal 1, from the repository root:

```powershell
cd backend
dart pub get
npm start
```

In terminal 2:

```powershell
cd flutter_app
flutter pub get
flutter run -d edge --web-port 51046
```

The `npm start` command is only a shortcut for the Dart server; it does not
run the old Node server. Run it from `backend`, not the repository root. The
same API is used by `flutter run -d windows`. An Android emulator uses
`10.0.2.2:4783`. A physical device needs a build configured with the
computer's LAN address, and the local API would need to bind to that LAN
interface using `API_HOST`. Do not expose HTTP or PostgreSQL to the public
Internet. Use HTTPS when moving to the VPS.

Log in as `owner@aerodesk.local` with the old password to see the old data, or
as `01k@01k.com` to see an empty workspace. The new account's one-time
temporary password is in the gitignored `backend/.local-login.txt`. Change it
immediately after signing in, then remove that file when no longer needed.
Never paste `.env.local` or `.local-login.txt` into chat or commit them.

## SQL migration and recovery

`schema_v2.sql` defines workspace, account, session and JSONB state tables.
`bin/migrate_workspaces.dart` copied the existing `app_state` document into the
old owner's workspace and created a second empty workspace. The legacy
`app_state` row was left untouched for recovery. Do not restart the old Node
server against this database after migration: it would write to that legacy
row instead of the new workspaces. Migration is one-time and
refuses to overwrite existing workspace data. Do not run it again on this
database.

In pgAdmin, connect to `127.0.0.1:55432`, database/user `aerodesk`, with the
password in the local `.env.local` URL. To check isolation:

```sql
SELECT workspace, owner_email, bookings, customers, products, grocery_sales
FROM tenant_record_counts ORDER BY workspace;
```

The new API takes workspace identity only from the authenticated SQL session.
Request bodies cannot choose another workspace. It also holds the same
PostgreSQL advisory lock as the old Node server, so both servers cannot write
the database simultaneously.

## Current scope

Core sign-in, isolated lists and data entry, grocery POS, purchasing, expense
payments, journals and basic account management are in the Dart API. Some
specialized old-web features are not yet ported, including authenticator setup,
uploads, printable/exportable documents, and full accounting reports. The API
returns an error for unsupported two-factor operations rather than silently
disabling security. Do not treat the summary report endpoint as a certified
accounting statement.

Payment method profiles are stored in each workspace's PostgreSQL JSONB state
and served by `/api/payment-methods`. Owners and administrators may manage
profiles; signed-in staff may read them for payment entry. Cash, Bank, eSewa,
and Khalti payments save a copy of the method-specific details on each
transaction, so later profile edits do not alter transaction history. No
separate schema migration is needed for existing workspaces.
