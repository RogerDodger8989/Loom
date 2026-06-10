const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const show = db.prepare("SELECT id FROM media_items WHERE title = 'FROM'").get();
if (show) {
  console.log(db.prepare("SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'status'").get(show.id));
  console.log(db.prepare("SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'next_episode_to_air'").get(show.id));
}
