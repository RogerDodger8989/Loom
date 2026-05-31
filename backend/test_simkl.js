const Database = require('node:sqlite').DatabaseSync;
const axios = require('axios');
const path = require('path');

const dbPath = path.resolve(__dirname, '../config/loom.db');
console.log('Reading database from:', dbPath);
const db = new Database(dbPath);

const getSetting = (key) => {
  const row = db.prepare("SELECT value FROM system_settings WHERE key = ?").get(key);
  return row ? row.value : '';
};

const simklClientId = getSetting('SIMKL_CLIENT_ID');
const simklAccessToken = getSetting('SIMKL_ACCESS_TOKEN');

console.log('Simkl Client ID:', simklClientId ? 'PRESENT' : 'MISSING');
console.log('Simkl Token:', simklAccessToken ? 'PRESENT' : 'MISSING');

async function test() {
  if (!simklClientId || !simklAccessToken) return;

  const headers = {
    'simkl-api-key': simklClientId,
    'Content-Type': 'application/json',
    'User-Agent': 'Loom-Media-Server/1.0.0',
    Authorization: `Bearer ${simklAccessToken}`,
  };

  try {
    const response = await axios.get('https://api.simkl.com/sync/watched?type=movies', { headers });
    console.log('Simkl watched response type:', Array.isArray(response.data) ? 'Array' : typeof response.data);
    console.log('Simkl watched response sample:', JSON.stringify(response.data, null, 2).slice(0, 1500));
  } catch (err) {
    console.error('Error fetching from Simkl:', err.response?.data || err.message);
  }
}

test();
