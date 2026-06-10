const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
console.log(db.prepare("SELECT id, title, tmdb_id FROM media_items WHERE type='Show' AND title LIKE '%Rick%'").all());
