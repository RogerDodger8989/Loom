const Database = require('better-sqlite3');
const db = new Database('c:/Users/denni/Desktop/Egna appar/Loom/backend/loom.db');

const show = db.prepare("SELECT id FROM media_items WHERE title='FROM'").get();
if (!show) {
  console.log("Show not found");
  process.exit(1);
}

const eps = db.prepare("SELECT id, season_number, episode_number FROM episodes WHERE show_id=? ORDER BY season_number, episode_number LIMIT 1").all(show.id);
console.log("Episodes:", eps);

const meta = db.prepare("SELECT * FROM media_metadata WHERE media_item_id=?").all(show.id);
console.log("Metadata keys:", meta.map(m => m.metadata_key));
