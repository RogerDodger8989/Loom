const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const res = db.prepare("SELECT metadata_value FROM media_metadata WHERE media_item_id = '3ddf2eeb-f478-473f-928f-f43f2527e874' AND metadata_key = 'trailer_url'").all();
console.log('Res:', res);
