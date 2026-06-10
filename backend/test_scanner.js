const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const scanner = require('./dist/services/scanner.js').mediaScanner;

async function run() {
  console.log("Deleting duplicates before test...");
  db.prepare(`DELETE FROM media_items WHERE title='Rick and Morty' AND id != 'cf8be691-fdd9-41a9-be7a-b42df0c463f6'`).run();
  
  console.log("Running scanLibrary programmatically...");
  try {
    const res = await scanner.scanLibrary('C:\\tv-test', 'Show', true);
    console.log("Scan result:", res);
  } catch (e) {
    console.error(e);
  }
}
run();
