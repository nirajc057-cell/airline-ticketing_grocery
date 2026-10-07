const fs = require('fs');
const path = require('path');

const source = path.resolve(process.argv.find(arg => arg.startsWith('--file='))?.slice(7)
  || path.join(__dirname, '..', 'data', 'store.json'));
const dryRun = process.argv.includes('--dry-run');

async function main() {
  const before = fs.statSync(source);
  const document = JSON.parse(fs.readFileSync(source, 'utf8'));
  if (!document || !Array.isArray(document.users) || !Array.isArray(document.bookings)) {
    throw Error('The source is not an AeroDesk data file.');
  }
  const counts = Object.fromEntries(Object.entries(document)
    .filter(([, value]) => Array.isArray(value))
    .map(([name, value]) => [name, value.length]));
  console.log(`Source: ${source}`);
  console.log('Collections:', counts);
  if (dryRun) return;
  if (!process.env.DATABASE_URL) throw Error('Set DATABASE_URL before importing.');

  const { Client } = require('pg');
  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  let transactionStarted = false;
  try {
    await client.query(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
    await client.query('BEGIN');
    transactionStarted = true;
    const existing = await client.query('SELECT id FROM app_state WHERE id = 1 FOR UPDATE');
    if (existing.rowCount) throw Error('PostgreSQL already contains AeroDesk data; refusing to overwrite it.');
    await client.query('INSERT INTO app_state (id, document) VALUES (1, $1::jsonb)',
      [JSON.stringify(document)]);
    const after = fs.statSync(source);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs) {
      throw Error('The JSON file changed during import. Stop the old server and retry.');
    }
    await client.query('COMMIT');
    transactionStarted = false;
    console.log('Import complete. The original JSON file was not changed.');
  } catch (error) {
    if (transactionStarted) await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
