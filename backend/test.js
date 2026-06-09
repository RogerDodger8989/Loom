const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const rows = db.prepare("SELECT id, title FROM media_items").all();
for (let r of rows) {
    const meta = db.prepare("SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'trailer_url'").get(r.id);
    if (meta) {
        console.log("HAS TRAILER:", r.title, meta.metadata_value);
    }
}
