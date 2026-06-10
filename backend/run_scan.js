const { ScannerService } = require('./dist/services/scanner');
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(__dirname, '../config/loom.db'));

(async () => {
  const scanner = new ScannerService();
  await scanner.scanLibrary('C:\\tv-test', 'Show');
  console.log('Scan complete');
})();
