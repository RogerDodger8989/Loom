const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const key = db.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get().value;
console.log(key);
