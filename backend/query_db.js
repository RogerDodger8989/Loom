const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');

const itemId = 'f6f46be6-de48-4992-9587-12619038920c'; // A show ID I saw earlier

const epMetaRows = db.prepare(`
  SELECT metadata_key, metadata_value
  FROM media_metadata
  WHERE media_item_id = ? AND metadata_key LIKE 'ep_%'
`).all(itemId);

const epMeta = {};
for (const row of epMetaRows) {
  const match = row.metadata_key.match(/^ep_([^_]+)_(.+)$/);
  if (match) {
    const epId = match[1];
    const key = match[2];
    if (!epMeta[epId]) epMeta[epId] = {};
    epMeta[epId][key] = row.metadata_value;
  }
}
console.log(JSON.stringify(epMeta, null, 2));
