const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
try {
  db.prepare("INSERT INTO media_items (id, title, type) VALUES ('_dummy_test_2', 'test', 'Music')").run();
  console.log('Insert OK');
  db.prepare("DELETE FROM media_items WHERE id = '_dummy_test_2'").run();
} catch(e) {
  console.error('Insert Failed:', e);
}
