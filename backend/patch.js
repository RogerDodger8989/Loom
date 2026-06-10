const fs = require('fs');
const file = 'src/services/scanner.ts';
let code = fs.readFileSync(file, 'utf8');

const target = `      // ── 2. Probe file for audio/subtitle tracks ────────────────
      const probeResult = await this.probeMediaFile(filePath);

      // ── 3. Look up TMDB episode title if available ─────────────
      let episodeTitle: string | null = null;
      let episodeAirDate: string | null = null;
      let episodeOverview: string | null = null;
      let episodeStillPath: string | null = null;
      if (tmdbShowId) {
        try {
          const apiKey = (db.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get() as any)?.value;
          const prefLang = (db.prepare("SELECT value FROM system_settings WHERE key='METADATA_LANGUAGE'").get() as any)?.value || 'sv-SE';
          if (apiKey) {
            const epResp = await axios.get(
              \`https://api.themoviedb.org/3/tv/\${tmdbShowId}/season/\${season}/episode/\${episodeNum}\`,
              { params: { api_key: apiKey, language: prefLang } }
            );
            episodeTitle = epResp.data?.name || null;
            episodeAirDate = epResp.data?.air_date || null;
            episodeOverview = epResp.data?.overview || null;
            if (epResp.data?.still_path) {
              episodeStillPath = tmdbService.getImageUrl(epResp.data.still_path, 'w500');
            }
            // Fallback overview in English if missing
            if (!episodeOverview && prefLang !== 'en-US') {
              try {
                const enResp = await axios.get(
                  \`https://api.themoviedb.org/3/tv/\${tmdbShowId}/season/\${season}/episode/\${episodeNum}\`,
                  { params: { api_key: apiKey, language: 'en-US' } }
                );
                episodeOverview = enResp.data?.overview || null;
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      // ── 4. Upsert episode ─────────────────────────────────────
      const existing = db.prepare(\`
        SELECT id FROM episodes WHERE show_id = ? AND season_number = ? AND episode_number = ?
      \`).get(showId, season, episodeNum) as any;

      let episodeId: string;
      if (existing) {
        db.prepare(\`UPDATE episodes SET file_path = ?, title = COALESCE(?, title), air_date = COALESCE(?, air_date), overview = COALESCE(?, overview), still_path = COALESCE(?, still_path) WHERE id = ?\`)
          .run(filePath, episodeTitle, episodeAirDate, episodeOverview, episodeStillPath, existing.id);
        episodeId = existing.id;

        // Update track metadata
        if (probeResult.audioTracks.length > 0 || probeResult.subtitleTracks.length > 0) {
          const upsertEpMeta = (key: string, val: string) => {
            db.prepare(\`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            \`).run(uuidv4(), showId, \`ep_\${episodeId}_\${key}\`, val);
          };
          if (probeResult.audioTracks.length > 0) upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
          if (probeResult.subtitleTracks.length > 0) upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
        }

        triggerChapterScan(filePath, null, episodeId);
        emitScanEvent('item_updated', \`Uppdaterad: \${showDirName} S\${String(season).padStart(2,'0')}E\${String(episodeNum).padStart(2,'0')}\`, 'Show');
        return 'updated';
      } else {
        episodeId = uuidv4();
        db.prepare(\`
          INSERT INTO episodes (id, show_id, season_number, episode_number, title, file_path, air_date, overview, still_path)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        \`).run(episodeId, showId, season, episodeNum, episodeTitle, filePath, episodeAirDate, episodeOverview, episodeStillPath);
        console.log(\`[Scanner] Added S\${String(season).padStart(2,'0')}E\${String(episodeNum).padStart(2,'0')} of \${showDirName}\`);

        // Store track metadata on the show's media_item
        const upsertEpMeta = (key: string, val: string) => {
          db.prepare(\`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          \`).run(uuidv4(), showId, \`ep_\${episodeId}_\${key}\`, val);
        };
        if (probeResult.audioTracks.length > 0) upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
        if (probeResult.subtitleTracks.length > 0) upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));`;

const replacement = `      // ── 2. Probe file for audio/subtitle tracks ────────────────
      const probeResult = await this.probeMediaFile(filePath);

      // ── 3. Check if episode already exists to avoid unnecessary TMDB lookups
      const existing = db.prepare(\`
        SELECT id, file_path FROM episodes WHERE show_id = ? AND season_number = ? AND episode_number = ?
      \`).get(showId, season, episodeNum) as any;

      let episodeId: string;

      if (existing) {
        episodeId = existing.id;
        
        // Update file path if it changed
        if (existing.file_path !== filePath) {
          db.prepare(\`UPDATE episodes SET file_path = ? WHERE id = ?\`).run(filePath, episodeId);
        }

        // Always update track metadata in case the file was replaced or probed differently
        if (probeResult.audioTracks.length > 0 || probeResult.subtitleTracks.length > 0) {
          const upsertEpMeta = (key: string, val: string) => {
            db.prepare(\`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            \`).run(uuidv4(), showId, \`ep_\${episodeId}_\${key}\`, val);
          };
          if (probeResult.audioTracks.length > 0) upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
          if (probeResult.subtitleTracks.length > 0) upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
        }

        return existing.file_path === filePath ? 'skipped' : 'updated';
      }

      // ── 4. Look up TMDB episode title if available (ONLY FOR NEW EPISODES)
      let episodeTitle: string | null = null;
      let episodeAirDate: string | null = null;
      let episodeOverview: string | null = null;
      let episodeStillPath: string | null = null;
      let episodeGuestStars: any[] | null = null;
      if (tmdbShowId) {
        try {
          const apiKey = (db.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get() as any)?.value;
          const prefLang = (db.prepare("SELECT value FROM system_settings WHERE key='METADATA_LANGUAGE'").get() as any)?.value || 'sv-SE';
          if (apiKey) {
            const epResp = await axios.get(
              \`https://api.themoviedb.org/3/tv/\${tmdbShowId}/season/\${season}/episode/\${episodeNum}\`,
              { params: { api_key: apiKey, language: prefLang } }
            );
            episodeTitle = epResp.data?.name || null;
            episodeAirDate = epResp.data?.air_date || null;
            episodeOverview = epResp.data?.overview || null;
            if (epResp.data?.still_path) {
              episodeStillPath = tmdbService.getImageUrl(epResp.data.still_path, 'w500');
            }
            if (epResp.data?.guest_stars?.length) {
              episodeGuestStars = epResp.data.guest_stars.map((g: any) => ({
                id: String(g.id),
                name: g.name,
                character: g.character || '',
                profile_path: g.profile_path ? tmdbService.getImageUrl(g.profile_path, 'w185') : null
              }));
            }
            // Fallback overview in English if missing
            if (!episodeOverview && prefLang !== 'en-US') {
              try {
                const enResp = await axios.get(
                  \`https://api.themoviedb.org/3/tv/\${tmdbShowId}/season/\${season}/episode/\${episodeNum}\`,
                  { params: { api_key: apiKey, language: 'en-US' } }
                );
                episodeOverview = enResp.data?.overview || null;
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      // ── 5. Insert new episode ─────────────────────────────────────
      episodeId = uuidv4();
      db.prepare(\`
        INSERT INTO episodes (id, show_id, season_number, episode_number, title, file_path, air_date, overview, still_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      \`).run(episodeId, showId, season, episodeNum, episodeTitle, filePath, episodeAirDate, episodeOverview, episodeStillPath);
      console.log(\`[Scanner] Added S\${String(season).padStart(2,'0')}E\${String(episodeNum).padStart(2,'0')} of \${showDirName}\`);

      // Store track metadata on the show's media_item
      const upsertEpMeta = (key: string, val: string) => {
        db.prepare(\`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        \`).run(uuidv4(), showId, \`ep_\${episodeId}_\${key}\`, val);
      };
      if (probeResult.audioTracks.length > 0) upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
      if (probeResult.subtitleTracks.length > 0) upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
      if (episodeGuestStars) upsertEpMeta('guest_stars', JSON.stringify(episodeGuestStars));`;

if (code.includes(target)) {
    fs.writeFileSync(file, code.replace(target, replacement), 'utf8');
    console.log("SUCCESS");
} else {
    console.log("TARGET NOT FOUND. Here is what exists near '4. Upsert episode':");
    const match = code.match(/.{0,200}4\. Upsert episode.{0,200}/s);
    if (match) console.log(match[0]);
}
