const Database = require('node:sqlite').DatabaseSync;
const axios = require('axios');
const path = require('path');

const dbPath = path.resolve(__dirname, '../config/loom.db');
const db = new Database(dbPath);

const getSetting = (key) => {
  const row = db.prepare("SELECT value FROM system_settings WHERE key = ?").get(key);
  return row ? row.value : '';
};

const simklClientId = getSetting('SIMKL_CLIENT_ID');
const simklAccessToken = getSetting('SIMKL_ACCESS_TOKEN');

async function test() {
  if (!simklClientId || !simklAccessToken) return;

  const headers = {
    'simkl-api-key': simklClientId,
    'Content-Type': 'application/json',
    'User-Agent': 'Loom-Media-Server/1.0.0',
    Authorization: `Bearer ${simklAccessToken}`,
  };

  const urls = [
    'https://api.simkl.com/sync/all-items/movies/completed',
    'https://api.simkl.com/sync/all-items/movies'
  ];

  for (const url of urls) {
    try {
      const response = await axios.get(url, { headers });
      console.log(`URL: ${url}`);
      console.log('  Response Type:', Array.isArray(response.data) ? 'Array' : typeof response.data);
      console.log('  Response Sample:', JSON.stringify(response.data, null, 2).slice(0, 800));
    } catch (err) {
      console.error(`URL: ${url} failed:`, err.response?.data || err.message);
    }
  }
}

test();
