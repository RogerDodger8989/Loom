const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');

const rows = db.prepare(`SELECT tmdb_id, MIN(added_at) as first_added FROM media_items WHERE type='Show' GROUP BY tmdb_id`).all();
let deleted = 0;
for (const row of rows) {
  if (!row.tmdb_id) continue;
  
  // Find the original item
  const original = db.prepare('SELECT id FROM media_items WHERE tmdb_id = ? AND added_at = ? LIMIT 1').get(row.tmdb_id, row.first_added);
  
  // Find all duplicates
  const duplicates = db.prepare('SELECT id FROM media_items WHERE tmdb_id = ? AND id != ?').all(row.tmdb_id, original.id);
  
  for (const dup of duplicates) {
    db.prepare('DELETE FROM episodes WHERE show_id = ?').run(dup.id);
    db.prepare('DELETE FROM media_metadata WHERE media_item_id = ?').run(dup.id);
    db.prepare('DELETE FROM media_items WHERE id = ?').run(dup.id);
    deleted++;
  }
}
console.log(`Deleted ${deleted} duplicate shows and their dependencies.`);
