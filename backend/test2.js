const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
console.log(db.prepare("SELECT id FROM media_items LIMIT 1").get().id);
