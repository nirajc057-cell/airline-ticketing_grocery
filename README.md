# AeroDesk Local

A local-first airline ticketing and travel-agency operations MVP. It includes agency login, dashboard, flight shopping, quotes, customers, reservations, simulated ticket issuance, wallet, ledger, refunds, support cases, users, markup rules, reports, notifications, and audit history.

## Run

Double-click `start.bat`, or run:

```powershell
npm install
npm start
```

Open <http://localhost:4782>. Demo login: `owner@aerodesk.local` / `AeroDesk2026!`

All records are stored locally in `data/store.json`. Flight inventory and supplier operations are simulated; connect a contracted GDS/NDC/aggregator through the supplier adapter in `server.js` before using real customer funds or issuing real tickets.
