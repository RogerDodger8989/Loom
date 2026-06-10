const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const mediaScanner = require('./dist/services/scanner.js').mediaScanner;

async function run() {
    const shows = db.prepare("SELECT id, tmdb_id FROM media_items WHERE type = 'Show' AND tmdb_id IS NOT NULL").all();
    console.log(`Refreshing metadata for ${shows.length} shows...`);
    for (const show of shows) {
        try {
            await mediaScanner.refreshShowMetadata(show.id, show.tmdb_id);
            console.log(`Refreshed ${show.id}`);
        } catch (e) {
            console.error(`Failed to refresh ${show.id}:`, e.message);
        }
    }
    console.log("Done.");
}

run();
