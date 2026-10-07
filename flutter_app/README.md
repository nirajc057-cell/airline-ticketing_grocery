# AeroDesk & FreshMart Flutter client

This Flutter app uses the Dart API in `../backend`, backed only by PostgreSQL.
It does not call the old Node server or read JSON files. Workspace data is
selected from the SQL login session: the old owner sees the existing records,
and `01k@01k.com` starts with no business records.

## Run locally

Start the SQL API in terminal 1 as described in `../backend/README.md`.
Then, in terminal 2:

```powershell
cd flutter_app
flutter pub get
flutter run -d edge --web-port 51046
```

For Windows desktop use `flutter run -d windows`. The browser, desktop app,
and Android emulator use the Dart API on port `4783` by default; no server
address needs to be entered on the login screen. A real phone cannot use the
computer's `127.0.0.1` address, so a phone build needs your computer's LAN
address supplied with `--dart-define=API_BASE_URL=http://YOUR-LAN-IP:4783`
and the backend must bind to that LAN interface. Do not expose the local HTTP
service to the Internet. Later VPS builds should use an HTTPS API URL via
`--dart-define=API_BASE_URL=https://your-domain`.

The Table feature adds CSV file import/export plugins. On Windows, Flutter
needs Developer Mode enabled to create plugin symlinks before running
`flutter pub get` or building the desktop app.

## FreshMart point of sale and barcode scanner

Out-of-stock products are hidden from the sale catalog. When a sale has no
items, the cart shows only a start prompt; totals, discount/tax controls, and
checkout appear after the first item is added. The existing checkout and
payment flow is unchanged.

Use a USB or Bluetooth scanner configured as a **HID keyboard** with an
**Enter/Return suffix**. Connect or pair it with the device, then focus the
**Scan barcode** box in FreshMart → Point of sale and scan. The app matches
the complete barcode exactly (including leading zeros) to one active product
and adds one unit per scan, subject to stock. The box clears and refocuses
after each scan. The same box supports typing a barcode and pressing Enter.
You can still search by name, SKU, or barcode and tap products manually.

Set each product's barcode in Products & inventory; barcodes should be unique.
Unknown, duplicate, and out-of-stock scans show a message and do not add an
item. Use the help icon next to the scan box for setup steps. Scanner models
that expose only a serial/COM interface require switching to their HID
keyboard mode; this app does not open serial ports or install scanner drivers.

The POS rounds the final payable amount to the nearest whole rupee by
default (0.50 rounds up). The **Round-off** row shows the signed adjustment:
for example, 16.32 becomes 16.00 with -0.32 shown. Turn the switch off to
charge the exact two-decimal amount. The backend recalculates the choice and
saves both the pre-rounding amount and adjustment with the sale; the payment
must match the final total. Restart the backend after upgrading both apps.

## Table screen

On a phone, tap **Table** in the bottom bar. On a wide screen, use **Table** in
the sidebar. Select **Create table**, enter its sidebar name, row count,
column count, and optional header names. There are no preset headers in custom
tables; blank headings can be named later by long-pressing the header or using
**Name Header**. Each new table appears beneath **Table** in the sidebar.
Tables can be renamed or deleted, with deletion confirmation. Use **Save** to
persist cell and header edits to the signed-in PostgreSQL workspace. AeroDesk
and FreshMart tables are separate.

The table toolbar keeps **Add Row**, **Add Column**, search, filter, and **Save**
visible. **Import / Export** contains the CSV actions, while **Table options**
contains rename and delete. Click a row number, column header, or cell to see
actions for that selection; on narrow screens, open **Row actions**, **Column
actions**, or **Cell actions**. Tap a cell once and type directly inside it.
**Enter** adds a new line in that cell; **Next row** opens the cell below in
the same column. Select another cell or **Save** when finished.
The **Edit cell** action is still available as an optional larger editor for
longer text.

Row and column actions include deleting and coloring. Open the **three-dot
menu** beside a row number to color that row, set or edit its notification,
duplicate it, or delete it. The **Set notification** toolbar button also works
after selecting a row or cell. Select **Save** after changing a row.
Once due, the alert appears
in **Table alerts** on that workspace's dashboard and remains there until
dismissed. The dashboard refreshes alerts while open; if the app was closed,
overdue alerts appear when the dashboard is opened again. These are dashboard
alerts, not operating-system push notifications.

The previous booking/product spreadsheet remains available through **Open
linked booking spreadsheet** or **Open linked product spreadsheet** on the
Table landing screen. Existing bookings/products are not changed by creating
or deleting a custom table. That linked spreadsheet still uses its original
setup flow and built-in business columns.

Blank or incomplete rows are drafts. Use **Save** to keep drafts; once all
required fields are filled, saving creates a normal booking/product record.
The toolbar also supports filtering, sorting, copy/paste, CSV import and CSV
export. Imports are drafts until saved. Deletion is blocked for paid/ticketed
bookings and products with stock or linked transactions. Table data and drafts
are stored in the signed-in PostgreSQL workspace through the existing local
Dart API, not in a second on-device database.

## Custom form fields

Agency owners and administrators can use **Manage form fields** on AeroDesk and
FreshMart record screens, or the tune icon inside a form, to add, rename,
reorder, remove, and restore fields. This includes bookings, passport services
and collection, refunds, customers, direct sales, support cases, employees,
products, suppliers, expenses, and purchase-order headers. Settings and field
values are saved in the current PostgreSQL workspace. Deleting a field also
permanently deletes its values from existing records; restoring a built-in
field does not restore those values. Core fields needed for authentication,
payments, inventory calculations, or workflow identity cannot be removed.
Payment splits, purchase line items, role permissions, and accounting entries
retain their fixed operational controls.

## Payment methods

Open **Payment methods** from either AeroDesk or FreshMart's sidebar. Owners
and administrators can save Cash, Bank, eSewa, and Khalti profiles for the
current workspace. Bank profiles store the bank, account holder, account
number, and branch; digital-wallet profiles store the registered wallet
number and account name. Existing workspaces start with no saved profiles.

When recording a payment, enter each method's amount. Bank and digital-wallet
payments then ask for their relevant details and an optional transaction
reference. Select a saved profile to prefill those details or enter them
manually. Cash requires no bank or wallet details. Split payments remain
supported; the amounts must add up to the required total for a sale, while
booking, supplier, and expense payments can be partial. Each completed
transaction stores a snapshot of its payment details, so changing or deleting
a saved profile does not rewrite past payments. The profiles and transactions
are stored in the signed-in PostgreSQL workspace through the local Dart API.

Use the old owner's known password for `owner@aerodesk.local`. The temporary
password for the new empty workspace is in `../backend/.local-login.txt`.
Change it on first login; that file is gitignored.

## Supported platforms

Flutter targets Web, Android, iOS, Windows, Linux and macOS. Build iOS/macOS
on macOS with Xcode, and Linux on Linux with the Flutter desktop prerequisites.
Android release signing and app IDs must be configured before distribution.
The local development API uses HTTP; mobile release builds must use HTTPS.

The app contains responsive screens for travel and grocery modules. Some
specialized workflows (authenticator setup, uploads, exports/printing and
complete financial statements) are still being migrated from the old app.
The current SQL-backed Flutter client should not be represented as having
complete functional/UI parity yet.
