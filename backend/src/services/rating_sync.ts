import axios from 'axios';
import { tmdbService } from './tmdb';

export let syncStatus = {
  isSyncing: false,
  progress: 0,
  currentStep: '',
  lastSyncResult: null as any
};

type MediaLike = {
  title: string;
  type?: string;
  tmdb_id?: string | null;
  imdb_id?: string | null;
  year?: number | null;
};

function normalizeRating(value: any): number {
  const parsed = Number.parseInt(value?.toString?.() ?? '0', 10);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.min(10, parsed));
}

function isShow(media: MediaLike): boolean {
  const type = media.type?.toString().toLowerCase();
  return type === 'show' || type === 'tv' || type === 'tv show';
}

function buildItem(media: MediaLike) {
  return {
    title: media.title,
    year: media.year ? Number(media.year) : undefined,
    ids: {
      imdb: media.imdb_id || undefined,
      tmdb: media.tmdb_id ? Number(media.tmdb_id) : undefined,
    },
  };
}

function hasExternalId(media: MediaLike): boolean {
  return Boolean(media.imdb_id || media.tmdb_id);
}

function upsertExternalState(args: {
  tmdbId?: string | null;
  imdbId?: string | null;
  myRating?: string | null;
  watchStatus?: 'watched' | 'unwatched' | null;
  source: string;
}) {
  const tmdbId = args.tmdbId?.toString().trim() || '';
  const imdbId = args.imdbId?.toString().trim() || '';
  if (!tmdbId && !imdbId) return;

  const existing = db.prepare(`
    SELECT tmdb_id FROM external_media_state
    WHERE (tmdb_id = ? AND tmdb_id IS NOT NULL)
       OR (imdb_id = ? AND imdb_id IS NOT NULL)
    LIMIT 1
  `).get(tmdbId || null, imdbId || null) as { tmdb_id?: string } | undefined;

  const resolvedTmdbId = existing?.tmdb_id || tmdbId || imdbId;

  db.prepare(`
    INSERT INTO external_media_state (tmdb_id, imdb_id, my_rating, watch_status, source, updated_at)
    VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(tmdb_id) DO UPDATE SET
      imdb_id = COALESCE(excluded.imdb_id, external_media_state.imdb_id),
      my_rating = COALESCE(excluded.my_rating, external_media_state.my_rating),
      watch_status = COALESCE(excluded.watch_status, external_media_state.watch_status),
      source = excluded.source,
      updated_at = CURRENT_TIMESTAMP
  `).run(
    resolvedTmdbId,
    imdbId || null,
    args.myRating ?? null,
    args.watchStatus ?? null,
    args.source
  );
}

async function syncTrakt(media: MediaLike, rating: number) {
  if (tmdbService.getSetting('sync_trakt_ratings') === 'false') {
    console.log('[Sync] Trakt ratings sync disabled by user settings.');
    return;
  }

  const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
  const traktAccessToken = tmdbService.getSetting('TRAKT_ACCESS_TOKEN');

  if (!traktApiKey || !traktAccessToken || !hasExternalId(media)) return;

  const headers = {
    'trakt-api-key': traktApiKey,
    'trakt-api-version': '2',
    'Content-Type': 'application/json',
    'User-Agent': 'Loom/1.0',
    Authorization: `Bearer ${traktAccessToken}`,
  };

  const item = { ...buildItem(media), rating };
  const body = isShow(media) ? { shows: [item] } : { movies: [item] };

  if (rating === 0) {
    await axios.delete('https://api.trakt.tv/sync/ratings', { headers, data: body });
    return;
  }

  await axios.post('https://api.trakt.tv/sync/ratings', body, { headers });
}

async function syncSimkl(media: MediaLike, rating: number) {
  if (tmdbService.getSetting('sync_simkl_ratings') === 'false') {
    console.log('[Sync] Simkl ratings sync disabled by user settings.');
    return;
  }

  const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
  const simklAccessToken = tmdbService.getSetting('SIMKL_ACCESS_TOKEN');

  if (!simklClientId || !simklAccessToken || !hasExternalId(media)) return;

  const headers = {
    'simkl-api-key': simklClientId,
    'Content-Type': 'application/json',
    Authorization: `Bearer ${simklAccessToken}`,
  };

  const item = buildItem(media);

  if (rating === 0) {
    const body = isShow(media) ? { shows: [item] } : { movies: [item] };
    await axios.post('https://api.simkl.com/sync/remove-ratings', body, { headers });
    return;
  }

  const body = isShow(media)
    ? { shows: [{ ...item, rating }] }
    : { movies: [{ ...item, rating }] };
  await axios.post('https://api.simkl.com/sync/add-ratings', body, { headers });
}

async function syncTmdb(media: MediaLike, rating: number) {
  const tmdbUserAuth = tmdbService.getSetting('TMDB_USER_AUTH');

  if (!tmdbUserAuth || !media.tmdb_id) return;

  const path = isShow(media)
    ? `https://api.themoviedb.org/3/tv/${media.tmdb_id}/rating`
    : `https://api.themoviedb.org/3/movie/${media.tmdb_id}/rating`;

  const looksLikeBearer = tmdbUserAuth.includes('.') && tmdbUserAuth.split('.').length >= 2;
  const config = looksLikeBearer
    ? {
        headers: {
          Authorization: `Bearer ${tmdbUserAuth}`,
          'Content-Type': 'application/json;charset=utf-8',
          accept: 'application/json',
        },
      }
    : {
        params: { session_id: tmdbUserAuth },
        headers: {
          'Content-Type': 'application/json;charset=utf-8',
          accept: 'application/json',
        },
      };

  if (rating === 0) {
    await axios.delete(path, config);
    return;
  }

  await axios.post(path, { value: rating }, config);
}
async function syncTraktWatchStatus(media: MediaLike, isWatched: boolean) {
  if (tmdbService.getSetting('sync_trakt_watched') === 'false') {
    console.log('[Sync] Trakt watched status sync disabled by user settings.');
    return;
  }

  const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
  const traktAccessToken = tmdbService.getSetting('TRAKT_ACCESS_TOKEN');

  if (!traktApiKey || !traktAccessToken || !hasExternalId(media)) return;

  const headers = {
    'trakt-api-key': traktApiKey,
    'trakt-api-version': '2',
    'Content-Type': 'application/json',
    'User-Agent': 'Loom/1.0',
    Authorization: `Bearer ${traktAccessToken}`,
  };

  const item = buildItem(media);
  const body = isShow(media) ? { shows: [item] } : { movies: [item] };

  const path = isWatched 
    ? 'https://api.trakt.tv/sync/history' 
    : 'https://api.trakt.tv/sync/history/remove';

  await axios.post(path, body, { headers });
}

async function syncSimklWatchStatus(media: MediaLike, isWatched: boolean) {
  if (tmdbService.getSetting('sync_simkl_watched') === 'false') {
    console.log('[Sync] Simkl watched status sync disabled by user settings.');
    return;
  }

  const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
  const simklAccessToken = tmdbService.getSetting('SIMKL_ACCESS_TOKEN');

  if (!simklClientId || !simklAccessToken || !hasExternalId(media)) return;

  const headers = {
    'simkl-api-key': simklClientId,
    'Content-Type': 'application/json',
    Authorization: `Bearer ${simklAccessToken}`,
  };

  const item = buildItem(media);
  const body = isShow(media) ? { shows: [item] } : { movies: [item] };

  const path = isWatched 
    ? 'https://api.simkl.com/sync/history' 
    : 'https://api.simkl.com/sync/history/remove';

  await axios.post(path, body, { headers });
}

export async function syncExternalWatchStatus(media: MediaLike, isWatched: boolean) {
  try {
    await syncTraktWatchStatus(media, isWatched);
  } catch (error) {
    console.error('[Playback Sync] Trakt watch status sync failed:', error);
  }

  try {
    await syncSimklWatchStatus(media, isWatched);
  } catch (error) {
    console.error('[Playback Sync] Simkl watch status sync failed:', error);
  }
}

import db from '../config/database';
import { v4 as uuidv4 } from 'uuid';

export async function syncExternalRatings(media: MediaLike, rawRating: any) {
  const rating = normalizeRating(rawRating);

  try {
    await syncTrakt(media, rating);
  } catch (error) {
    console.error('[Rating Sync] Trakt sync failed:', error);
  }

  try {
    await syncSimkl(media, rating);
  } catch (error) {
    console.error('[Rating Sync] Simkl sync failed:', error);
  }

  try {
    await syncTmdb(media, rating);
  } catch (error) {
    console.error('[Rating Sync] TMDB sync failed:', error);
  }
}

// Background Import for Trakt.tv Ratings
export async function importRatingsFromTrakt(): Promise<number> {
  if (tmdbService.getSetting('sync_trakt_ratings') === 'false') {
    console.log('[Rating Sync] Trakt ratings import disabled by user settings.');
    return 0;
  }

  const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
  const traktAccessToken = tmdbService.getSetting('TRAKT_ACCESS_TOKEN');

  if (!traktApiKey || !traktAccessToken) {
    console.log('[Rating Sync] Trakt credentials missing for ratings import.');
    return 0;
  }

  let importCount = 0;
  try {
    console.log('[Rating Sync] Starting Trakt ratings import...');
    const headers = {
      'trakt-api-key': traktApiKey,
      'trakt-api-version': '2',
      'Content-Type': 'application/json',
      'User-Agent': 'Loom-Media-Server/1.0.0',
      Authorization: `Bearer ${traktAccessToken}`,
    };

    // Fetch rated movies from Trakt
    const response = await axios.get('https://api.trakt.tv/sync/ratings/movies', { headers });
    const ratedMovies = response.data as Array<{ rating: number; movie: { ids: { imdb?: string; tmdb?: number } } }>;

    if (!Array.isArray(ratedMovies)) return 0;

    for (const entry of ratedMovies) {
      const ratingValue = entry.rating;
      const imdbId = entry.movie?.ids?.imdb;
      const tmdbId = entry.movie?.ids?.tmdb?.toString();

      if (!imdbId && !tmdbId) continue;

      upsertExternalState({
        tmdbId,
        imdbId,
        myRating: ratingValue.toString(),
        source: 'trakt',
      });

      // Find matched film in Loom SQLite
      const movie = db.prepare(`
        SELECT id FROM media_items 
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL) 
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null) as { id: string } | undefined;

      if (movie) {
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'my_rating', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id, ratingValue.toString());
        importCount++;
      }
    }

    console.log(`[Rating Sync] Trakt ratings import complete. Synced ${importCount} ratings to Loom database!`);
  } catch (err) {
    console.error('[Rating Sync] Failed to import ratings from Trakt:', err);
  }
  return importCount;
}

// Background Import for Simkl Ratings
export async function importRatingsFromSimkl(): Promise<number> {
  if (tmdbService.getSetting('sync_simkl_ratings') === 'false') {
    console.log('[Rating Sync] Simkl ratings import disabled by user settings.');
    return 0;
  }

  const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
  const simklAccessToken = tmdbService.getSetting('SIMKL_ACCESS_TOKEN');

  if (!simklClientId || !simklAccessToken) {
    console.log('[Rating Sync] Simkl credentials missing for ratings import.');
    return 0;
  }

  let importCount = 0;
  try {
    console.log('[Rating Sync] Starting Simkl ratings import...');
    const headers = {
      'simkl-api-key': simklClientId,
      'Content-Type': 'application/json',
      'User-Agent': 'Loom-Media-Server/1.0.0',
      Authorization: `Bearer ${simklAccessToken}`,
    };

    // Fetch rated items from Simkl
    const response = await axios.get('https://api.simkl.com/sync/ratings', { headers });
    const data = response.data as { movies?: Array<{ user_rating?: number; rating?: number; movie: { ids: { imdb?: string; tmdb?: string } } }> };

    const ratedMovies = data.movies;
    if (!Array.isArray(ratedMovies)) return 0;

    for (const entry of ratedMovies) {
      const ratingValue = entry.user_rating ?? entry.rating;
      if (ratingValue === undefined || ratingValue === null) continue;

      const imdbId = entry.movie?.ids?.imdb;
      const tmdbId = entry.movie?.ids?.tmdb;

      if (!imdbId && !tmdbId) continue;

      upsertExternalState({
        tmdbId: tmdbId?.toString() ?? null,
        imdbId,
        myRating: ratingValue.toString(),
        source: 'simkl',
      });

      // Find matched film in Loom SQLite
      const movie = db.prepare(`
        SELECT id FROM media_items 
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL) 
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null) as { id: string } | undefined;

      if (movie) {
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'my_rating', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id, ratingValue.toString());
        importCount++;
      }
    }

    console.log(`[Rating Sync] Simkl ratings import complete. Synced ${importCount} ratings to Loom database!`);
  } catch (err) {
    console.error('[Rating Sync] Failed to import ratings from Simkl:', err);
  }
  return importCount;
}

// Background Import for Trakt Watch History / Seen Status
export async function importWatchHistoryFromTrakt(): Promise<number> {
  if (tmdbService.getSetting('sync_trakt_watched') === 'false') {
    console.log('[Playback Sync] Trakt watched status import disabled by user settings.');
    return 0;
  }

  const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
  const traktAccessToken = tmdbService.getSetting('TRAKT_ACCESS_TOKEN');

  if (!traktApiKey || !traktAccessToken) {
    console.log('[Playback Sync] Trakt credentials missing for watch history import.');
    return 0;
  }

  let importCount = 0;
  try {
    console.log('[Playback Sync] Starting Trakt watch history import...');
    const headers = {
      'trakt-api-key': traktApiKey,
      'trakt-api-version': '2',
      'Content-Type': 'application/json',
      'User-Agent': 'Loom-Media-Server/1.0.0',
      Authorization: `Bearer ${traktAccessToken}`,
    };

    const response = await axios.get('https://api.trakt.tv/sync/watched/movies', { headers });
    const watchedMovies = response.data as Array<{ movie: { ids: { imdb?: string; tmdb?: number } } }>;

    if (!Array.isArray(watchedMovies)) return 0;

    const defaultUser = db.prepare(`SELECT id FROM users LIMIT 1`).get() as { id: string } | undefined;
    const userId = defaultUser?.id || 'admin';

    for (const entry of watchedMovies) {
      const imdbId = entry.movie?.ids?.imdb;
      const tmdbId = entry.movie?.ids?.tmdb?.toString();

      if (!imdbId && !tmdbId) continue;

      upsertExternalState({
        tmdbId,
        imdbId,
        watchStatus: 'watched',
        source: 'trakt',
      });

      const movie = db.prepare(`
        SELECT id FROM media_items 
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL) 
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null) as { id: string } | undefined;

      if (movie) {
        // 1. Set watch_status = 'watched' in media_metadata
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'watch_status', 'watched')
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id);

        // 2. Set watch_history
        const existingHistory = db.prepare(`
          SELECT id FROM watch_history 
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(userId, movie.id) as { id: string } | undefined;

        if (existingHistory) {
          db.prepare(`
            UPDATE watch_history 
            SET is_watched = 1, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(existingHistory.id);
        } else {
          db.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          `).run(uuidv4(), userId, movie.id, 7200, 7200, 1);
        }
        importCount++;
      }
    }

    console.log(`[Playback Sync] Trakt watch history import complete. Synced ${importCount} items as watched!`);
  } catch (err) {
    console.error('[Playback Sync] Failed to import watch history from Trakt:', err);
  }
  return importCount;
}

// Background Import for Simkl Watch History / Seen Status
export async function importWatchHistoryFromSimkl(): Promise<number> {
  if (tmdbService.getSetting('sync_simkl_watched') === 'false') {
    console.log('[Playback Sync] Simkl watched status import disabled by user settings.');
    return 0;
  }

  const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
  const simklAccessToken = tmdbService.getSetting('SIMKL_ACCESS_TOKEN');

  if (!simklClientId || !simklAccessToken) {
    console.log('[Playback Sync] Simkl credentials missing for watch history import.');
    return 0;
  }

  let importCount = 0;
  try {
    console.log('[Playback Sync] Starting Simkl watch history import...');
    const headers = {
      'simkl-api-key': simklClientId,
      'Content-Type': 'application/json',
      'User-Agent': 'Loom-Media-Server/1.0.0',
      Authorization: `Bearer ${simklAccessToken}`,
    };

    const response = await axios.get('https://api.simkl.com/sync/all-items/movies/completed', { headers });
    const data = response.data;
    let watchedMovies: any[] = [];
    if (Array.isArray(data)) {
      watchedMovies = data;
    } else if (data && Array.isArray((data as any).movies)) {
      watchedMovies = (data as any).movies;
    }

    if (!Array.isArray(watchedMovies) || watchedMovies.length === 0) return 0;

    const defaultUser = db.prepare(`SELECT id FROM users LIMIT 1`).get() as { id: string } | undefined;
    const userId = defaultUser?.id || 'admin';

    for (const entry of watchedMovies) {
      const imdbId = entry.movie?.ids?.imdb;
      const tmdbId = entry.movie?.ids?.tmdb;

      if (!imdbId && !tmdbId) continue;

      upsertExternalState({
        tmdbId: tmdbId?.toString() ?? null,
        imdbId,
        watchStatus: 'watched',
        source: 'simkl',
      });

      const movie = db.prepare(`
        SELECT id FROM media_items 
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL) 
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null) as { id: string } | undefined;

      if (movie) {
        // 1. Set watch_status = 'watched' in media_metadata
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'watch_status', 'watched')
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id);

        // 2. Set watch_history
        const existingHistory = db.prepare(`
          SELECT id FROM watch_history 
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(userId, movie.id) as { id: string } | undefined;

        if (existingHistory) {
          db.prepare(`
            UPDATE watch_history 
            SET is_watched = 1, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(existingHistory.id);
        } else {
          db.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          `).run(uuidv4(), userId, movie.id, 7200, 7200, 1);
        }
        importCount++;
      }
    }

    console.log(`[Playback Sync] Simkl watch history import complete. Synced ${importCount} items as watched!`);
  } catch (err) {
    console.error('[Playback Sync] Failed to import watch history from Simkl:', err);
  }
  return importCount;
}

export async function syncAllExternalData() {
  if (syncStatus.isSyncing) {
    console.log('[Sync] A synchronization process is already active. Skipping duplicate trigger.');
    return;
  }

  console.log('[Sync] Starting full external data sync...');
  syncStatus.isSyncing = true;
  syncStatus.progress = 0;
  syncStatus.currentStep = 'Initierar synkning...';
  syncStatus.lastSyncResult = null;

  let totalTraktRatings = 0;
  let totalTraktWatched = 0;
  let totalSimklRatings = 0;
  let totalSimklWatched = 0;

  try {
    // Step 1: Trakt Ratings
    syncStatus.progress = 10;
    syncStatus.currentStep = 'Synkroniserar betyg från Trakt.tv...';
    totalTraktRatings = await importRatingsFromTrakt();

    // Step 2: Trakt Watched Status
    syncStatus.progress = 35;
    syncStatus.currentStep = 'Synkroniserar sedda filmer från Trakt.tv...';
    totalTraktWatched = await importWatchHistoryFromTrakt();

    // Step 3: Simkl Ratings
    syncStatus.progress = 60;
    syncStatus.currentStep = 'Synkroniserar betyg från Simkl...';
    totalSimklRatings = await importRatingsFromSimkl();

    // Step 4: Simkl Watched Status
    syncStatus.progress = 85;
    syncStatus.currentStep = 'Synkroniserar sedda filmer från Simkl...';
    totalSimklWatched = await importWatchHistoryFromSimkl();

    syncStatus.progress = 100;
    syncStatus.currentStep = 'Synkronisering klar!';
    syncStatus.lastSyncResult = {
      timestamp: new Date().toISOString(),
      success: true,
      trakt: { ratings: totalTraktRatings, watched: totalTraktWatched },
      simkl: { ratings: totalSimklRatings, watched: totalSimklWatched }
    };
    console.log('[Sync] Full external data sync finished successfully.', syncStatus.lastSyncResult);
  } catch (error: any) {
    syncStatus.progress = 100;
    syncStatus.currentStep = 'Synkronisering misslyckades!';
    syncStatus.lastSyncResult = {
      timestamp: new Date().toISOString(),
      success: false,
      error: error.message || String(error)
    };
    console.error('[Sync] Full external data sync failed:', error);
  } finally {
    syncStatus.isSyncing = false;
  }
}