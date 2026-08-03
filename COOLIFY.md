# Hosting on Coolify

This project is ready to deploy as a Dockerfile application on Coolify.

## Requirements

- A VPS with Coolify installed
- A GitHub repository containing this project
- A domain or subdomain pointed to the VPS (recommended)
- Ports `80` and `443` open on the VPS

Recommended minimum VPS size:

- 2 CPU cores
- 2 GB RAM
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

The Dockerfile installs production dependencies, starts the Express server, and
exposes port `4782`. No build command, start command, Nixpacks configuration, or
`.toml` file is required.

## 3. Add environment variables

Open **Environment Variables** and add:

```env
NODE_ENV=production
PORT=4782
```

These values are also defined in the Dockerfile, but setting them in Coolify
makes the runtime configuration explicit and allows them to be changed without
editing the image.

## 4. Configure persistent storage

This step is required. The application stores its records in
`data/store.json`. Without a persistent volume, records can be lost when the
container is replaced during a deployment.

Open **Persistent Storage**, add a volume, and use:

| Setting | Value |
| --- | --- |
| Name | `aerodesk-data` |
| Destination Path | `/app/data` |

Do not mount only `/app/data/store.json`. Mount the complete `/app/data`
directory.

The application creates and seeds `store.json` automatically when the volume is
empty.

> Run only one replica of this application. Its JSON file storage is not
> designed for concurrent writes from multiple containers.

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
3. Install dependencies with `npm ci --omit=dev`.
4. Start the application with `npm start`.
5. Route the configured domain to container port `4782`.

After deployment, open the configured domain.

The initial demo account is:

```text
Email: owner@aerodesk.local
Password: AeroDesk2026!
```

Change or remove the demo credentials before using the application with real
data.

## 8. Verify persistent storage

After the first successful deployment:

1. Sign in to the application.
2. Create a temporary record.
3. Redeploy the application from Coolify.
4. Confirm that the record still exists.

If the record disappears, verify that the volume destination is exactly:

```text
/app/data
```

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
{"status":"ok"}
```

### Records disappear after redeployment

- Add persistent storage with destination `/app/data`.
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

## Backup

The persistent volume contains the application's operational data. Back up the
contents of `/app/data`, especially `store.json`, before server migrations or
major application changes.

For production use, migrate the JSON file to a managed database such as
PostgreSQL and configure automated off-server backups.
