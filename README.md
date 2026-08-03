# AeroDesk Local

A local-first airline ticketing and travel-agency operations MVP. It includes agency login, dashboard, manual bookings, quotes, customers, reservations, simulated ticket issuance, wallet, ledger, refunds, support cases, users, reports, notifications, and audit history.

## Run

Double-click `start.bat`, or run:

```powershell
npm install
npm start
```

Open <http://localhost:4782>. Demo login: `owner@aerodesk.local` / `AeroDesk2026!`

All records are stored locally in `data/store.json`. Flight inventory and supplier operations are simulated; connect a contracted GDS/NDC/aggregator through the supplier adapter in `server.js` before using real customer funds or issuing real tickets.

## Hosting

See [COOLIFY.md](COOLIFY.md) for the complete Dockerfile deployment, persistent
storage, domain, HTTPS, health-check, and automatic deployment configuration.
