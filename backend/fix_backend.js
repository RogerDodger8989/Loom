const fs = require('fs');
let content = fs.readFileSync('src/routes/media.ts', 'utf8');

const splitPoint = `_guest_stars') as guest_stars\n              FROM episodes e\n              LEFT JOIN watch_history wh ON wh.episode_id = e.id AND wh.user_id = ?\n              WHERE e.show_id = ? AND (e.deleted_at IS NULL OR e.deleted_at = '')\n              ORDER BY e.season_number ASC, e.episode_number ASC\n            \`).all(user.id, show.id);`;

if (content.includes(splitPoint)) {
  const replacement = `_guest_stars') as guest_stars,
                     (SELECT metadata_value FROM media_metadata WHERE media_item_id = e.show_id AND metadata_key = 'ep_' || e.id || '_subtitle_tracks') as subtitle_tracks,
                     (SELECT metadata_value FROM media_metadata WHERE media_item_id = e.show_id AND metadata_key = 'ep_' || e.id || '_audio_tracks') as audio_tracks
              FROM episodes e
              LEFT JOIN watch_history wh ON wh.episode_id = e.id AND wh.user_id = ?
              WHERE e.show_id = ? AND (e.deleted_at IS NULL OR e.deleted_at = '')
              ORDER BY e.season_number ASC, e.episode_number ASC
            \`).all(user.id, show.id).map((ep: any) => ({
              ...ep,
              subtitle_tracks: (() => { try { return ep.subtitle_tracks ? JSON.parse(ep.subtitle_tracks) : []; } catch { return []; } })(),
              audio_tracks: (() => { try { return ep.audio_tracks ? JSON.parse(ep.audio_tracks) : []; } catch { return []; } })()
            }));`;
  content = content.replace(splitPoint, replacement);
  fs.writeFileSync('src/routes/media.ts', content, 'utf8');
  console.log('Fixed media.ts query 2 splitPoint');
} else {
  console.log('Split point not found!');
}
