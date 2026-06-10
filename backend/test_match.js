const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('../config/loom.db');
const ptt = require('parse-torrent-title');

const showDirName = "Rick and Morty (2013)";
const info = ptt.parse(showDirName);
let title = info.title;
title = title.replace(/\s*[\(\[]?(19|20)\d{2}[\)\]]?\s*$/i, '').trim();

console.log('showTitle:', title, 'showDirName:', showDirName);

let showRow = db.prepare(`
  SELECT id, title, tmdb_id FROM media_items WHERE type='Show' AND (
    lower(title) = lower(?) OR lower(title) = lower(?)
  ) AND deleted_at IS NULL LIMIT 1
`).get(title, showDirName);
console.log('Match?', showRow);
