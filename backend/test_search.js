const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const tmdbService = require('./dist/services/tmdb.js').tmdbService;

async function run() {
    try {
        const results = await tmdbService.searchTvCandidates("From", 2022);
        console.log(JSON.stringify(results.slice(0, 5), null, 2));
    } catch (e) {
        console.error(e.message);
    }
}

run();
