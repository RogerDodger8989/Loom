const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');

try {
    const show = db.prepare("SELECT id FROM media_items WHERE tmdb_id = '158357' AND type = 'Show'").get();
    if (show) {
        db.prepare("DELETE FROM media_metadata WHERE media_item_id = ?").run(show.id);
        db.prepare("DELETE FROM media_items WHERE id = ?").run(show.id);
        console.log("Deleted incorrect show entry. It will be rescanned properly on the next library scan.");
    } else {
        console.log("Incorrect show not found.");
    }
} catch (e) {
    console.error(e.message);
}
