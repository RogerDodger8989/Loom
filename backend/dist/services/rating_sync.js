"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncExternalRatings = syncExternalRatings;
exports.importRatingsFromTrakt = importRatingsFromTrakt;
exports.importRatingsFromSimkl = importRatingsFromSimkl;
const axios_1 = __importDefault(require("axios"));
const tmdb_1 = require("./tmdb");
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
async function syncTrakt(media, rating) {
    const traktApiKey = tmdb_1.tmdbService.getSetting('TRAKT_API_KEY');
    const traktAccessToken = tmdb_1.tmdbService.getSetting('TRAKT_ACCESS_TOKEN');
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
async function syncSimkl(media, rating) {
    const simklClientId = tmdb_1.tmdbService.getSetting('SIMKL_CLIENT_ID');
    const simklAccessToken = tmdb_1.tmdbService.getSetting('SIMKL_ACCESS_TOKEN');
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
const database_1 = __importDefault(require("../config/database"));
const uuid_1 = require("uuid");
async function syncExternalRatings(media, rawRating) {
    const rating = normalizeRating(rawRating);
    try {
        await syncTrakt(media, rating);
    }
    catch (error) {
        console.error('[Rating Sync] Trakt sync failed:', error);
    }
    try {
        await syncSimkl(media, rating);
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
async function importRatingsFromTrakt() {
    const traktApiKey = tmdb_1.tmdbService.getSetting('TRAKT_API_KEY');
    const traktAccessToken = tmdb_1.tmdbService.getSetting('TRAKT_ACCESS_TOKEN');
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
        const response = await axios_1.default.get('https://api.trakt.tv/sync/ratings/movies', { headers });
        const ratedMovies = response.data;
        if (!Array.isArray(ratedMovies))
            return;
        let importCount = 0;
        for (const entry of ratedMovies) {
            const ratingValue = entry.rating;
            const imdbId = entry.movie?.ids?.imdb;
            const tmdbId = entry.movie?.ids?.tmdb?.toString();
            if (!imdbId && !tmdbId)
                continue;
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
}
// Background Import for Simkl Ratings
async function importRatingsFromSimkl() {
    const simklClientId = tmdb_1.tmdbService.getSetting('SIMKL_CLIENT_ID');
    const simklAccessToken = tmdb_1.tmdbService.getSetting('SIMKL_ACCESS_TOKEN');
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
        const response = await axios_1.default.get('https://api.simkl.com/sync/ratings', { headers });
        const data = response.data;
        const ratedMovies = data.movies;
        if (!Array.isArray(ratedMovies))
            return;
        let importCount = 0;
        for (const entry of ratedMovies) {
            const ratingValue = entry.user_rating ?? entry.rating;
            if (ratingValue === undefined || ratingValue === null)
                continue;
            const imdbId = entry.movie?.ids?.imdb;
            const tmdbId = entry.movie?.ids?.tmdb;
            if (!imdbId && !tmdbId)
                continue;
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
}
