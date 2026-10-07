const fs = require('fs');
const path = require('path');

const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');

async function openPersistence({ dataFile, seed }) {
  const testJson = process.env.NODE_ENV === 'test' && process.env.STORAGE_DRIVER === 'json-test';
  if (testJson) {
    fs.mkdirSync(path.dirname(dataFile), { recursive: true });
    if (!fs.existsSync(dataFile)) fs.writeFileSync(dataFile, JSON.stringify(seed(), null, 2));
    return {
      driver: 'json',
      data: JSON.parse(fs.readFileSync(dataFile, 'utf8')),
      queueSave(data) { fs.writeFileSync(dataFile, JSON.stringify(data, null, 2)); },
      flush: async () => {},
      ping: async () => {},
    };
  }

  if (!process.env.DATABASE_URL) {
    throw Error('DATABASE_URL is required. Run npm run local:setup and npm run local:start for the local PostgreSQL database.');
  }

  const { Pool } = require('pg');
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 3 });
  pool.on('error', error => {
    console.error('PostgreSQL idle connection error:', error.message);
  });
  let lockClient;
  let queued = Promise.resolve();
  try {
    lockClient = await pool.connect();
    const lock = await lockClient.query('SELECT pg_try_advisory_lock(4782001) AS acquired');
    if (!lock.rows[0].acquired) {
      throw Error('Another AeroDesk server is already using this PostgreSQL database. Run one replica only.');
    }
    await pool.query(schema);
    let result = await pool.query('SELECT document FROM app_state WHERE id = 1');
    if (result.rowCount === 0) {
      const initial = fs.existsSync(dataFile)
        ? JSON.parse(fs.readFileSync(dataFile, 'utf8'))
        : seed();
      await pool.query(
        'INSERT INTO app_state (id, document) VALUES (1, $1::jsonb) ON CONFLICT (id) DO NOTHING',
        [JSON.stringify(initial)],
      );
      result = await pool.query('SELECT document FROM app_state WHERE id = 1');
      console.log(fs.existsSync(dataFile)
        ? 'Imported existing JSON records into PostgreSQL; the JSON file remains untouched.'
        : 'Initialized PostgreSQL with sample records.');
    }
    return {
      driver: 'postgres',
      data: result.rows[0].document,
      queueSave(data) {
        const snapshot = JSON.stringify(data);
        queued = queued.then(() => pool.query(
          'UPDATE app_state SET document = $1::jsonb, revision = revision + 1, updated_at = now() WHERE id = 1',
          [snapshot],
        ));
        // A response awaits flush(); this handler also prevents an unhandled
        // rejection if the database fails between save() and that response.
        queued.catch(() => {});
      },
      flush() { return queued; },
      async ping() { await pool.query('SELECT 1'); },
      async close() {
        await queued;
        await lockClient.query('SELECT pg_advisory_unlock(4782001)');
        lockClient.release();
        await pool.end();
      },
    };
  } catch (error) {
    if (lockClient) lockClient.release();
    await pool.end();
    throw error;
  }
}

module.exports = { openPersistence };
