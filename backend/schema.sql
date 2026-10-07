-- One authoritative PostgreSQL document preserves the existing API's record
-- structure and transaction semantics during the client migration. The views
-- make each collection queryable with SQL without maintaining a second copy.
CREATE TABLE IF NOT EXISTS app_state (
  id smallint PRIMARY KEY CHECK (id = 1),
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  revision bigint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW airline_bookings AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'bookings', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_customers AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'customers', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_sales AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'sales', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_quotes AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'quotes', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_passport_services AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'passportServices', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_refunds AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'refunds', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_cases AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'cases', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_ledger AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'ledger', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_wallet_transactions AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'walletTransactions', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_users AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'users', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_roles AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'roles', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_audit AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'audit', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_notifications AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'notifications', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_markup_rules AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'markups', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_work_tasks AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'workTasks', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW airline_workspaces AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document->'workspaces', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_products AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,products}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_sales AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,sales}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_suppliers AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,suppliers}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_purchases AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,purchases}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_customers AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,customers}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_expenses AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,expenses}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW grocery_audit AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{grocery,audit}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW finance_adjustments AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{finance,pendingAdjustments}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW finance_reconciliations AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{finance,reconciliations}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;

CREATE OR REPLACE VIEW finance_locked_periods AS
SELECT item.value->>'id' AS id, item.ordinality AS position, item.value AS document
FROM app_state AS state
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(state.document #> '{finance,lockedPeriods}', '[]'::jsonb))
  WITH ORDINALITY AS item(value, ordinality)
WHERE state.id = 1;
