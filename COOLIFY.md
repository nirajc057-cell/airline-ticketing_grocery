# Hosting on Coolify

> **Legacy deployment reference — do not redeploy yet.** This guide and the
> root Dockerfile describe the old Node/web application, not the current
> Flutter + Dart API. The old VPS and its database have not been changed.
> Back up the VPS PostgreSQL database and `/app/data` volume, then prepare a
> replacement deployment and migration before pushing these cleanup changes.

This project is ready to deploy as a Dockerfile application on Coolify.

## Requirements

- A VPS with Coolify installed
- A GitHub repository containing this project
- A PostgreSQL resource in the same Coolify destination as the application
- A domain or subdomain pointed to the VPS (recommended)
- Ports `80` and `443` open on the VPS

Recommended minimum VPS size (the Flutter build is heavier than the Node runtime):

- 2 CPU cores
- 4 GB RAM for builds
- 30 GB storage

## 1. Create the application

1. Sign in to Coolify.
2. Create or select a project.
3. Select the environment where the application should run, such as `production`.
4. Click **New Resource**.
5. Select **Public Repository** if the GitHub repository is public.
6. For a private repository, connect a GitHub App or use a deploy key.
7. Enter the repository URL:

   ```text
   https://github.com/nirajc057-cell/airline-ticketing_grocery.git
   ```

8. Select the `main` branch.

## 2. Configure the build

Use the following application settings:

| Setting | Value |
| --- | --- |
| Build Pack | Dockerfile |
| Base Directory | `/` |
| Dockerfile Location | `/Dockerfile` |
| Port Exposes | `4782` |
| Port Mappings | Leave empty |

The multi-stage Dockerfile builds Flutter web, installs Node production
dependencies, starts Express, and exposes port `4782`. No build command,
Nixpacks configuration, or `.toml` file is required. The Flutter builder image
is large; allow extra build time and disk space on the first deployment.

## 3. Create PostgreSQL and add environment variables

Create and start a **PostgreSQL** resource in the same Coolify project,
environment, and destination as the application. Open its **Configuration >
General** page and copy its **Internal URL**. You do not need to know or paste
your other project's password; Coolify generates this database's credentials.
Keep the database private and use UTF-8 encoding.

Open the application's **Configuration > Environment Variables** and add these
runtime values. Set `DATABASE_URL` to the copied Internal URL in Coolify, mark
it secret/locked, and never commit it to GitHub:

```env
NODE_ENV=production
PORT=4782
STORAGE_DRIVER=postgres
DATABASE_URL=<PostgreSQL Internal URL from Coolify>
```

`NODE_ENV` and `PORT` are also defined in the Dockerfile. `DATABASE_URL` is
required; the server refuses to start without PostgreSQL.

## 4. Configure persistent storage

PostgreSQL is the active store when `DATABASE_URL` is set. Enable persistent
storage and backups on the PostgreSQL resource. If upgrading an existing JSON
deployment, keep its existing `/app/data` volume for the first SQL deployment.
Stop the old app and back up `store.json` first: the new server imports the file
only when SQL is empty, then leaves the JSON file untouched.

For an existing JSON installation, retain this app volume:

| Setting | Value |
| --- | --- |
| Name | `aerodesk-data` |
| Destination Path | `/app/data` |

Do not mount only `/app/data/store.json`. Mount the complete `/app/data`
directory.

For a new installation, no app data volume is needed; the empty SQL database is
initialized with sample records. Run only one application replica because the
SQL compatibility layer preserves the API's whole-document writes. It blocks
a second writer from starting.

## 5. Configure the health check

The application includes a public health endpoint at `/health`.

Use these health-check settings:

| Setting | Value |
| --- | --- |
| Enabled | Yes |
| Method | GET |
| Scheme | HTTP |
| Path | `/health` |
| Port | `4782` |
| Expected status | `200` |

The Dockerfile also contains a container health check, so Coolify can determine
whether the Node.js process is responding.

## 6. Configure the domain and HTTPS

Create an `A` record at the DNS provider:

```text
Type: A
Name: app
Value: YOUR_VPS_PUBLIC_IP
```

In Coolify, set the application domain using the complete HTTPS URL:

```text
https://app.example.com
```

Enable **Force HTTPS**. Coolify will configure its reverse proxy and request a
TLS certificate. Ports `80` and `443` must be publicly reachable.

Do not expose port `4782` through the VPS firewall and do not add a host port
mapping. Coolify's proxy routes public traffic to the container's exposed port.

## 7. Deploy

Save the configuration and click **Deploy**.

During deployment, Coolify will:

1. Clone the `main` branch from GitHub.
2. Build the included Dockerfile.
3. Compile the Flutter web client and install Node production dependencies.
4. Start the application with `npm start`.
5. Route the configured domain to container port `4782`.

After deployment, open the configured domain for the existing web interface,
or `/flutter/` for the new Flutter client. Both use the same API and data.
Keep the existing interface available during the migration: the Flutter client
does not yet cover file uploads, exports/printing, and every specialized
workflow. Android, iOS, and desktop builds are separate artifacts; Coolify
only deploys the Flutter web build.

For a brand-new database initialized from sample records, the demo account is:

```text
Email: owner@aerodesk.local
Password: AeroDesk2026!
```

If you imported an existing `store.json`, use its existing account password
instead. Change or remove demo credentials before using real data.

## 8. Verify persistent storage

After the first successful deployment:

1. Sign in to the application.
2. Create a temporary record.
3. Redeploy the application from Coolify.
4. Confirm that the record still exists. In PostgreSQL mode it is in the
   database resource, not in `/app/data/store.json`.

If it disappears, check `DATABASE_URL`, database health, and database storage.

## 9. Enable automatic deployments

For automatic deployment after every push to `main`:

1. Connect the repository through a Coolify GitHub App.
2. Open the application's **Advanced** settings.
3. Enable **Auto Deploy**.
4. Confirm that the production branch is `main`.

If the application uses the public-repository option instead, configure the
deployment webhook displayed by Coolify in the GitHub repository's webhook
settings.

## 10. Updating the application

Push changes to GitHub:

```bash
git add .
git commit -m "Describe the change"
git push origin main
```

With automatic deployment enabled, Coolify will deploy the new commit. Otherwise,
open the application in Coolify and click **Redeploy**.

## Troubleshooting

### Application returns 502 or 404

- Confirm **Port Exposes** is `4782`.
- Confirm `PORT=4782` is set.
- Check the deployment and runtime logs.
- Confirm the container is healthy.
- Do not set this project as a static site.

### Health check fails

- Confirm the path is `/health`.
- Confirm the health-check port is `4782`.
- Open the container logs and verify that the server started successfully.

The successful response should look like:

```json
{"status":"ok","storage":"postgres"}
```

### Records disappear after redeployment

- Confirm `DATABASE_URL` is available at runtime and the PostgreSQL resource
  has persistent storage.
- Make sure the application is using only one replica.
- Do not use ephemeral preview deployments for production data.

### HTTPS certificate is not issued

- Confirm the domain points to the VPS public IP.
- Ensure ports `80` and `443` are open.
- If Cloudflare proxying is enabled, temporarily switch the DNS record to
  **DNS only**, issue the certificate, and then test proxying again.

### Build fails at `npm ci`

- Confirm both `package.json` and `package-lock.json` are committed.
- Confirm the Dockerfile location is `/Dockerfile`.
- Rebuild without the Coolify build cache if an old dependency layer is being
  reused.

### Flutter web build fails

- Check the first (Flutter builder) stage in the Coolify build logs.
- Ensure the VPS has enough free RAM and disk space for the Flutter SDK and
  web compiler.
- Confirm `flutter_app/pubspec.lock` is committed.
- The Dockerfile pins a published Flutter builder image; update it deliberately
  alongside the project's SDK constraint when upgrading Flutter.

## Backup

Enable PostgreSQL backups and test a restore. Keep a separate copy of the old
`store.json` until the SQL import has been verified.

The SQL schema stores the existing API document in PostgreSQL JSONB and exposes
queryable collection views. It preserves current behavior but is not yet a
fully normalized relational schema; see [backend/README.md](backend/README.md).
