import db from '../backend/src/config/database';
const items = db.prepare('SELECT title, poster_path, year FROM media_items').all();
console.log(JSON.stringify(items, null, 2));
