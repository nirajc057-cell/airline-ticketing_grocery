-- Separate, SQL-owned workspaces. The original app_state is retained as an
-- unchanged recovery copy; this migration never writes to it.
CREATE TABLE IF NOT EXISTS tenant_workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_state (
  workspace_id uuid PRIMARY KEY REFERENCES tenant_workspaces(id) ON DELETE CASCADE,
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  revision bigint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES tenant_workspaces(id) ON DELETE CASCADE,
  email text NOT NULL,
  display_name text NOT NULL,
  role text NOT NULL DEFAULT 'Agency owner',
  password_hash text NOT NULL,
  password_scheme text NOT NULL CHECK (password_scheme IN ('sha256', 'pbkdf2-sha256')),
  legacy_user_id text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id)
);

CREATE UNIQUE INDEX IF NOT EXISTS tenant_users_email_unique
  ON tenant_users (lower(email));

CREATE TABLE IF NOT EXISTS tenant_sessions (
  token_hash text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES tenant_users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tenant_sessions_user_idx ON tenant_sessions (user_id);

CREATE OR REPLACE VIEW tenant_record_counts AS
SELECT w.name AS workspace, u.email AS owner_email,
  jsonb_array_length(COALESCE(s.document->'bookings', '[]'::jsonb)) AS bookings,
  jsonb_array_length(COALESCE(s.document->'customers', '[]'::jsonb)) AS customers,
  jsonb_array_length(COALESCE(s.document #> '{grocery,products}', '[]'::jsonb)) AS products,
  jsonb_array_length(COALESCE(s.document #> '{grocery,sales}', '[]'::jsonb)) AS grocery_sales
FROM tenant_workspaces w
JOIN tenant_state s ON s.workspace_id = w.id
JOIN tenant_users u ON u.workspace_id = w.id AND u.role = 'Agency owner';
