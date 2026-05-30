import axios from 'axios';
import { tmdbService } from './tmdb';

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

async function syncTrakt(media: MediaLike, rating: number) {
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
export async function importRatingsFromTrakt() {
  const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
  const traktAccessToken = tmdbService.getSetting('TRAKT_ACCESS_TOKEN');

  if (!traktApiKey || !traktAccessToken) {
    console.log('[Rating Sync] Trakt credentials missing for ratings import.');
    return;
  }

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

    if (!Array.isArray(ratedMovies)) return;

    let importCount = 0;
    for (const entry of ratedMovies) {
      const ratingValue = entry.rating;
      const imdbId = entry.movie?.ids?.imdb;
      const tmdbId = entry.movie?.ids?.tmdb?.toString();

      if (!imdbId && !tmdbId) continue;

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
}

// Background Import for Simkl Ratings
export async function importRatingsFromSimkl() {
  const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
  const simklAccessToken = tmdbService.getSetting('SIMKL_ACCESS_TOKEN');

  if (!simklClientId || !simklAccessToken) {
    console.log('[Rating Sync] Simkl credentials missing for ratings import.');
    return;
  }

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
    if (!Array.isArray(ratedMovies)) return;

    let importCount = 0;
    for (const entry of ratedMovies) {
      const ratingValue = entry.user_rating ?? entry.rating;
      if (ratingValue === undefined || ratingValue === null) continue;

      const imdbId = entry.movie?.ids?.imdb;
      const tmdbId = entry.movie?.ids?.tmdb;

      if (!imdbId && !tmdbId) continue;

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
}