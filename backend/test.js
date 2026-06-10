const { DatabaseSync } = require('node:sqlite'); 
const db = new DatabaseSync('../config/loom.db'); 
console.log("TMDB duplicates:", db.prepare("SELECT tmdb_id, title, COUNT(*) as c FROM media_items WHERE type='Show' AND deleted_at IS NULL GROUP BY tmdb_id HAVING c > 1").all()); 
console.log("Title duplicates:", db.prepare("SELECT title, COUNT(*) as c FROM media_items WHERE type='Show' AND deleted_at IS NULL GROUP BY title HAVING c > 1").all());
