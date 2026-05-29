const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const dbPath = path.resolve(__dirname, 'config/loom.db');
console.log('Connecting to database at:', dbPath);

try {
  const db = new DatabaseSync(dbPath);
  
  console.log('\n--- Users ---');
  const users = db.prepare('SELECT id, username, role FROM users').all();
  console.log(users);
  
  console.log('\n--- Paired Devices ---');
  const devices = db.prepare('SELECT * FROM paired_devices').all();
  console.log(devices);

} catch (err) {
  console.error('Error querying database:', err);
}
