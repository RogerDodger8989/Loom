const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
console.log(db.prepare("SELECT sql FROM sqlite_master WHERE type='table'").all().map(r => r.sql).join('\n\n'));
