# AeroDesk + FreshMart

The current application is the cross-platform Flutter client in
[flutter_app](flutter_app/README.md), backed by the Dart API and PostgreSQL in
[backend](backend/README.md). The previous browser interface in `public/` has
been removed from this working tree. It was plain HTML/CSS/JavaScript, not
React.

## Run locally

Start the Dart API from `backend` with `npm start` (a PowerShell shortcut for
`dart run bin/server.dart`). In a second terminal, run
`flutter run -d edge --web-port 51046` from `flutter_app`. See the linked
README files for PostgreSQL, emulator, phone, and platform-specific setup.

## Old VPS: do not redeploy yet

The existing VPS has **not** been changed. The root `Dockerfile`,
`COOLIFY.md`, old Node server, and legacy SQL/JSON import scripts still belong
to the previous deployment and are retained for data recovery and migration.
They are **not** the production deployment of the current Flutter + Dart API.
Do not push or redeploy this cleanup to the old VPS until its PostgreSQL and
`/app/data` contents have been backed up and the replacement deployment has
been prepared and tested. Removing source files locally does not delete data
already stored on the VPS.
