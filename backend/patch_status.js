const fs = require('fs');
const file = 'src/services/scanner.ts';
let code = fs.readFileSync(file, 'utf8');

const target = `            if (fullShow?.number_of_seasons) {
              const upsertShowMeta = (key: string, val: string) => {
                db.prepare(\`INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
                  VALUES (?,?,?,?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value\`)
                  .run(uuidv4(), showId, key, val);
              };
              upsertShowMeta('number_of_seasons', String(fullShow.number_of_seasons));
              if (fullShow.seasons?.length) {`;

const replacement = `            if (fullShow) {
              const upsertShowMeta = (key: string, val: string) => {
                db.prepare(\`INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
                  VALUES (?,?,?,?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value\`)
                  .run(uuidv4(), showId, key, val);
              };
              if (fullShow.number_of_seasons) {
                upsertShowMeta('number_of_seasons', String(fullShow.number_of_seasons));
              }
              if (fullShow.status) {
                upsertShowMeta('status', fullShow.status);
              }
              if (fullShow.next_episode_to_air) {
                upsertShowMeta('next_episode_to_air', JSON.stringify(fullShow.next_episode_to_air));
              }
              if (fullShow.vote_average != null) {
                upsertShowMeta('tmdb_rating', String(fullShow.vote_average));
                upsertShowMeta('ratings', JSON.stringify({ tmdb: fullShow.vote_average, tmdb_votes: fullShow.vote_count }));
              }
              if (fullShow.seasons?.length) {`;

if (code.includes(target)) {
    fs.writeFileSync(file, code.replace(target, replacement), 'utf8');
    console.log("SUCCESS");
} else {
    console.log("TARGET NOT FOUND");
}
