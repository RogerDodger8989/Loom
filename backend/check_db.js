const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const meta = db.prepare("SELECT * FROM media_items").all();
console.log('Meta:', meta);
