const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');

try {
    db.exec("PRAGMA foreign_keys=off;");
    db.exec("BEGIN TRANSACTION;");
    db.exec("CREATE TABLE media_items_new (id TEXT PRIMARY KEY, title TEXT NOT NULL, type TEXT CHECK(type IN ('Movie', 'Show', 'Music')) NOT NULL, year INTEGER, plot TEXT, genre TEXT, poster_path TEXT, fanart_path TEXT, tmdb_id TEXT, imdb_id TEXT, collection_name TEXT, collection_id TEXT, director TEXT, original_title TEXT, file_path TEXT, added_at DATETIME DEFAULT CURRENT_TIMESTAMP, deleted_at DATETIME DEFAULT NULL);");
    db.exec("INSERT INTO media_items_new SELECT * FROM media_items;");
    db.exec("DROP TABLE media_items;");
    db.exec("ALTER TABLE media_items_new RENAME TO media_items;");
    db.exec("COMMIT;");
    db.exec("PRAGMA foreign_keys=on;");
    console.log("Migration OK");
} catch(e) {
    db.exec("ROLLBACK;");
    console.error("Migration failed:", e);
}
