"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncStatus = void 0;
exports.syncExternalWatchStatus = syncExternalWatchStatus;
exports.syncExternalRatings = syncExternalRatings;
exports.importRatingsFromTrakt = importRatingsFromTrakt;
exports.importRatingsFromSimkl = importRatingsFromSimkl;
exports.importWatchHistoryFromTrakt = importWatchHistoryFromTrakt;
exports.importWatchHistoryFromSimkl = importWatchHistoryFromSimkl;
exports.importPlayHistoryFromTrakt = importPlayHistoryFromTrakt;
exports.syncAllExternalData = syncAllExternalData;
const database_1 = __importDefault(require("../config/database"));
const uuid_1 = require("uuid");
const axios_1 = __importDefault(require("axios"));
const tmdb_1 = require("./tmdb");
// Refresh Trakt access token using stored refresh_token.
// Returns new access token on success, null on failure.
function getUserSetting(userId, key) {
    try {
        const row = database_1.default.prepare('SELECT value FROM user_settings WHERE user_id = ? AND key = ?').get(userId, key);
        if (row)
            return row.value;
        if (key.startsWith('sync_'))
            return 'true';
        return '';
    }
    catch (e) {
        if (key.startsWith('sync_'))
            return 'true';
        return '';
    }
}
function setUserSetting(userId, key, value) {
    database_1.default.prepare('INSERT INTO user_settings (user_id, key, value) VALUES (?, ?, ?) ON CONFLICT(user_id, key) DO UPDATE SET value=excluded.value').run(userId, key, value);
}
async function refreshTraktToken(userId) {
    const clientId = getUserSetting(userId, 'TRAKT_API_KEY');
    const clientSecret = getUserSetting(userId, 'TRAKT_CLIENT_SECRET');
    const refreshToken = getUserSetting(userId, 'TRAKT_REFRESH_TOKEN');
    if (!clientId || !clientSecret || !refreshToken)
        return null;
    try {
        const res = await fetch('https://api.trakt.tv/oauth/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'User-Agent': 'Loom-Media-Server/1.0.0' },
            body: JSON.stringify({ refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret, grant_type: 'refresh_token' }),
        });
        if (!res.ok) {
            console.error('[Trakt] Token refresh failed:', res.status);
            return null;
        }
        const data = await res.json();
        setUserSetting(userId, 'TRAKT_ACCESS_TOKEN', data.access_token);
        if (data.refresh_token)
            setUserSetting(userId, 'TRAKT_REFRESH_TOKEN', data.refresh_token);
        console.log('[Trakt] Access token refreshed successfully.');
        return data.access_token;
    }
    catch (e) {
        console.error('[Trakt] Token refresh error:', e);
        return null;
    }
}
// Make a Trakt API GET request, auto-refreshing token on 401.
async function traktGet(userId, url, headers) {
    try {
        const res = await axios_1.default.get(url, { headers });
        return res.data;
    }
    catch (err) {
        if (err?.response?.status === 401) {
            console.log('[Trakt] 401 received — attempting token refresh...');
            const newToken = await refreshTraktToken(userId);
            if (!newToken)
                throw err;
            const newHeaders = { ...headers, Authorization: `Bearer ${newToken}` };
            const res = await axios_1.default.get(url, { headers: newHeaders });
            return res.data;
        }
        throw err;
    }
}
exports.syncStatus = {
    isSyncing: false,
    progress: 0,
    currentStep: '',
    lastSyncResult: null
};
function normalizeRating(value) {
    const parsed = Number.parseInt(value?.toString?.() ?? '0', 10);
    if (!Number.isFinite(parsed))
        return 0;
    return Math.max(0, Math.min(10, parsed));
}
function isShow(media) {
    const type = media.type?.toString().toLowerCase();
    return type === 'show' || type === 'tv' || type === 'tv show';
}
function buildItem(media) {
    return {
        title: media.title,
        year: media.year ? Number(media.year) : undefined,
        ids: {
            imdb: media.imdb_id || undefined,
            tmdb: media.tmdb_id ? Number(media.tmdb_id) : undefined,
        },
    };
}
function hasExternalId(media) {
    return Boolean(media.imdb_id || media.tmdb_id);
}
function upsertExternalState(userId, args) {
    const tmdbId = args.tmdbId?.toString().trim() || '';
    const imdbId = args.imdbId?.toString().trim() || '';
    if (!tmdbId && !imdbId)
        return;
    const existing = database_1.default.prepare(`
    SELECT tmdb_id FROM external_media_state
    WHERE user_id = ? 
      AND (
           (tmdb_id = ? AND tmdb_id IS NOT NULL)
        OR (imdb_id = ? AND imdb_id IS NOT NULL)
      )
    LIMIT 1
  `).get(userId, tmdbId || null, imdbId || null);
    const resolvedTmdbId = existing?.tmdb_id || tmdbId || imdbId;
    database_1.default.prepare(`
    INSERT INTO external_media_state (tmdb_id, user_id, imdb_id, my_rating, watch_status, source, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(tmdb_id, user_id) DO UPDATE SET
      imdb_id = COALESCE(excluded.imdb_id, external_media_state.imdb_id),
      my_rating = COALESCE(excluded.my_rating, external_media_state.my_rating),
      watch_status = COALESCE(excluded.watch_status, external_media_state.watch_status),
      source = excluded.source,
      updated_at = CURRENT_TIMESTAMP
  `).run(resolvedTmdbId, userId, imdbId || null, args.myRating ?? null, args.watchStatus ?? null, args.source);
}
async function syncTrakt(userId, media, rating) {
    if (getUserSetting(userId, 'sync_trakt_ratings') === 'false') {
        console.log('[Sync] Trakt ratings sync disabled by user settings.');
        return;
    }
    const traktApiKey = getUserSetting(userId, 'TRAKT_API_KEY');
    const traktAccessToken = getUserSetting(userId, 'TRAKT_ACCESS_TOKEN');
    if (!traktApiKey || !traktAccessToken || !hasExternalId(media))
        return;
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
        await axios_1.default.delete('https://api.trakt.tv/sync/ratings', { headers, data: body });
        return;
    }
    await axios_1.default.post('https://api.trakt.tv/sync/ratings', body, { headers });
}
async function syncSimkl(userId, media, rating) {
    if (getUserSetting(userId, 'sync_simkl_ratings') === 'false') {
        console.log('[Sync] Simkl ratings sync disabled by user settings.');
        return;
    }
    const simklClientId = getUserSetting(userId, 'SIMKL_CLIENT_ID');
    const simklAccessToken = getUserSetting(userId, 'SIMKL_ACCESS_TOKEN');
    if (!simklClientId || !simklAccessToken || !hasExternalId(media))
        return;
    const headers = {
        'simkl-api-key': simklClientId,
        'Content-Type': 'application/json',
        Authorization: `Bearer ${simklAccessToken}`,
    };
    const item = buildItem(media);
    if (rating === 0) {
        const body = isShow(media) ? { shows: [item] } : { movies: [item] };
        await axios_1.default.post('https://api.simkl.com/sync/remove-ratings', body, { headers });
        return;
    }
    const body = isShow(media)
        ? { shows: [{ ...item, rating }] }
        : { movies: [{ ...item, rating }] };
    await axios_1.default.post('https://api.simkl.com/sync/add-ratings', body, { headers });
}
async function syncTmdb(media, rating) {
    const tmdbUserAuth = tmdb_1.tmdbService.getSetting('TMDB_USER_AUTH');
    if (!tmdbUserAuth || !media.tmdb_id)
        return;
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
        await axios_1.default.delete(path, config);
        return;
    }
    await axios_1.default.post(path, { value: rating }, config);
}
async function syncTraktWatchStatus(userId, media, isWatched) {
    if (getUserSetting(userId, 'sync_trakt_watched') === 'false') {
        console.log('[Sync] Trakt watched status sync disabled by user settings.');
        return;
    }
    const traktApiKey = getUserSetting(userId, 'TRAKT_API_KEY');
    const traktAccessToken = getUserSetting(userId, 'TRAKT_ACCESS_TOKEN');
    if (!traktApiKey || !traktAccessToken || !hasExternalId(media))
        return;
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
    await axios_1.default.post(path, body, { headers });
}
async function syncSimklWatchStatus(userId, media, isWatched) {
    if (getUserSetting(userId, 'sync_simkl_watched') === 'false') {
        console.log('[Sync] Simkl watched status sync disabled by user settings.');
        return;
    }
    const simklClientId = getUserSetting(userId, 'SIMKL_CLIENT_ID');
    const simklAccessToken = getUserSetting(userId, 'SIMKL_ACCESS_TOKEN');
    if (!simklClientId || !simklAccessToken || !hasExternalId(media))
        return;
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
    await axios_1.default.post(path, body, { headers });
}
async function syncExternalWatchStatus(userId, media, isWatched) {
    try {
        await syncTraktWatchStatus(userId, media, isWatched);
    }
    catch (error) {
        console.error('[Playback Sync] Trakt watch status sync failed:', error);
    }
    try {
        await syncSimklWatchStatus(userId, media, isWatched);
    }
    catch (error) {
        console.error('[Playback Sync] Simkl watch status sync failed:', error);
    }
}
async function syncExternalRatings(userId, media, rawRating) {
    const rating = normalizeRating(rawRating);
    try {
        await syncTrakt(userId, media, rating);
    }
    catch (error) {
        console.error('[Rating Sync] Trakt sync failed:', error);
    }
    try {
        await syncSimkl(userId, media, rating);
    }
    catch (error) {
        console.error('[Rating Sync] Simkl sync failed:', error);
    }
    try {
        await syncTmdb(media, rating);
    }
    catch (error) {
        console.error('[Rating Sync] TMDB sync failed:', error);
    }
}
// Background Import for Trakt.tv Ratings
async function importRatingsFromTrakt(userId) {
    if (getUserSetting(userId, 'sync_trakt_ratings') === 'false') {
        console.log('[Rating Sync] Trakt ratings import disabled by user settings.');
        return 0;
    }
    const traktApiKey = getUserSetting(userId, 'TRAKT_API_KEY');
    const traktAccessToken = getUserSetting(userId, 'TRAKT_ACCESS_TOKEN');
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
        // Fetch rated movies from Trakt (auto-refreshes token on 401)
        const ratedMovies = await traktGet(userId, 'https://api.trakt.tv/sync/ratings/movies', headers);
        if (!Array.isArray(ratedMovies))
            return 0;
        for (const entry of ratedMovies) {
            const ratingValue = entry.rating;
            const imdbId = entry.movie?.ids?.imdb;
            const tmdbId = entry.movie?.ids?.tmdb?.toString();
            if (!imdbId && !tmdbId)
                continue;
            upsertExternalState(userId, {
                tmdbId,
                imdbId,
                myRating: ratingValue.toString(),
                source: 'trakt',
            });
            // Find matched film in Loom SQLite
            const movie = database_1.default.prepare(`
        SELECT id FROM media_items 
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL) 
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null);
            if (movie) {
                database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'my_rating', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id, ratingValue.toString());
                importCount++;
            }
        }
        console.log(`[Rating Sync] Trakt ratings import complete. Synced ${importCount} ratings to Loom database!`);
    }
    catch (err) {
        console.error('[Rating Sync] Failed to import ratings from Trakt:', err);
    }
    return importCount;
}
// Background Import for Simkl Ratings
async function importRatingsFromSimkl(userId) {
    if (getUserSetting(userId, 'sync_simkl_ratings') === 'false') {
        console.log('[Rating Sync] Simkl ratings import disabled by user settings.');
        return 0;
    }
    const simklClientId = getUserSetting(userId, 'SIMKL_CLIENT_ID');
    const simklAccessToken = getUserSetting(userId, 'SIMKL_ACCESS_TOKEN');
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
        const response = await axios_1.default.get('https://api.simkl.com/sync/ratings', { headers });
        const data = response.data;
        const ratedMovies = data.movies;
        if (!Array.isArray(ratedMovies))
            return 0;
        for (const entry of ratedMovies) {
            const ratingValue = entry.user_rating ?? entry.rating;
            if (ratingValue === undefined || ratingValue === null)
                continue;
            const imdbId = entry.movie?.ids?.imdb;
            const tmdbId = entry.movie?.ids?.tmdb;
            if (!imdbId && !tmdbId)
                continue;
            upsertExternalState(userId, {
                tmdbId: tmdbId?.toString() ?? null,
                imdbId,
                myRating: ratingValue.toString(),
                source: 'simkl',
            });
            // Find matched film in Loom SQLite
            const movie = database_1.default.prepare(`
        SELECT id FROM media_items 
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL) 
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null);
            if (movie) {
                database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'my_rating', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id, ratingValue.toString());
                importCount++;
            }
        }
        console.log(`[Rating Sync] Simkl ratings import complete. Synced ${importCount} ratings to Loom database!`);
    }
    catch (err) {
        console.error('[Rating Sync] Failed to import ratings from Simkl:', err);
    }
    return importCount;
}
// Background Import for Trakt Watch History / Seen Status
async function importWatchHistoryFromTrakt(userId) {
    if (getUserSetting(userId, 'sync_trakt_watched') === 'false') {
        console.log('[Playback Sync] Trakt watched status import disabled by user settings.');
        return 0;
    }
    const traktApiKey = getUserSetting(userId, 'TRAKT_API_KEY');
    const traktAccessToken = getUserSetting(userId, 'TRAKT_ACCESS_TOKEN');
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
        const watchedMovies = await traktGet(userId, 'https://api.trakt.tv/sync/watched/movies', headers);
        if (!Array.isArray(watchedMovies))
            return 0;
        for (const entry of watchedMovies) {
            const imdbId = entry.movie?.ids?.imdb;
            const tmdbId = entry.movie?.ids?.tmdb?.toString();
            const plays = typeof entry.plays === 'number' && entry.plays > 0 ? entry.plays : 1;
            if (!imdbId && !tmdbId)
                continue;
            upsertExternalState(userId, {
                tmdbId,
                imdbId,
                watchStatus: 'watched',
                source: 'trakt',
            });
            const movie = database_1.default.prepare(`
        SELECT id FROM media_items
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL)
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null);
            if (movie) {
                // 1. Set watch_status = 'watched' in media_metadata
                database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, 'watch_status', 'watched')
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id);
                // 2. Set watch_history + play_count from Trakt
                const existingHistory = database_1.default.prepare(`
          SELECT id FROM watch_history
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(userId, movie.id);
                if (existingHistory) {
                    database_1.default.prepare(`
            UPDATE watch_history
            SET is_watched = 1, play_count = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(plays, existingHistory.id);
                }
                else {
                    database_1.default.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, play_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          `).run((0, uuid_1.v4)(), userId, movie.id, 7200, 7200, 1, plays);
                }
                importCount++;
            }
        }
        console.log(`[Playback Sync] Trakt watch history import complete. Synced ${importCount} items as watched!`);
    }
    catch (err) {
        console.error('[Playback Sync] Failed to import watch history from Trakt:', err);
    }
    return importCount;
}
// Background Import for Simkl Watch History / Seen Status
async function importWatchHistoryFromSimkl(userId) {
    if (getUserSetting(userId, 'sync_simkl_watched') === 'false') {
        console.log('[Playback Sync] Simkl watched status import disabled by user settings.');
        return 0;
    }
    const simklClientId = getUserSetting(userId, 'SIMKL_CLIENT_ID');
    const simklAccessToken = getUserSetting(userId, 'SIMKL_ACCESS_TOKEN');
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
        const response = await axios_1.default.get('https://api.simkl.com/sync/all-items/movies/completed', { headers });
        const data = response.data;
        let watchedMovies = [];
        if (Array.isArray(data)) {
            watchedMovies = data;
        }
        else if (data && Array.isArray(data.movies)) {
            watchedMovies = data.movies;
        }
        if (!Array.isArray(watchedMovies) || watchedMovies.length === 0)
            return 0;
        for (const entry of watchedMovies) {
            const imdbId = entry.movie?.ids?.imdb;
            const tmdbId = entry.movie?.ids?.tmdb;
            const timesWatched = typeof entry.times_watched === 'number' && entry.times_watched > 0 ? entry.times_watched : 1;
            if (!imdbId && !tmdbId)
                continue;
            upsertExternalState(userId, {
                tmdbId: tmdbId?.toString() ?? null,
                imdbId,
                watchStatus: 'watched',
                source: 'simkl',
            });
            const movie = database_1.default.prepare(`
        SELECT id FROM media_items
        WHERE (imdb_id = ? AND imdb_id IS NOT NULL)
           OR (tmdb_id = ? AND tmdb_id IS NOT NULL)
      `).get(imdbId ?? null, tmdbId ?? null);
            if (movie) {
                // 1. Set watch_status = 'watched' in media_metadata
                database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, 'watch_status', 'watched')
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id);
                // 2. Set watch_history + play_count from SIMKL
                const existingHistory = database_1.default.prepare(`
          SELECT id FROM watch_history
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(userId, movie.id);
                if (existingHistory) {
                    database_1.default.prepare(`
            UPDATE watch_history
            SET is_watched = 1, play_count = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(timesWatched, existingHistory.id);
                }
                else {
                    database_1.default.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, play_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          `).run((0, uuid_1.v4)(), userId, movie.id, 7200, 7200, 1, timesWatched);
                }
                importCount++;
            }
        }
        console.log(`[Playback Sync] Simkl watch history import complete. Synced ${importCount} items as watched!`);
    }
    catch (err) {
        console.error('[Playback Sync] Failed to import watch history from Simkl:', err);
    }
    return importCount;
}
// Import full Trakt play history (individual play events with real timestamps).
// Uses /sync/history/movies which is paginated and supports delta sync via start_at.
async function importPlayHistoryFromTrakt(userId) {
    if (getUserSetting(userId, 'sync_trakt_watched') === 'false')
        return 0;
    const traktApiKey = getUserSetting(userId, 'TRAKT_API_KEY');
    const traktAccessToken = getUserSetting(userId, 'TRAKT_ACCESS_TOKEN');
    if (!traktApiKey || !traktAccessToken)
        return 0;
    const headers = {
        'trakt-api-key': traktApiKey,
        'trakt-api-version': '2',
        'Content-Type': 'application/json',
        'User-Agent': 'Loom-Media-Server/1.0.0',
        Authorization: `Bearer ${traktAccessToken}`,
    };
    const lastSync = getUserSetting(userId, 'trakt_play_history_sync_at');
    const startAt = lastSync ? `&start_at=${encodeURIComponent(lastSync)}` : '';
    let importCount = 0;
    let page = 1;
    try {
        console.log(`[Play History] Starting Trakt play history import (userId=${userId}, delta=${!!lastSync})...`);
        while (true) {
            const url = `https://api.trakt.tv/sync/history/movies?limit=1000&page=${page}${startAt}`;
            // Use axios directly to capture response headers for pagination; traktGet only returns data
            let res;
            try {
                res = await axios_1.default.get(url, { headers });
            }
            catch (err) {
                if (err?.response?.status === 401) {
                    const newToken = await refreshTraktToken(userId);
                    if (!newToken)
                        throw err;
                    headers.Authorization = `Bearer ${newToken}`;
                    res = await axios_1.default.get(url, { headers });
                }
                else {
                    throw err;
                }
            }
            const entries = res.data;
            const pageCount = parseInt(res.headers['x-pagination-page-count'] ?? '1', 10);
            if (!Array.isArray(entries) || entries.length === 0)
                break;
            for (const entry of entries) {
                const imdbId = entry.movie?.ids?.imdb;
                const tmdbId = entry.movie?.ids?.tmdb?.toString();
                if (!imdbId && !tmdbId)
                    continue;
                const movie = database_1.default.prepare(`
          SELECT id FROM media_items
          WHERE ((imdb_id = ? AND imdb_id IS NOT NULL) OR (tmdb_id = ? AND tmdb_id IS NOT NULL))
            AND deleted_at IS NULL
        `).get(imdbId ?? null, tmdbId ?? null);
                if (!movie)
                    continue;
                // INSERT OR IGNORE — trakt_history_id UNIQUE prevents duplicates on re-sync
                database_1.default.prepare(`
          INSERT OR IGNORE INTO play_history (id, user_id, media_item_id, watched_at, source, trakt_history_id)
          VALUES (?, ?, ?, ?, 'trakt', ?)
        `).run((0, uuid_1.v4)(), userId, movie.id, entry.watched_at, entry.id);
                importCount++;
            }
            if (page >= pageCount)
                break;
            page++;
        }
        // Update play_count in watch_history to reflect total plays from Trakt
        const countRows = database_1.default.prepare(`
      SELECT media_item_id, COUNT(*) as cnt
      FROM play_history
      WHERE user_id = ? AND source = 'trakt'
      GROUP BY media_item_id
    `).all(userId);
        for (const row of countRows) {
            database_1.default.prepare(`
        UPDATE watch_history SET play_count = ?
        WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
      `).run(row.cnt, userId, row.media_item_id);
        }
        setUserSetting(userId, 'trakt_play_history_sync_at', new Date().toISOString());
        console.log(`[Play History] Trakt import complete. ${importCount} new entries.`);
    }
    catch (err) {
        console.error('[Play History] Trakt import failed:', err);
    }
    return importCount;
}
async function syncAllExternalData() {
    if (exports.syncStatus.isSyncing) {
        console.log('[Sync] A synchronization process is already active. Skipping duplicate trigger.');
        return;
    }
    console.log('[Sync] Starting full external data sync...');
    exports.syncStatus.isSyncing = true;
    exports.syncStatus.progress = 0;
    exports.syncStatus.currentStep = 'Initierar synkning...';
    exports.syncStatus.lastSyncResult = null;
    let totalTraktRatings = 0;
    let totalTraktWatched = 0;
    let totalTraktHistory = 0;
    let totalSimklRatings = 0;
    let totalSimklWatched = 0;
    try {
        const users = database_1.default.prepare('SELECT id FROM users').all();
        for (const user of users) {
            const userId = user.id;
            // Step 1: Trakt Ratings
            exports.syncStatus.progress = 10;
            exports.syncStatus.currentStep = 'Synkroniserar betyg från Trakt.tv...';
            totalTraktRatings += await importRatingsFromTrakt(userId);
            // Step 2: Trakt Watched Status
            exports.syncStatus.progress = 30;
            exports.syncStatus.currentStep = 'Synkroniserar sedda filmer från Trakt.tv...';
            totalTraktWatched += await importWatchHistoryFromTrakt(userId);
            // Step 3: Trakt Full Play History (individual plays with real timestamps)
            exports.syncStatus.progress = 50;
            exports.syncStatus.currentStep = 'Synkroniserar spelhistorik från Trakt.tv...';
            totalTraktHistory += await importPlayHistoryFromTrakt(userId);
            // Step 4: Simkl Ratings
            exports.syncStatus.progress = 70;
            exports.syncStatus.currentStep = 'Synkroniserar betyg från Simkl...';
            totalSimklRatings += await importRatingsFromSimkl(userId);
            // Step 5: Simkl Watched Status
            exports.syncStatus.progress = 85;
            exports.syncStatus.currentStep = 'Synkroniserar sedda filmer från Simkl...';
            totalSimklWatched += await importWatchHistoryFromSimkl(userId);
        }
        exports.syncStatus.progress = 100;
        exports.syncStatus.currentStep = 'Synkronisering klar!';
        exports.syncStatus.lastSyncResult = {
            timestamp: new Date().toISOString(),
            success: true,
            trakt: { ratings: totalTraktRatings, watched: totalTraktWatched, history: totalTraktHistory },
            simkl: { ratings: totalSimklRatings, watched: totalSimklWatched }
        };
        console.log('[Sync] Full external data sync finished successfully.', exports.syncStatus.lastSyncResult);
    }
    catch (error) {
        exports.syncStatus.progress = 100;
        exports.syncStatus.currentStep = 'Synkronisering misslyckades!';
        exports.syncStatus.lastSyncResult = {
            timestamp: new Date().toISOString(),
            success: false,
            error: error.message || String(error)
        };
        console.error('[Sync] Full external data sync failed:', error);
    }
    finally {
        exports.syncStatus.isSyncing = false;
    }
}
