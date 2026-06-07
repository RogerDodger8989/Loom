import { FastifyInstance } from 'fastify';
import db from '../config/database';
import axios from 'axios';

const getSetting = (key: string): string => {
  const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value ?? '';
};

export default async function calendarRoutes(app: FastifyInstance) {
  // GET /api/calendar?start=YYYY-MM-DD&end=YYYY-MM-DD&type=Show|Movie|all
  app.get('/api/calendar', async (request, reply) => {
    const { start, end, type = 'all' } = request.query as Record<string, string>;

    if (!start || !end) {
      return reply.code(400).send({ error: 'start and end query params required (YYYY-MM-DD)' });
    }

    const tmdbKey = getSetting('TMDB_API_KEY');
    const events: any[] = [];

    if (type === 'all' || type === 'Show') {
      const episodes = db.prepare(`
        SELECT e.id, e.season_number, e.episode_number, e.title AS episode_title,
               e.air_date, m.id AS show_id, m.title AS show_title, m.poster_path, m.tmdb_id
        FROM episodes e
        JOIN media_items m ON e.show_id = m.id
        WHERE e.air_date IS NOT NULL
          AND e.air_date >= ? AND e.air_date <= ?
          AND m.deleted_at IS NULL
        ORDER BY e.air_date ASC
      `).all(start, end) as any[];

      for (const ep of episodes) {
        events.push({
          date: ep.air_date,
          type: 'episode',
          source: 'library',
          show_id: ep.show_id,
          episode_id: ep.id,
          title: ep.show_title,
          subtitle: `S${String(ep.season_number).padStart(2, '0')}E${String(ep.episode_number).padStart(2, '0')}${ep.episode_title ? ' – ' + ep.episode_title : ''}`,
          poster_path: ep.poster_path,
          media_type: 'Show',
        });
      }
    }

    if (type === 'all' || type === 'Movie') {
      // Lazy-backfill release_date for movies that have tmdb_id but no date yet (batch of 20)
      if (tmdbKey) {
        const missing = db.prepare(`
          SELECT id, tmdb_id FROM media_items
          WHERE type = 'Movie' AND deleted_at IS NULL AND tmdb_id IS NOT NULL
            AND (release_date IS NULL OR release_date = '')
          LIMIT 20
        `).all() as { id: string; tmdb_id: string }[];

        if (missing.length > 0) {
          await Promise.allSettled(missing.map(async (m) => {
            try {
              const r = await axios.get(`https://api.themoviedb.org/3/movie/${m.tmdb_id}`, {
                params: { api_key: tmdbKey },
              });
              if (r.data.release_date) {
                db.prepare('UPDATE media_items SET release_date = ? WHERE id = ?')
                  .run(r.data.release_date, m.id);
              }
            } catch {}
          }));
        }
      }

      const movies = db.prepare(`
        SELECT id, title, year, poster_path, tmdb_id, release_date
        FROM media_items
        WHERE type = 'Movie' AND deleted_at IS NULL
          AND release_date IS NOT NULL AND release_date != ''
          AND release_date >= ? AND release_date <= ?
        ORDER BY release_date ASC
      `).all(start, end) as any[];

      for (const m of movies) {
        events.push({
          date: m.release_date,
          type: 'movie',
          source: 'library',
          show_id: m.id,
          title: m.title,
          subtitle: m.year ? String(m.year) : '',
          poster_path: m.poster_path,
          media_type: 'Movie',
        });
      }
    }

    events.sort((a, b) => (a.date ?? '').localeCompare(b.date ?? ''));
    return reply.send(events);
  });

  // GET /api/calendar/trakt?start=YYYY-MM-DD&days=30
  // Uses the stored TRAKT_ACCESS_TOKEN to fetch the user's personal calendar.
  // Requires the user to have connected Trakt via OAuth in settings.
  app.get('/api/calendar/trakt', async (request, reply) => {
    const { start, days = '30' } = request.query as Record<string, string>;

    if (!start) {
      return reply.code(400).send({ error: 'start query param required (YYYY-MM-DD)' });
    }

    const accessToken = getSetting('TRAKT_ACCESS_TOKEN');
    const clientId = getSetting('TRAKT_API_KEY');

    if (!accessToken) {
      return reply.code(401).send({ error: 'Trakt ej ansluten. Koppla ditt Trakt-konto under Inställningar → Trakt.tv.' });
    }
    if (!clientId) {
      return reply.code(400).send({ error: 'TRAKT_API_KEY saknas i inställningarna.' });
    }

    try {
      const resp = await axios.get(
        `https://api.trakt.tv/calendars/my/shows/${start}/${days}`,
        {
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'trakt-api-key': clientId,
            'trakt-api-version': '2',
            'Content-Type': 'application/json',
          },
        }
      );

      const localShows = db.prepare(
        "SELECT id, tmdb_id, poster_path FROM media_items WHERE type='Show' AND deleted_at IS NULL AND tmdb_id IS NOT NULL"
      ).all() as { id: string; tmdb_id: string; poster_path: string | null }[];
      const localTmdbIds = new Set(localShows.map((s) => s.tmdb_id));
      const localPosterByTmdb = new Map(localShows.map((s) => [s.tmdb_id, s.poster_path]));
      const localIdByTmdb = new Map(localShows.map((s) => [s.tmdb_id, s.id]));

      const events = (resp.data as any[]).map((item: any) => {
        const tmdbId = item.show?.ids?.tmdb?.toString() ?? null;
        const inLib = tmdbId ? localTmdbIds.has(tmdbId) : false;
        return {
          date: item.first_aired?.substring(0, 10) ?? null,
          type: 'trakt_episode',
          source: 'trakt',
          title: item.show?.title ?? '',
          subtitle: `S${String(item.episode?.season).padStart(2, '0')}E${String(item.episode?.number).padStart(2, '0')}${item.episode?.title ? ' – ' + item.episode.title : ''}`,
          tmdb_id: tmdbId,
          // For library items: include local show_id so navigation goes to local detail page
          show_id: (inLib && tmdbId) ? (localIdByTmdb.get(tmdbId) ?? null) : null,
          in_library: inLib,
          // Poster: local DB first, then fetched below from TMDB
          poster_path: (tmdbId ? localPosterByTmdb.get(tmdbId) : null) ?? null,
          trakt_show_slug: item.show?.ids?.slug ?? null,
          media_type: 'Show',
        };
      });

      // Also fetch Trakt movie calendar (kommande biopremiärer från watchlist).
      // Trakt's movie calendar has a max of 31 days per request — split into chunks.
      const traktMovieHeaders = {
        'Authorization': `Bearer ${accessToken}`,
        'trakt-api-key': clientId,
        'trakt-api-version': '2',
        'Content-Type': 'application/json',
      };

      const localMovies = db.prepare(
        "SELECT id, tmdb_id, poster_path FROM media_items WHERE type='Movie' AND deleted_at IS NULL AND tmdb_id IS NOT NULL"
      ).all() as { id: string; tmdb_id: string; poster_path: string | null }[];
      const localMoviePoster = new Map(localMovies.map(m => [m.tmdb_id, m.poster_path]));
      const localMovieId    = new Map(localMovies.map(m => [m.tmdb_id, m.id]));
      const localMovieTmdbIds = new Set(localMovies.map(m => m.tmdb_id));

      const totalDays = parseInt(days, 10) + 60;  // +60 days lookback for movies
      const maxChunk  = 31;  // Trakt API limit
      let movieOffset = -60; // start 60 days before window

      while (movieOffset < parseInt(days, 10)) {
        const chunkDays  = Math.min(maxChunk, parseInt(days, 10) - movieOffset);
        const chunkStart = new Date(start);
        chunkStart.setDate(chunkStart.getDate() + movieOffset);
        const chunkStartStr = chunkStart.toISOString().substring(0, 10);

        try {
          const movieResp = await axios.get(
            `https://api.trakt.tv/calendars/my/movies/${chunkStartStr}/${chunkDays}`,
            { headers: traktMovieHeaders }
          );
          console.log(`[Trakt] Movie calendar ${chunkStartStr}+${chunkDays}: ${movieResp.data?.length ?? 0} items`);

          for (const item of movieResp.data as any[]) {
            const tmdbId = item.movie?.ids?.tmdb?.toString() ?? null;
            const inLib  = tmdbId ? localMovieTmdbIds.has(tmdbId) : false;
            const relDate = item.released ?? null;
            if (!relDate) continue;
            events.push({
              date: relDate,
              type: 'trakt_movie',
              source: 'trakt',
              title: item.movie?.title ?? '',
              subtitle: item.movie?.year ? String(item.movie.year) : '',
              tmdb_id: tmdbId,
              show_id: (inLib && tmdbId) ? (localMovieId.get(tmdbId) ?? null) : null,
              in_library: inLib,
              poster_path: (tmdbId ? localMoviePoster.get(tmdbId) : null) ?? null,
              trakt_show_slug: item.movie?.ids?.slug ?? null,
              media_type: 'Movie',
            });
          }
        } catch (movieErr: any) {
          console.warn('[Trakt] Movie calendar chunk failed:', chunkStartStr, movieErr?.response?.status, movieErr?.message);
          break; // stop chunking on error
        }

        movieOffset += chunkDays;
      }

      // Batch-fetch TMDB poster URLs for events still missing posters
      const tmdbKey = getSetting('TMDB_API_KEY');
      if (tmdbKey) {
        // Separate poster fetch for shows vs movies
        const needShowPoster = [...new Set(
          events.filter(e => !e.poster_path && e.tmdb_id && e.media_type !== 'Movie')
                .map(e => e.tmdb_id as string)
        )];
        const needMoviePoster = [...new Set(
          events.filter(e => !e.poster_path && e.tmdb_id && e.media_type === 'Movie')
                .map(e => e.tmdb_id as string)
        )];
        const posterMap: Record<string, string> = {};
        const batchSz = 20;

        for (const [tmdbIds, endpoint] of [
          [needShowPoster,  'tv'],
          [needMoviePoster, 'movie'],
        ] as [string[], string][]) {
          for (let i = 0; i < tmdbIds.length; i += batchSz) {
            await Promise.allSettled(
              tmdbIds.slice(i, i + batchSz).map(async (tid) => {
                try {
                  const r = await axios.get(
                    `https://api.themoviedb.org/3/${endpoint}/${tid}`,
                    { params: { api_key: tmdbKey } }
                  );
                  if (r.data.poster_path) {
                    posterMap[tid] = `https://image.tmdb.org/t/p/w200${r.data.poster_path}`;
                  }
                } catch {}
              })
            );
          }
        }
        for (const ev of events) {
          if (!ev.poster_path && ev.tmdb_id && posterMap[ev.tmdb_id]) {
            ev.poster_path = posterMap[ev.tmdb_id];
          }
        }
      }

      return reply.send(events);
    } catch (e: any) {
      const status = e.response?.status;
      if (status === 401) {
        return reply.code(401).send({ error: 'Trakt-token ogiltig. Återkoppla kontot under Inställningar.' });
      }
      return reply.code(502).send({ error: 'Trakt API-fel', details: e.message });
    }
  });

  // GET /api/calendar/simkl?start=YYYY-MM-DD&days=30
  // Gets the user's Simkl "watching" list, then queries TMDB for next_episode_to_air
  // on each show, and returns those that fall within the requested date range.
  app.get('/api/calendar/simkl', async (request, reply) => {
    const { start, days = '90' } = request.query as Record<string, string>;

    if (!start) {
      return reply.code(400).send({ error: 'start query param required (YYYY-MM-DD)' });
    }

    const accessToken = getSetting('SIMKL_ACCESS_TOKEN');
    const clientId = getSetting('SIMKL_CLIENT_ID');
    const tmdbKey = getSetting('TMDB_API_KEY');

    if (!accessToken) {
      return reply.code(401).send({ error: 'Simkl ej ansluten. Koppla ditt Simkl-konto under Inställningar → Simkl.' });
    }
    if (!clientId) {
      return reply.code(400).send({ error: 'SIMKL_CLIENT_ID saknas i inställningarna.' });
    }
    if (!tmdbKey) {
      return reply.code(400).send({ error: 'TMDB_API_KEY saknas i inställningarna.' });
    }

    try {
      // Step 1: Get Simkl watching list
      const watchResp = await axios.get('https://api.simkl.com/sync/all-items/shows/watching', {
        params: { client_id: clientId },
        headers: { 'Authorization': `Bearer ${accessToken}` },
      });

      const watchList: any[] = watchResp.data?.shows ?? [];
      if (watchList.length === 0) return reply.send([]);

      // Extract TMDB IDs (max 100 to stay within TMDB rate limits)
      const tmdbIds: { tmdbId: string; simklTitle: string; poster: string | null }[] = [];
      for (const item of watchList.slice(0, 100)) {
        const tmdbId = item.show?.ids?.tmdb?.toString();
        if (tmdbId) {
          tmdbIds.push({
            tmdbId,
            simklTitle: item.show?.title ?? '',
            poster: item.show?.poster ? `https://simkl.in/posters/${item.show.poster}_m.jpg` : null,
          });
        }
      }

      const rangeStart = new Date(start);
      const rangeEnd = new Date(start);
      rangeEnd.setDate(rangeEnd.getDate() + parseInt(days, 10));
      const movieLookback = new Date(start);
      movieLookback.setDate(movieLookback.getDate() - 60);

      const localShows = db.prepare(
        "SELECT tmdb_id FROM media_items WHERE type='Show' AND deleted_at IS NULL AND tmdb_id IS NOT NULL"
      ).all() as { tmdb_id: string }[];
      const localTmdbIds = new Set(localShows.map((s) => s.tmdb_id));

      // Step 2: Fetch TMDB show info + full season episode lists in batches of 8
      const events: any[] = [];
      const seenKeys = new Set<string>();
      const batchSize = 8;

      for (let i = 0; i < tmdbIds.length; i += batchSize) {
        const batch = tmdbIds.slice(i, i + batchSize);
        const results = await Promise.allSettled(
          batch.map(({ tmdbId, simklTitle, poster }) =>
            axios.get(`https://api.themoviedb.org/3/tv/${tmdbId}`, {
              params: { api_key: tmdbKey, language: 'sv-SE' },
            }).then(async (r: any) => {
              const data = r.data;

              // Determine which seasons to fully fetch (current + adjacent)
              const seasonNums = new Set<number>();
              if (data.next_episode_to_air?.season_number) {
                seasonNums.add(data.next_episode_to_air.season_number);
              }
              if (data.last_episode_to_air?.season_number) {
                seasonNums.add(data.last_episode_to_air.season_number);
              }

              // Fetch full episode lists for each relevant season
              const allEpisodes: any[] = [];
              for (const sn of seasonNums) {
                try {
                  const sr = await axios.get(
                    `https://api.themoviedb.org/3/tv/${tmdbId}/season/${sn}`,
                    { params: { api_key: tmdbKey } }
                  );
                  allEpisodes.push(...(sr.data?.episodes ?? []));
                } catch {}
              }

              return { data, allEpisodes, tmdbId, simklTitle, poster };
            })
          )
        );

        for (const result of results) {
          if (result.status !== 'fulfilled') continue;
          const { data, allEpisodes, tmdbId, simklTitle, poster } = result.value;

          const posterPath = data.poster_path
            ? `https://image.tmdb.org/t/p/w200${data.poster_path}`
            : poster;
          const showName = data.name ?? simklTitle;

          for (const ep of allEpisodes) {
            if (!ep.air_date) continue;
            const airDate = new Date(ep.air_date);
            if (airDate < rangeStart || airDate > rangeEnd) continue;

            const key = `${tmdbId}:S${ep.season_number}E${ep.episode_number}`;
            if (seenKeys.has(key)) continue;
            seenKeys.add(key);

            const s = String(ep.season_number ?? 0).padStart(2, '0');
            const e = String(ep.episode_number ?? 0).padStart(2, '0');
            const epTitle = ep.name ? ` – ${ep.name}` : '';

            events.push({
              date: ep.air_date,
              type: 'simkl_episode',
              source: 'simkl',
              title: showName,
              subtitle: `S${s}E${e}${epTitle}`,
              tmdb_id: tmdbId,
              in_library: localTmdbIds.has(tmdbId),
              poster_path: posterPath,
              media_type: 'Show',
            });
          }
        }
      }


      // ── Simkl movie_release calendar filtered to user's watchlist ──────
      // Per Simkl docs: combine /sync/all-items + CDN calendar to get personal upcoming movies
      try {
        // Step 1: get user's full movie watchlist (per docs: full sync, no date_from)
        const wlResp = await axios.get('https://api.simkl.com/sync/all-items/movies', {
          params: { client_id: clientId, 'app-name': 'Loom', 'app-version': '1.0' },
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'User-Agent': 'Loom/1.0',
          },
        });
        const wlMovies: any[] = wlResp.data?.movies ?? [];
        const watchlistSimklIds = new Set(
          wlMovies.map(m => m.movie?.ids?.simkl_id?.toString()).filter(Boolean)
        );
        const watchlistTmdbIds = new Set(
          wlMovies.map(m => m.movie?.ids?.tmdb?.toString()).filter(Boolean)
        );
        console.log(`[Simkl] watchlist movies: ${wlMovies.length} (${watchlistSimklIds.size} simkl IDs)`);

        const localMovies = db.prepare(
          "SELECT id, tmdb_id FROM media_items WHERE type='Movie' AND deleted_at IS NULL AND tmdb_id IS NOT NULL"
        ).all() as { id: string; tmdb_id: string }[];
        const localMovieByTmdb = new Map(localMovies.map(m => [m.tmdb_id, m.id]));

        // Step 2: fetch CDN calendar per month, filter to watchlist
        const months: { year: number; month: number }[] = [];
        const cur = new Date(movieLookback);
        while (cur <= rangeEnd) {
          months.push({ year: cur.getFullYear(), month: cur.getMonth() + 1 });
          cur.setMonth(cur.getMonth() + 1);
        }

        for (const { year, month } of months) {
          try {
            const url = `https://data.simkl.in/calendar/${year}/${month}/movie_release.json`;
            const resp = await axios.get(url, {
              params: { client_id: clientId, 'app-name': 'Loom', 'app-version': '1.0' },
              headers: { 'User-Agent': 'Loom/1.0' },
              timeout: 8000,
            });
            const entries: any[] = Array.isArray(resp.data) ? resp.data : [];
            for (const entry of entries) {
              const simklId = entry.ids?.simkl_id?.toString();
              const tmdbId  = entry.ids?.tmdb?.toString() ?? null;
              // Only show movies in user's watchlist
              if (!watchlistSimklIds.has(simklId) && (!tmdbId || !watchlistTmdbIds.has(tmdbId))) continue;
              const dateStr: string = (entry.date ?? entry.release_date ?? '').substring(0, 10);
              if (!dateStr) continue;
              const d = new Date(dateStr);
              if (d < movieLookback || d > rangeEnd) continue;
              events.push({
                date: dateStr,
                type: 'simkl_movie',
                source: 'simkl',
                title: entry.title ?? '',
                subtitle: dateStr.substring(0, 4),
                tmdb_id: tmdbId,
                show_id: tmdbId ? (localMovieByTmdb.get(tmdbId) ?? null) : null,
                in_library: tmdbId ? localMovieByTmdb.has(tmdbId) : false,
                poster_path: entry.poster ? `https://simkl.in/posters/${entry.poster}_m.jpg` : null,
                media_type: 'Movie',
              });
            }
            console.log(`[Simkl] ${year}/${month}: ${entries.length} total, ${events.filter(e=>e.type==='simkl_movie').length} matched watchlist`);
          } catch (me: any) {
            console.warn(`[Simkl] ${year}/${month} failed:`, me?.response?.status);
          }
        }
      } catch (movieErr: any) {
        console.warn('[Simkl] movie calendar failed:', movieErr?.message);
      }

      events.sort((a, b) => (a.date ?? '').localeCompare(b.date ?? ''));
      return reply.send(events);
    } catch (e: any) {
      const status = e.response?.status;
      if (status === 401) {
        return reply.code(401).send({ error: 'Simkl-token ogiltig. Återkoppla kontot under Inställningar.' });
      }
      return reply.code(502).send({ error: 'Simkl API-fel', details: e.message });
    }
  });

  // GET /api/calendar/export.ics?start=YYYY-MM-DD&end=YYYY-MM-DD
  app.get('/api/calendar/export.ics', async (request, reply) => {
    const { start = '2000-01-01', end = '2099-12-31' } = request.query as Record<string, string>;

    const episodes = db.prepare(`
      SELECT e.id, e.season_number, e.episode_number, e.title AS episode_title,
             e.air_date, m.title AS show_title
      FROM episodes e
      JOIN media_items m ON e.show_id = m.id
      WHERE e.air_date IS NOT NULL
        AND e.air_date >= ? AND e.air_date <= ?
        AND m.deleted_at IS NULL
      ORDER BY e.air_date ASC
    `).all(start, end) as any[];

    const toIcalDate = (d: string) => d.replace(/-/g, '');

    const lines: string[] = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Loom Media Server//Calendar//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:Loom TV Calendar',
    ];

    for (const ep of episodes) {
      const s = String(ep.season_number).padStart(2, '0');
      const e = String(ep.episode_number).padStart(2, '0');
      const title = `${ep.show_title} S${s}E${e}${ep.episode_title ? ' – ' + ep.episode_title : ''}`;
      lines.push('BEGIN:VEVENT');
      lines.push(`UID:loom-ep-${ep.id}@loom`);
      lines.push(`DTSTART;VALUE=DATE:${toIcalDate(ep.air_date)}`);
      lines.push(`DTEND;VALUE=DATE:${toIcalDate(ep.air_date)}`);
      lines.push(`SUMMARY:${title}`);
      lines.push('END:VEVENT');
    }

    lines.push('END:VCALENDAR');

    reply.header('Content-Type', 'text/calendar; charset=utf-8');
    reply.header('Content-Disposition', 'attachment; filename="loom-calendar.ics"');
    return reply.send(lines.join('\r\n'));
  });

  // GET /api/calendar/imdb?start=YYYY-MM-DD&days=N
  // Fetches the user's public IMDb watchlist via RSS, cross-references with TMDB
  // for release dates, and returns calendar events.
  app.get('/api/calendar/imdb', async (request, reply) => {
    const { start, days = '90' } = request.query as Record<string, string>;

    const rawId = getSetting('IMDB_USER_ID').trim();
    if (!rawId) {
      return reply.code(404).send({ error: 'IMDB_USER_ID inte konfigurerat under Inställningar → Källor & Integrationer → IMDb.' });
    }

    const tmdbKey = getSetting('TMDB_API_KEY');
    if (!tmdbKey) {
      return reply.code(400).send({ error: 'TMDB_API_KEY krävs för IMDb-kalendern.' });
    }

    // Accept full URLs or bare IDs. Extract ls/ur ID from URL if needed.
    let rssUrl: string;
    const lsMatch = rawId.match(/ls\d+/);
    const urMatch = rawId.match(/ur[\w]+/);
    if (lsMatch) {
      rssUrl = `https://rss.imdb.com/list/${lsMatch[0]}/`;
    } else if (urMatch) {
      rssUrl = `https://rss.imdb.com/user/${urMatch[0]}/watchlist`;
    } else if (/^\d+$/.test(rawId)) {
      rssUrl = `https://rss.imdb.com/user/ur${rawId}/watchlist`;
    } else {
      return reply.code(400).send({ error: `Ogiltigt IMDb-ID: "${rawId}". Klistra in din watchlist-URL eller ditt User ID (ur12345678 eller ls003160623).` });
    }

    try {
      // Fetch public RSS watchlist
      const rssResp = await axios.get(
        rssUrl,
        { responseType: 'text', timeout: 10000 }
      );

      const xml = rssResp.data as string;

      // Extract IMDb IDs (tt followed by digits) from item links
      const matches = [...xml.matchAll(/https?:\/\/www\.imdb\.com\/title\/(tt\d+)\//g)];
      const imdbIds = [...new Set(matches.map(m => m[1]))].slice(0, 100);

      if (imdbIds.length === 0) {
        return reply.send([]);
      }

      const rangeStart = new Date(start);
      const rangeEnd = new Date(start);
      rangeEnd.setDate(rangeEnd.getDate() + parseInt(days, 10));
      // For movies: also include releases from up to 60 days before the window
      // so recently-released watchlist films are visible.
      const movieLookback = new Date(start);
      movieLookback.setDate(movieLookback.getDate() - 60);

      const localMovies = db.prepare(
        "SELECT id, tmdb_id, poster_path FROM media_items WHERE type='Movie' AND deleted_at IS NULL AND tmdb_id IS NOT NULL"
      ).all() as { id: string; tmdb_id: string; poster_path: string | null }[];
      const localShows = db.prepare(
        "SELECT id, tmdb_id, poster_path FROM media_items WHERE type='Show' AND deleted_at IS NULL AND tmdb_id IS NOT NULL"
      ).all() as { id: string; tmdb_id: string; poster_path: string | null }[];

      const localMovieByTmdb  = new Map(localMovies.map(m => [m.tmdb_id, m]));
      const localShowByTmdb   = new Map(localShows.map(s => [s.tmdb_id, s]));

      const events: any[] = [];
      const batchSize = 10;

      for (let i = 0; i < imdbIds.length; i += batchSize) {
        const batch = imdbIds.slice(i, i + batchSize);

        await Promise.allSettled(batch.map(async (imdbId) => {
          try {
            // Step 1: Resolve IMDb ID → TMDB
            const findResp = await axios.get(
              `https://api.themoviedb.org/3/find/${imdbId}`,
              { params: { api_key: tmdbKey, external_source: 'imdb_id' } }
            );

            const movieResults: any[] = findResp.data.movie_results ?? [];
            const tvResults: any[]    = findResp.data.tv_results ?? [];

            // ── Movies ──
            for (const movie of movieResults) {
              const releaseDate = movie.release_date;
              if (!releaseDate) continue;
              const d = new Date(releaseDate);
              if (d < movieLookback || d > rangeEnd) continue;

              const tmdbId  = movie.id?.toString();
              const localM  = tmdbId ? localMovieByTmdb.get(tmdbId) : undefined;
              const posterPath = localM?.poster_path
                ?? (movie.poster_path ? `https://image.tmdb.org/t/p/w200${movie.poster_path}` : null);

              events.push({
                date:       releaseDate,
                type:       'imdb_movie',
                source:     'imdb',
                title:      movie.title ?? '',
                subtitle:   movie.release_date?.substring(0, 4) ?? '',
                tmdb_id:    tmdbId ?? null,
                show_id:    localM?.id ?? null,
                in_library: !!localM,
                poster_path: posterPath,
                media_type: 'Movie',
              });
            }

            // ── TV Shows: fetch full details for next/last episode ──
            for (const tv of tvResults) {
              const tmdbId = tv.id?.toString();
              if (!tmdbId) continue;

              const tvResp = await axios.get(
                `https://api.themoviedb.org/3/tv/${tmdbId}`,
                { params: { api_key: tmdbKey } }
              );
              const tvData = tvResp.data;

              // Determine current season
              const seasonNums = new Set<number>();
              if (tvData.next_episode_to_air?.season_number) {
                seasonNums.add(tvData.next_episode_to_air.season_number);
              }
              if (tvData.last_episode_to_air?.season_number) {
                seasonNums.add(tvData.last_episode_to_air.season_number);
              }

              const localS = localShowByTmdb.get(tmdbId);
              const posterPath = localS?.poster_path
                ?? (tvData.poster_path ? `https://image.tmdb.org/t/p/w200${tvData.poster_path}` : null);

              for (const sn of seasonNums) {
                try {
                  const seasonResp = await axios.get(
                    `https://api.themoviedb.org/3/tv/${tmdbId}/season/${sn}`,
                    { params: { api_key: tmdbKey } }
                  );
                  for (const ep of (seasonResp.data?.episodes ?? []) as any[]) {
                    if (!ep.air_date) continue;
                    const epDate = new Date(ep.air_date);
                    if (epDate < rangeStart || epDate > rangeEnd) continue;

                    const s = String(ep.season_number ?? 0).padStart(2, '0');
                    const e = String(ep.episode_number ?? 0).padStart(2, '0');

                    events.push({
                      date:       ep.air_date,
                      type:       'imdb_episode',
                      source:     'imdb',
                      title:      tvData.name ?? tv.name ?? '',
                      subtitle:   `S${s}E${e}${ep.name ? ' – ' + ep.name : ''}`,
                      tmdb_id:    tmdbId,
                      show_id:    localS?.id ?? null,
                      in_library: !!localS,
                      poster_path: posterPath,
                      media_type: 'Show',
                    });
                  }
                } catch {}
              }
            }
          } catch {}
        }));
      }

      events.sort((a, b) => (a.date ?? '').localeCompare(b.date ?? ''));
      console.log(`[IMDb] Calendar: ${events.length} events for ${rawId}`);
      return reply.send(events);

    } catch (e: any) {
      if (e?.response?.status === 404) {
        return reply.code(401).send({ error: 'IMDb-watchlist hittades inte. Kontrollera att ditt User ID är rätt och att watchlist är offentlig.' });
      }
      return reply.code(502).send({ error: 'IMDb RSS-fel', details: e.message });
    }
  });
}
