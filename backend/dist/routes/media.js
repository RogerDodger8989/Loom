"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = mediaRoutes;
const database_1 = __importDefault(require("../config/database"));
const axios_1 = __importDefault(require("axios"));
const tmdb_1 = require("../services/tmdb");
const uuid_1 = require("uuid");
const path_1 = __importDefault(require("path"));
const rating_sync_1 = require("../services/rating_sync");
function normalizeRatingValue(value) {
    if (value === undefined || value === null)
        return null;
    const cleaned = value.toString().trim().replace(',', '.').replace(/[^0-9.]/g, '');
    if (!cleaned)
        return null;
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? parsed.toString() : null;
}
function normalizeVotesValue(value) {
    if (value === undefined || value === null)
        return null;
    const cleaned = value.toString().replace(/[^0-9]/g, '');
    if (!cleaned)
        return null;
    const parsed = Number.parseInt(cleaned, 10);
    return Number.isFinite(parsed) ? parsed.toString() : null;
}
function extractSimklId(payload) {
    const candidates = [
        payload,
        payload?.movie,
        payload?.show,
        payload?.anime,
        payload?.item,
        payload?.data,
        payload?.result,
    ].filter(Boolean);
    for (const candidate of candidates) {
        const rawId = candidate?.ids?.simkl ?? candidate?.simkl ?? candidate?.simkl_id ?? candidate?.id;
        if (rawId === undefined || rawId === null) {
            continue;
        }
        const cleaned = rawId.toString().trim();
        if (!cleaned) {
            continue;
        }
        return cleaned;
    }
    return null;
}
function extractSimklRatings(payload) {
    const candidates = [
        payload,
        payload?.movie,
        payload?.show,
        payload?.anime,
        payload?.item,
        payload?.data,
        payload?.result,
    ].filter(Boolean);
    let simklRating = null;
    let simklVotes = null;
    for (const candidate of candidates) {
        const ratings = candidate?.ratings || {};
        simklRating = simklRating
            || normalizeRatingValue(ratings?.simkl?.rating)
            || normalizeRatingValue(ratings?.simkl_rating)
            || normalizeRatingValue(candidate?.simkl?.rating)
            || normalizeRatingValue(candidate?.simkl_rating)
            || normalizeRatingValue(candidate?.simklRating)
            || normalizeRatingValue(candidate?.rating);
        simklVotes = simklVotes
            || normalizeVotesValue(ratings?.simkl?.votes)
            || normalizeVotesValue(ratings?.simkl_votes)
            || normalizeVotesValue(candidate?.simkl?.votes)
            || normalizeVotesValue(candidate?.simkl_votes)
            || normalizeVotesValue(candidate?.simklVotes)
            || normalizeVotesValue(candidate?.votes);
        if (simklRating && simklVotes) {
            break;
        }
    }
    return {
        simklRating,
        simklVotes,
    };
}
function extractTraktRatings(payload) {
    const candidates = [
        payload,
        payload?.movie,
        payload?.show,
        payload?.anime,
        payload?.item,
        payload?.data,
        payload?.result,
    ].filter(Boolean);
    let simklRating = null;
    let simklVotes = null;
    let traktRating = null;
    let traktVotes = null;
    for (const candidate of candidates) {
        const ratings = candidate?.ratings || {};
        const nestedMovie = candidate?.movie || {};
        const nestedShow = candidate?.show || {};
        traktRating = traktRating
            || normalizeRatingValue(ratings?.trakt?.rating)
            || normalizeRatingValue(ratings?.trakt_rating)
            || normalizeRatingValue(candidate?.rating)
            || normalizeRatingValue(nestedMovie?.rating)
            || normalizeRatingValue(nestedShow?.rating)
            || normalizeRatingValue(candidate?.trakt?.rating)
            || normalizeRatingValue(candidate?.trakt_rating)
            || normalizeRatingValue(candidate?.traktRating);
        traktVotes = traktVotes
            || normalizeVotesValue(ratings?.trakt?.votes)
            || normalizeVotesValue(ratings?.trakt_votes)
            || normalizeVotesValue(candidate?.votes)
            || normalizeVotesValue(nestedMovie?.votes)
            || normalizeVotesValue(nestedShow?.votes)
            || normalizeVotesValue(candidate?.trakt?.votes)
            || normalizeVotesValue(candidate?.trakt_votes)
            || normalizeVotesValue(candidate?.traktVotes);
        if (traktRating && traktVotes) {
            break;
        }
    }
    return {
        traktRating,
        traktVotes,
    };
}
async function fetchTraktRatingsByImdb(imdbId, traktApiKey, mediaType) {
    const traktRes = await axios_1.default.get(`https://api.trakt.tv/search/imdb/${imdbId}`, {
        params: {
            type: mediaType,
            extended: 'full',
        },
        headers: {
            'trakt-api-key': traktApiKey,
            'trakt-api-version': '2',
            'User-Agent': 'Loom/1.0',
        },
    });
    const traktData = Array.isArray(traktRes.data) ? traktRes.data[0] : traktRes.data;
    return extractTraktRatings(traktData);
}
async function mediaRoutes(fastify) {
    // Set up auth guard hook for all media routes
    fastify.addHook('preValidation', async (request, reply) => {
        try {
            await request.jwtVerify();
        }
        catch (err) {
            reply.code(401).send({ error: 'Unauthorized: Access token required' });
        }
    });
    // GET /api/media/movies
    // Retrieves movies with automatic SQL-level content filtering based on user restrictions
    fastify.get('/api/media/movies', async (request, reply) => {
        const user = request.user;
        const mergeVersions = request.query.mergeVersions !== 'false'; // Default to true (merged mode)
        try {
            // Query to get all movies that are NOT restricted for this user
            // Excludes matches on GENRE, RATING, or KEYWORD restriction patterns completely at the DB layer
            const moviesQuery = `
          SELECT mi.*, (SELECT MAX(updated_at) FROM watch_history wh WHERE wh.media_item_id = mi.id) as last_watched_at FROM media_items mi
          WHERE mi.type = 'Movie'
          AND mi.id NOT IN (
            SELECT mm.media_item_id 
            FROM media_metadata mm
            JOIN user_restrictions ur ON ur.user_id = ?
            WHERE 
              (ur.restriction_type = 'GENRE' AND mm.metadata_key = 'genre' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'RATING' AND mm.metadata_key = 'rating' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'KEYWORD' AND mm.metadata_key = 'keyword' AND mm.metadata_value LIKE '%' || ur.restriction_value || '%')
          )
        `;
            const rawMovies = database_1.default.prepare(moviesQuery).all(user.id);
            // Fetch metadata for each movie
            const moviesWithMetadata = rawMovies.map(movie => {
                const metadataRows = database_1.default.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(movie.id);
                const metadata = {};
                metadataRows.forEach(row => {
                    metadata[row.metadata_key] = row.metadata_value;
                });
                return {
                    ...movie,
                    metadata,
                    resolution: metadata.resolution || '1080p'
                };
            });
            if (mergeVersions) {
                // Merged Mode: group movies by their TMDB ID or title if TMDB ID is missing
                const mergedMovies = {};
                moviesWithMetadata.forEach(movie => {
                    const groupKey = movie.tmdb_id || movie.title;
                    if (!mergedMovies[groupKey]) {
                        mergedMovies[groupKey] = {
                            id: movie.id,
                            title: movie.title,
                            type: movie.type,
                            tmdb_id: movie.tmdb_id,
                            imdb_id: movie.imdb_id,
                            poster_path: movie.poster_path,
                            fanart_path: movie.fanart_path,
                            plot: movie.plot,
                            year: movie.year,
                            last_watched_at: movie.last_watched_at,
                            genre: movie.genre || movie.metadata.genre || 'Movie',
                            added_at: movie.added_at,
                            metadata: movie.metadata,
                            versions: []
                        };
                    }
                    mergedMovies[groupKey].versions.push({
                        id: movie.id,
                        file_path: movie.file_path,
                        resolution: movie.resolution
                    });
                });
                return reply.send(Object.values(mergedMovies));
            }
            else {
                // Separated Mode: Return items individually and add a clear visual badge indicator
                const badgedMovies = moviesWithMetadata.map(movie => ({
                    ...movie,
                    last_watched_at: movie.last_watched_at,
                    resolution_badge: movie.resolution // e.g. "4K" or "1080p"
                }));
                return reply.send(badgedMovies);
            }
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to retrieve movies' });
        }
    });
    // POST /api/media/items/:id/metadata
    // Upsert a metadata key/value for a given media item (used to save user-specific state like ratings)
    fastify.post('/api/media/items/:id/metadata', async (request, reply) => {
        const user = request.user;
        const { id } = request.params;
        const { key, value } = request.body;
        try {
            const movie = database_1.default.prepare(`SELECT * FROM media_items WHERE id = ?`).get(id);
            if (!movie)
                return reply.code(404).send({ error: 'Media item not found' });
            // Upsert into media_metadata (use JSON-stringified value for complex objects)
            const stringVal = typeof value === 'string' ? value : JSON.stringify(value);
            database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, ?, ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id, key, stringVal);
            if (key === 'my_rating') {
                await (0, rating_sync_1.syncExternalRatings)(movie, value);
            }
            return reply.code(200).send({ ok: true });
        }
        catch (err) {
            request.log.error(err);
            return reply.code(500).send({ error: 'Failed to save metadata', details: err.message });
        }
    });
    // GET /api/media/items/:id/metadata-state
    // Returns metadata values together with lock flags for editor UIs.
    fastify.get('/api/media/items/:id/metadata-state', async (request, reply) => {
        const { id } = request.params;
        try {
            const item = database_1.default.prepare(`SELECT id FROM media_items WHERE id = ?`).get(id);
            if (!item)
                return reply.code(404).send({ error: 'Media item not found' });
            const rows = database_1.default.prepare(`
          SELECT metadata_key, metadata_value, is_locked
          FROM media_metadata
          WHERE media_item_id = ?
        `).all(id);
            const metadata = {};
            rows.forEach(row => {
                try {
                    metadata[row.metadata_key] = { value: JSON.parse(row.metadata_value), is_locked: row.is_locked === 1 };
                }
                catch {
                    metadata[row.metadata_key] = { value: row.metadata_value, is_locked: row.is_locked === 1 };
                }
            });
            return reply.send({ id, metadata });
        }
        catch (err) {
            request.log.error(err);
            return reply.code(500).send({ error: 'Failed to fetch metadata state', details: err.message });
        }
    });
    // PUT /api/media/items/:id/metadata-lock
    // Toggle lock state for a single metadata key.
    fastify.put('/api/media/items/:id/metadata-lock', async (request, reply) => {
        const { id } = request.params;
        const { key, isLocked } = request.body || {};
        if (!key) {
            return reply.code(400).send({ error: 'metadata key is required' });
        }
        try {
            const item = database_1.default.prepare(`SELECT id FROM media_items WHERE id = ?`).get(id);
            if (!item)
                return reply.code(404).send({ error: 'Media item not found' });
            const existing = database_1.default.prepare(`
          SELECT id FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?
        `).get(id, key);
            if (!existing) {
                database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value, is_locked)
            VALUES (?, ?, ?, ?, ?)
          `).run((0, uuid_1.v4)(), id, key, '', isLocked ? 1 : 0);
            }
            else {
                database_1.default.prepare(`
            UPDATE media_metadata
            SET is_locked = ?
            WHERE media_item_id = ? AND metadata_key = ?
          `).run(isLocked ? 1 : 0, id, key);
            }
            return reply.send({ ok: true });
        }
        catch (err) {
            request.log.error(err);
            return reply.code(500).send({ error: 'Failed to update metadata lock', details: err.message });
        }
    });
    // PATCH /api/media/items/:id
    // Update core media_items fields used by the editor modal.
    fastify.patch('/api/media/items/:id', async (request, reply) => {
        const { id } = request.params;
        const body = request.body || {};
        try {
            const item = database_1.default.prepare(`SELECT id FROM media_items WHERE id = ?`).get(id);
            if (!item)
                return reply.code(404).send({ error: 'Media item not found' });
            const allowed = ['title', 'original_title', 'plot', 'genre', 'year', 'poster_path', 'fanart_path', 'director', 'collection_name', 'collection_id', 'imdb_id', 'tmdb_id'];
            const updates = [];
            const params = [];
            for (const key of allowed) {
                if (body[key] !== undefined) {
                    updates.push(`${key} = ?`);
                    if (key === 'year') {
                        params.push(body[key] === '' || body[key] === null ? null : Number(body[key]));
                    }
                    else {
                        params.push(body[key]);
                    }
                }
            }
            if (updates.length === 0) {
                return reply.send({ ok: true, updated: 0 });
            }
            params.push(id);
            database_1.default.prepare(`UPDATE media_items SET ${updates.join(', ')} WHERE id = ?`).run(...params);
            return reply.send({ ok: true, updated: updates.length });
        }
        catch (err) {
            request.log.error(err);
            return reply.code(500).send({ error: 'Failed to update media item', details: err.message });
        }
    });
    // POST /api/media/items/:id/seen
    // Toggle seen status for a given media item, update DB (media_metadata & watch_history) and sync to Trakt/Simkl
    fastify.post('/api/media/items/:id/seen', async (request, reply) => {
        const user = request.user;
        const { id } = request.params;
        const { watched, isWatched } = request.body || {};
        const isWatchedBool = watched !== undefined ? watched : (isWatched ?? true);
        try {
            const movie = database_1.default.prepare(`SELECT * FROM media_items WHERE id = ?`).get(id);
            if (!movie)
                return reply.code(404).send({ error: 'Media item not found' });
            const statusStr = isWatchedBool ? 'watched' : 'unwatched';
            // 1. Update media_metadata for watch_status
            database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'watch_status', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id, statusStr);
            // 2. Update watch_history to prevent duplicate rows for the same user & media item
            const existingHistory = database_1.default.prepare(`
          SELECT id FROM watch_history 
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(user.id, movie.id);
            if (existingHistory) {
                database_1.default.prepare(`
            UPDATE watch_history 
            SET is_watched = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(isWatchedBool ? 1 : 0, existingHistory.id);
            }
            else {
                database_1.default.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, 0, 0, ?, CURRENT_TIMESTAMP)
          `).run((0, uuid_1.v4)(), user.id, movie.id, isWatchedBool ? 1 : 0);
            }
            // 3. Sync to external APIs in background
            (0, rating_sync_1.syncExternalWatchStatus)(movie, isWatchedBool).catch(err => {
                console.error('[Seen Route] syncExternalWatchStatus failed:', err);
            });
            return reply.code(200).send({ ok: true, watch_status: statusStr });
        }
        catch (err) {
            request.log.error(err);
            return reply.code(500).send({ error: 'Failed to update seen status', details: err.message });
        }
    });
    // POST /api/media/items/:id/progress
    // Save play progress (heartbeat/scrobbling) and toggle watched state if progress is >= 90%
    fastify.post('/api/media/items/:id/progress', async (request, reply) => {
        const user = request.user;
        const { id } = request.params;
        const { position, duration, positionSeconds, durationSeconds } = request.body || {};
        const posSec = positionSeconds !== undefined ? positionSeconds : (position ?? 0);
        const durSec = durationSeconds !== undefined ? durationSeconds : (duration ?? 0);
        if (durSec <= 0) {
            return reply.code(400).send({ error: 'Duration must be greater than 0' });
        }
        try {
            const movie = database_1.default.prepare(`SELECT * FROM media_items WHERE id = ?`).get(id);
            if (!movie)
                return reply.code(404).send({ error: 'Media item not found' });
            const progressPercent = posSec / durSec;
            const autoWatch = progressPercent >= 0.90;
            // 1. Update playback_progress and duration in media_metadata
            database_1.default.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'playback_progress', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run((0, uuid_1.v4)(), movie.id, posSec.toString());
            if (durSec > 0) {
                database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, 'duration', ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run((0, uuid_1.v4)(), movie.id, durSec.toString());
            }
            // 2. If >= 90%, update watch_status in media_metadata to 'watched'
            let currentStatus = 'unwatched';
            if (autoWatch) {
                currentStatus = 'watched';
                database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, 'watch_status', 'watched')
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run((0, uuid_1.v4)(), movie.id);
            }
            // 3. Update watch_history
            const existingHistory = database_1.default.prepare(`
          SELECT id FROM watch_history 
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(user.id, movie.id);
            if (existingHistory) {
                database_1.default.prepare(`
            UPDATE watch_history 
            SET last_position_seconds = ?, total_duration_seconds = ?, is_watched = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(posSec, durSec, autoWatch ? 1 : 0, existingHistory.id);
            }
            else {
                database_1.default.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          `).run((0, uuid_1.v4)(), user.id, movie.id, posSec, durSec, autoWatch ? 1 : 0);
            }
            // 4. Sync to Trakt/Simkl if threshold met
            if (autoWatch) {
                (0, rating_sync_1.syncExternalWatchStatus)(movie, true).catch(err => {
                    console.error('[Progress Route] syncExternalWatchStatus failed:', err);
                });
            }
            return reply.code(200).send({ ok: true, position: posSec, duration: durSec, watch_status: currentStatus });
        }
        catch (err) {
            request.log.error(err);
            return reply.code(500).send({ error: 'Failed to update progress', details: err.message });
        }
    });
    // GET /api/media/items/:id
    // Retrieves full details for a specific media item (Loom Media Details page)
    fastify.get('/api/media/items/:id', async (request, reply) => {
        const user = request.user;
        const { id } = request.params;
        try {
            if (id.startsWith('external_')) {
                const parts = id.split('_');
                const extType = parts[1]; // 'movie' or 'show'
                const tmdbId = parts[2];
                const type = extType.toLowerCase() === 'show' ? 'Show' : 'Movie';
                try {
                    let tmdbData;
                    if (type === 'Show') {
                        tmdbData = await tmdb_1.tmdbService.fetchShowById(tmdbId);
                    }
                    else {
                        tmdbData = await tmdb_1.tmdbService.fetchMovieById(tmdbId);
                    }
                    if (!tmdbData) {
                        return reply.code(404).send({ error: 'External media not found' });
                    }
                    // Check if this item is in the local watchlist
                    const watchlistRow = database_1.default.prepare(`SELECT status FROM watchlist WHERE tmdb_id = ?`).get(tmdbId);
                    const isInWatchlist = !!watchlistRow;
                    const watchlistStatus = watchlistRow?.status || null;
                    // Check if we already have it in the library
                    const localItem = database_1.default.prepare(`SELECT id FROM media_items WHERE tmdb_id = ?`).get(tmdbId);
                    // Local metadata (if movie already exists in library)
                    const localMetaRows = localItem
                        ? database_1.default.prepare(`
                  SELECT metadata_key, metadata_value
                  FROM media_metadata
                  WHERE media_item_id = ?
                    AND metadata_key IN ('my_rating', 'watch_status', 'playback_progress')
                `).all(localItem.id)
                        : [];
                    const localMeta = {};
                    for (const row of localMetaRows) {
                        localMeta[row.metadata_key] = row.metadata_value;
                    }
                    // Synced external metadata (for movies not in local library)
                    const externalState = database_1.default.prepare(`
              SELECT my_rating, watch_status
              FROM external_media_state
              WHERE (tmdb_id = ? AND tmdb_id IS NOT NULL)
                 OR (imdb_id = ? AND imdb_id IS NOT NULL)
              ORDER BY updated_at DESC
              LIMIT 1
            `).get(tmdbId, tmdbData.external_ids?.imdb_id || tmdbData.imdb_id || null);
                    // Map credits
                    const castList = (tmdbData.credits?.cast || []).map((c) => ({
                        ...c,
                        profile_path: c.profile_path ? tmdb_1.tmdbService.getImageUrl(c.profile_path, 'w500') : null,
                    }));
                    const crewList = (tmdbData.credits?.crew || []).map((c) => ({
                        ...c,
                        profile_path: c.profile_path ? tmdb_1.tmdbService.getImageUrl(c.profile_path, 'w500') : null,
                    }));
                    const directorItem = crewList.find((c) => c.job === 'Director');
                    const genresList = (tmdbData.genres || []).map((g) => g.name);
                    const imdbId = tmdbData.external_ids?.imdb_id || tmdbData.imdb_id || null;
                    const simklClientId = tmdb_1.tmdbService.getSetting('SIMKL_CLIENT_ID');
                    const traktApiKey = tmdb_1.tmdbService.getSetting('TRAKT_API_KEY');
                    let simklRating = null;
                    let simklVotes = null;
                    let traktRating = null;
                    let traktVotes = null;
                    if (simklClientId && imdbId) {
                        try {
                            const simklLookupRes = await axios_1.default.get(`https://api.simkl.com/search/id`, {
                                params: { imdb: imdbId, client_id: simklClientId }
                            });
                            const simklLookupData = Array.isArray(simklLookupRes.data)
                                ? simklLookupRes.data[0]
                                : simklLookupRes.data;
                            const simklId = extractSimklId(simklLookupData);
                            if (simklId) {
                                const simklRatingsRes = await axios_1.default.get(`https://api.simkl.com/ratings`, {
                                    params: {
                                        simkl: simklId,
                                        fields: 'rank,droprate,simkl,ext,has_trailer,reactions,year',
                                        client_id: simklClientId,
                                    }
                                });
                                const parsedSimklRatings = extractSimklRatings(simklRatingsRes.data);
                                simklRating = parsedSimklRatings.simklRating;
                                simklVotes = parsedSimklRatings.simklVotes;
                            }
                        }
                        catch (simklErr) {
                            console.error('[External Media Details] Simkl ratings fetch failed:', simklErr);
                        }
                    }
                    if (traktApiKey && imdbId) {
                        try {
                            const mediaType = type === 'Show' ? 'show' : 'movie';
                            const parsedTraktRatings = await fetchTraktRatingsByImdb(imdbId, traktApiKey, mediaType);
                            traktRating = parsedTraktRatings.traktRating;
                            traktVotes = parsedTraktRatings.traktVotes;
                        }
                        catch (traktErr) {
                            console.error('[External Media Details] Trakt ratings fetch failed:', traktErr);
                        }
                    }
                    const mergedMyRating = localMeta.my_rating ?? externalState?.my_rating ?? '0';
                    const mergedWatchStatus = localMeta.watch_status ?? externalState?.watch_status ?? 'unwatched';
                    const mergedProgress = localMeta.playback_progress ?? '0';
                    const metadata = {
                        tagline: tmdbData.tagline || '',
                        keywords: (tmdbData.keywords?.keywords || tmdbData.keywords?.results || []).map((k) => k.name),
                        production_companies: (tmdbData.production_companies || []).map((c) => ({
                            id: c.id,
                            name: c.name,
                            logo_path: c.logo_path ? tmdb_1.tmdbService.getImageUrl(c.logo_path, 'w500') : null,
                            origin_country: c.origin_country || null
                        })),
                        production_countries: (tmdbData.production_countries || []),
                        director: directorItem?.name || '',
                        writer: crewList.find((c) => c.department === 'Writing')?.name || '',
                        cast: castList,
                        crew: crewList,
                        logo_path: tmdbData.logo_path ? tmdb_1.tmdbService.getImageUrl(tmdbData.logo_path, 'w500') : null,
                        trailer_url: tmdbData.trailer_url || '',
                        ratings: {
                            tmdb: tmdbData.vote_average ?? null,
                            tmdb_votes: tmdbData.vote_count ?? null,
                            simkl: simklRating,
                            simkl_votes: simklVotes,
                            trakt: traktRating,
                            trakt_votes: traktVotes,
                        },
                        imdb_rating: tmdbData.vote_average ? tmdbData.vote_average.toFixed(1) : 'N/A',
                        simkl_rating: simklRating ?? 'N/A',
                        simkl_votes: simklVotes,
                        trakt_rating: traktRating ?? 'N/A',
                        trakt_votes: traktVotes,
                        my_rating: mergedMyRating,
                        watch_status: mergedWatchStatus,
                        playback_progress: mergedProgress,
                        'watch/providers': tmdbData['watch/providers'] || null,
                    };
                    return reply.send({
                        id: id,
                        title: tmdbData.title || tmdbData.name || 'Unknown',
                        type: type,
                        plot: tmdbData.overview || '',
                        year: tmdbData.release_date
                            ? parseInt(tmdbData.release_date.substring(0, 4), 10)
                            : (tmdbData.first_air_date ? parseInt(tmdbData.first_air_date.substring(0, 4), 10) : null),
                        genre: genresList.join(', ') || type,
                        poster_path: tmdbData.poster_path ? tmdb_1.tmdbService.getImageUrl(tmdbData.poster_path, 'w500') : null,
                        fanart_path: tmdbData.backdrop_path ? tmdb_1.tmdbService.getImageUrl(tmdbData.backdrop_path, 'original') : null,
                        tmdb_id: tmdbId,
                        imdb_id: imdbId,
                        collection_name: tmdbData.belongs_to_collection?.name || null,
                        collection_id: tmdbData.belongs_to_collection?.id?.toString() || null,
                        director: directorItem?.name || null,
                        original_title: tmdbData.original_title || tmdbData.original_name || null,
                        file_path: null, // Signals not in library
                        added_at: new Date().toISOString(),
                        is_in_watchlist: isInWatchlist,
                        watchlist_status: watchlistStatus,
                        local_id: localItem?.id || null,
                        metadata: metadata,
                        versions: []
                    });
                }
                catch (error) {
                    request.log.error(error);
                    return reply.code(500).send({ error: 'Failed to fetch external media details', details: error.message });
                }
            }
            // Fetch base media item
            const movie = database_1.default.prepare(`SELECT * FROM media_items WHERE id = ?`).get(id);
            if (!movie) {
                return reply.code(404).send({ error: 'Media item not found' });
            }
            // Check user restrictions (if restricted, return 403)
            const restrictions = database_1.default.prepare(`
          SELECT ur.restriction_type, ur.restriction_value
          FROM user_restrictions ur
          WHERE ur.user_id = ?
        `).all(user.id);
            // Fetch metadata
            const metadataRows = database_1.default.prepare(`
          SELECT metadata_key, metadata_value 
          FROM media_metadata 
          WHERE media_item_id = ?
        `).all(movie.id);
            const metadata = {};
            metadataRows.forEach(row => {
                try {
                    // Try to parse JSON for cast/ratings
                    metadata[row.metadata_key] = JSON.parse(row.metadata_value);
                }
                catch (e) {
                    metadata[row.metadata_key] = row.metadata_value;
                }
            });
            const upsertMeta = (key, value) => {
                database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run((0, uuid_1.v4)(), movie.id, key, value);
            };
            const awardsPlaceholder = 'Inga prisuppgifter hittades.';
            const simklClientId = tmdb_1.tmdbService.getSetting('SIMKL_CLIENT_ID');
            const traktApiKey = tmdb_1.tmdbService.getSetting('TRAKT_API_KEY');
            const needsEnrichment = !metadata.tagline || !metadata.keywords || !metadata.production_companies || !metadata.production_countries || !metadata.awards || metadata.awards === awardsPlaceholder || !metadata.director || !metadata.logo_path || !metadata.imdb_rating || !metadata.trailer_url || (simklClientId && (!metadata.simkl_rating || !metadata.trakt_rating));
            console.log('[Media Details] Diagnostic check for:', movie.title, {
                needsEnrichment,
                hasImdbRating: Boolean(metadata.imdb_rating),
                hasSimklRating: Boolean(metadata.simkl_rating),
                hasTraktRating: Boolean(metadata.trakt_rating),
                simklClientId: simklClientId ? 'PRESENT' : 'MISSING',
                traktApiKey: traktApiKey ? 'PRESENT' : 'MISSING',
                imdbIdInDb: movie.imdb_id || 'MISSING'
            });
            if (needsEnrichment) {
                const tmdbData = movie.tmdb_id
                    ? await tmdb_1.tmdbService.fetchMovieById(movie.tmdb_id.toString())
                    : await tmdb_1.tmdbService.searchMovie(movie.title, movie.year ?? undefined);
                if (tmdbData) {
                    if (!movie.original_title && tmdbData.original_title) {
                        database_1.default.prepare(`UPDATE media_items SET original_title = ? WHERE id = ?`).run(tmdbData.original_title, movie.id);
                        movie.original_title = tmdbData.original_title;
                    }
                    if (!metadata.tagline && tmdbData.tagline) {
                        metadata.tagline = tmdbData.tagline;
                        upsertMeta('tagline', tmdbData.tagline);
                    }
                    if (!metadata.keywords && tmdbData.keywords?.keywords) {
                        const keywords = tmdbData.keywords.keywords.map((keyword) => keyword.name);
                        metadata.keywords = keywords;
                        upsertMeta('keywords', JSON.stringify(keywords));
                    }
                    if (!metadata.production_companies && tmdbData.production_companies) {
                        const companies = tmdbData.production_companies
                            .filter((company) => company && company.name)
                            .slice(0, 2)
                            .map((company) => ({
                            id: company.id,
                            name: company.name,
                            logo_path: company.logo_path ? tmdb_1.tmdbService.getImageUrl(company.logo_path, 'w500') : null,
                            origin_country: company.origin_country || null
                        }));
                        metadata.production_companies = companies;
                        upsertMeta('production_companies', JSON.stringify(companies));
                    }
                    if (!metadata.production_countries && tmdbData.production_countries) {
                        const countries = tmdbData.production_countries.map((country) => ({
                            iso_3166_1: country.iso_3166_1,
                            name: country.name
                        }));
                        metadata.production_countries = countries;
                        upsertMeta('production_countries', JSON.stringify(countries));
                    }
                    if (!metadata.director && tmdbData.credits && tmdbData.credits.crew) {
                        const dirObj = tmdbData.credits.crew.find((c) => c.job === 'Director');
                        if (dirObj) {
                            const directorData = { id: dirObj.id, name: dirObj.name };
                            metadata.director = directorData;
                            upsertMeta('director', JSON.stringify(directorData));
                        }
                    }
                    if (!metadata.logo_path && tmdbData.logo_path) {
                        const logoUrl = tmdb_1.tmdbService.getImageUrl(tmdbData.logo_path, 'w500');
                        if (logoUrl) {
                            metadata.logo_path = logoUrl;
                            upsertMeta('logo_path', logoUrl);
                        }
                    }
                    if (!metadata.trailer_url && tmdbData.trailer_url) {
                        metadata.trailer_url = tmdbData.trailer_url;
                        upsertMeta('trailer_url', tmdbData.trailer_url);
                    }
                    const imdbId = movie.imdb_id || tmdbData.external_ids?.imdb_id || null;
                    if (imdbId) {
                        const omdbKey = tmdb_1.tmdbService.getSetting('OMDB_API_KEY');
                        if (omdbKey && (!metadata.awards || metadata.awards === awardsPlaceholder || !metadata.imdb_rating)) {
                            try {
                                const omdbRes = await axios_1.default.get(`http://www.omdbapi.com/`, {
                                    params: { apikey: omdbKey, i: imdbId }
                                });
                                if (omdbRes.data) {
                                    if (omdbRes.data.Awards) {
                                        metadata.awards = omdbRes.data.Awards;
                                        upsertMeta('awards', omdbRes.data.Awards);
                                    }
                                    if (omdbRes.data.imdbRating && omdbRes.data.imdbRating !== 'N/A') {
                                        metadata.imdb_rating = omdbRes.data.imdbRating;
                                        upsertMeta('imdb_rating', omdbRes.data.imdbRating);
                                    }
                                    if (omdbRes.data.imdbVotes && omdbRes.data.imdbVotes !== 'N/A') {
                                        metadata.imdb_votes = omdbRes.data.imdbVotes;
                                        upsertMeta('imdb_votes', omdbRes.data.imdbVotes);
                                    }
                                    if (omdbRes.data.Metascore && omdbRes.data.Metascore !== 'N/A') {
                                        metadata.metascore = omdbRes.data.Metascore;
                                        upsertMeta('metascore', omdbRes.data.Metascore);
                                    }
                                    if (Array.isArray(omdbRes.data.Ratings)) {
                                        const rtEntry = omdbRes.data.Ratings.find((r) => r.Source === 'Rotten Tomatoes');
                                        if (rtEntry) {
                                            metadata.rt_rating = rtEntry.Value;
                                            upsertMeta('rt_rating', rtEntry.Value);
                                        }
                                    }
                                }
                            }
                            catch (omdbErr) {
                                console.error('[Media Details] OMDb enrichment failed:', omdbErr);
                            }
                        }
                        if (simklClientId && (!metadata.simkl_rating || !metadata.simkl_votes)) {
                            try {
                                const simklLookupRes = await axios_1.default.get(`https://api.simkl.com/search/id`, {
                                    params: { imdb: imdbId, client_id: simklClientId }
                                });
                                const simklLookupData = Array.isArray(simklLookupRes.data)
                                    ? simklLookupRes.data[0]
                                    : simklLookupRes.data;
                                const simklId = extractSimklId(simklLookupData);
                                if (simklId && (!metadata.simkl_rating || !metadata.simkl_votes)) {
                                    const simklRatingsRes = await axios_1.default.get(`https://api.simkl.com/ratings`, {
                                        params: {
                                            simkl: simklId,
                                            fields: 'rank,droprate,simkl,ext,has_trailer,reactions,year',
                                            client_id: simklClientId,
                                        }
                                    });
                                    const parsedSimklRatings = extractSimklRatings(simklRatingsRes.data);
                                    if (parsedSimklRatings.simklRating) {
                                        metadata.simkl_rating = parsedSimklRatings.simklRating;
                                        upsertMeta('simkl_rating', parsedSimklRatings.simklRating);
                                    }
                                    if (parsedSimklRatings.simklVotes) {
                                        metadata.simkl_votes = parsedSimklRatings.simklVotes;
                                        upsertMeta('simkl_votes', parsedSimklRatings.simklVotes);
                                    }
                                }
                            }
                            catch (simklErr) {
                                console.error('[Media Details] Simkl/Trakt enrichment failed:', simklErr);
                            }
                        }
                        if (traktApiKey && imdbId && (!metadata.trakt_rating || !metadata.trakt_votes)) {
                            try {
                                const mediaType = movie.type?.toString().toLowerCase() === 'show' || movie.type?.toString().toLowerCase() === 'tv'
                                    ? 'show'
                                    : 'movie';
                                const parsedTraktRatings = await fetchTraktRatingsByImdb(imdbId, traktApiKey, mediaType);
                                if (parsedTraktRatings.traktRating) {
                                    metadata.trakt_rating = parsedTraktRatings.traktRating;
                                    upsertMeta('trakt_rating', parsedTraktRatings.traktRating);
                                }
                                if (parsedTraktRatings.traktVotes) {
                                    metadata.trakt_votes = parsedTraktRatings.traktVotes;
                                    upsertMeta('trakt_votes', parsedTraktRatings.traktVotes);
                                }
                            }
                            catch (traktErr) {
                                console.error('[Media Details] Trakt API enrichment failed:', traktErr);
                            }
                        }
                    }
                    if (!metadata.awards || metadata.awards === awardsPlaceholder) {
                        const tmdbAwards = await tmdb_1.tmdbService.fetchAwardsSummary(tmdbData.id?.toString?.() || movie.tmdb_id?.toString?.() || '');
                        if (tmdbAwards) {
                            metadata.awards = tmdbAwards;
                            upsertMeta('awards', tmdbAwards);
                        }
                    }
                }
            }
            // Simple restriction check
            if (restrictions.length > 0) {
                const genre = movie.genre || metadata.genre;
                const rating = metadata.rating;
                for (const r of restrictions) {
                    if (r.restriction_type === 'GENRE' && genre === r.restriction_value) {
                        return reply.code(403).send({ error: 'Access denied due to genre restriction' });
                    }
                }
            }
            // Return combined data
            return {
                id: movie.id,
                title: movie.title,
                type: movie.type,
                plot: movie.plot,
                year: movie.year,
                genre: movie.genre || metadata.genre || 'Movie',
                poster_path: movie.poster_path,
                fanart_path: movie.fanart_path,
                tmdb_id: movie.tmdb_id,
                imdb_id: movie.imdb_id,
                collection_name: movie.collection_name,
                collection_id: movie.collection_id,
                director: movie.director,
                original_title: movie.original_title,
                file_path: movie.file_path,
                added_at: movie.added_at,
                metadata: metadata, // includes 'cast', 'ratings' etc
                versions: (() => {
                    try {
                        const sameItems = movie.tmdb_id
                            ? database_1.default.prepare(`SELECT id, file_path FROM media_items WHERE tmdb_id = ?`).all(movie.tmdb_id)
                            : database_1.default.prepare(`SELECT id, file_path FROM media_items WHERE title = ?`).all(movie.title);
                        return sameItems.map((item) => {
                            const resRow = database_1.default.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'resolution'`).get(item.id);
                            return {
                                id: item.id,
                                file_path: item.file_path,
                                resolution: resRow?.metadata_value || '1080p'
                            };
                        });
                    }
                    catch (e) {
                        return [{
                                id: movie.id,
                                file_path: movie.file_path,
                                resolution: metadata.resolution || '1080p'
                            }];
                    }
                })()
            };
        }
        catch (error) {
            request.log.error(error);
            return reply.code(500).send({ error: 'Failed to fetch media details', details: error.message });
        }
    });
    // GET /api/media/shows
    // Retrieves shows with SQL-level restriction filters applied
    fastify.get('/api/media/shows', async (request, reply) => {
        const user = request.user;
        try {
            const showsQuery = `
          SELECT mi.* FROM media_items mi
          WHERE mi.type = 'Show'
          AND mi.id NOT IN (
            SELECT mm.media_item_id 
            FROM media_metadata mm
            JOIN user_restrictions ur ON ur.user_id = ?
            WHERE 
              (ur.restriction_type = 'GENRE' AND mm.metadata_key = 'genre' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'RATING' AND mm.metadata_key = 'rating' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'KEYWORD' AND mm.metadata_key = 'keyword' AND mm.metadata_value LIKE '%' || ur.restriction_value || '%')
          )
        `;
            const rawShows = database_1.default.prepare(showsQuery).all(user.id);
            const showsWithEpisodes = rawShows.map(show => {
                // Get metadata
                const metadataRows = database_1.default.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(show.id);
                const metadata = {};
                metadataRows.forEach(row => {
                    metadata[row.metadata_key] = row.metadata_value;
                });
                // Get episodes list
                const episodes = database_1.default.prepare(`
            SELECT id, season_number, episode_number, title, file_path 
            FROM episodes 
            WHERE show_id = ?
            ORDER BY season_number ASC, episode_number ASC
          `).all(show.id);
                return {
                    ...show,
                    metadata,
                    episodes
                };
            });
            return reply.send(showsWithEpisodes);
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to retrieve shows' });
        }
    });
    // GET /api/people/:id
    // Retrieves bio and local-library matched movie credits for actors/directors
    fastify.get('/api/people/:id', async (request, reply) => {
        const apiKeyRow = database_1.default.prepare("SELECT value FROM system_settings WHERE key = 'TMDB_API_KEY'").get();
        if (!apiKeyRow || !apiKeyRow.value) {
            return reply.code(400).send({ error: 'TMDB API key not configured' });
        }
        const { id } = request.params;
        const prefLang = database_1.default.prepare("SELECT value FROM system_settings WHERE key = 'METADATA_LANGUAGE'").get()?.value || 'sv-SE';
        try {
            // 1. Fetch biographical info
            const personRes = await axios_1.default.get(`https://api.themoviedb.org/3/person/${id}`, {
                params: { api_key: apiKeyRow.value, language: prefLang }
            });
            const person = personRes.data;
            let biography = person.biography;
            if ((!biography || biography.trim() === '') && prefLang !== 'en-US') {
                try {
                    const enPersonRes = await axios_1.default.get(`https://api.themoviedb.org/3/person/${id}`, {
                        params: { api_key: apiKeyRow.value, language: 'en-US' }
                    });
                    if (enPersonRes.data && enPersonRes.data.biography) {
                        biography = enPersonRes.data.biography;
                    }
                }
                catch (e) {
                    console.error('Failed to fetch fallback en-US biography', e);
                }
            }
            // 2. Fetch movie credits
            const creditsRes = await axios_1.default.get(`https://api.themoviedb.org/3/person/${id}/movie_credits`, {
                params: { api_key: apiKeyRow.value, language: prefLang }
            });
            const castCredits = creditsRes.data.cast || [];
            const crewCredits = creditsRes.data.crew || [];
            // 3. Match against local library movies and watchlist!
            const localMovies = database_1.default.prepare(`
          SELECT mi.id, mi.title, mi.year, mi.tmdb_id, mi.poster_path,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'watch_status') as watch_status,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'playback_progress') as playback_progress,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'duration') as duration,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'runtime') as runtime
          FROM media_items mi
          WHERE mi.type = 'Movie'
        `).all();
            const watchlistRows = database_1.default.prepare(`SELECT tmdb_id FROM watchlist`).all();
            const watchlistTmdbIds = new Set(watchlistRows.map(r => r.tmdb_id.toString()));
            const matchLocal = (tmdbId, title) => {
                return localMovies.find(m => (m.tmdb_id && tmdbId && m.tmdb_id.toString() === tmdbId.toString()) || m.title.toLowerCase() === title.toLowerCase());
            };
            const mappedCast = castCredits.map((c) => {
                const localMatch = matchLocal(c.id, c.title);
                return {
                    id: c.id,
                    title: c.title,
                    character: c.character,
                    release_date: c.release_date,
                    year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
                    poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
                    popularity: c.popularity || 0.0,
                    vote_average: c.vote_average || 0.0,
                    vote_count: c.vote_count || 0,
                    overview: c.overview || '',
                    local_id: localMatch ? localMatch.id : null,
                    watch_status: localMatch ? localMatch.watch_status : null,
                    playback_progress: localMatch ? localMatch.playback_progress : null,
                    duration: localMatch ? localMatch.duration : null,
                    runtime: localMatch ? localMatch.runtime : null,
                    is_in_watchlist: watchlistTmdbIds.has(c.id.toString()),
                };
            }).sort((a, b) => (b.year || 0) - (a.year || 0));
            const mappedCrew = crewCredits.map((c) => {
                const localMatch = matchLocal(c.id, c.title);
                return {
                    id: c.id,
                    title: c.title,
                    job: c.job,
                    department: c.department || '',
                    release_date: c.release_date,
                    year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
                    poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
                    popularity: c.popularity || 0.0,
                    vote_average: c.vote_average || 0.0,
                    vote_count: c.vote_count || 0,
                    overview: c.overview || '',
                    local_id: localMatch ? localMatch.id : null,
                    watch_status: localMatch ? localMatch.watch_status : null,
                    playback_progress: localMatch ? localMatch.playback_progress : null,
                    duration: localMatch ? localMatch.duration : null,
                    runtime: localMatch ? localMatch.runtime : null,
                    is_in_watchlist: watchlistTmdbIds.has(c.id.toString()),
                };
            }).sort((a, b) => (b.year || 0) - (a.year || 0));
            return reply.send({
                id: person.id,
                name: person.name,
                biography: biography,
                birthday: person.birthday,
                deathday: person.deathday,
                place_of_birth: person.place_of_birth,
                profile_path: person.profile_path ? `https://image.tmdb.org/t/p/w500${person.profile_path}` : null,
                imdb_id: person.imdb_id,
                cast: mappedCast,
                crew: mappedCrew
            });
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to fetch person details', details: err.message });
        }
    });
    // GET /api/media/items/:id/search-tmdb
    fastify.get('/api/media/items/:id/search-tmdb', async (request, reply) => {
        const { query, year } = request.query;
        const parsedYear = year ? parseInt(year, 10) : undefined;
        try {
            const results = await tmdb_1.tmdbService.searchMovieCandidates(query, parsedYear);
            return results.map((m) => ({
                id: m.id,
                title: m.title,
                original_title: m.original_title,
                release_date: m.release_date,
                year: m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null,
                poster_path: m.poster_path ? tmdb_1.tmdbService.getImageUrl(m.poster_path, 'w500') : null
            }));
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to search TMDB', details: err.message });
        }
    });
    // GET /api/media/search-tmdb
    // Generic TMDB movie search used by Home quick search (no local item id required)
    fastify.get('/api/media/search-tmdb', async (request, reply) => {
        const { query, year } = request.query;
        const parsedYear = year ? parseInt(year, 10) : undefined;
        if (!query || query.trim().length < 1) {
            return reply.send([]);
        }
        try {
            const results = await tmdb_1.tmdbService.searchMovieCandidates(query.trim(), parsedYear);
            return results.map((m) => ({
                id: m.id,
                title: m.title,
                original_title: m.original_title,
                release_date: m.release_date,
                year: m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null,
                poster_path: m.poster_path ? tmdb_1.tmdbService.getImageUrl(m.poster_path, 'w500') : null
            }));
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to search TMDB', details: err.message });
        }
    });
    // POST /api/media/items/:id/match
    fastify.post('/api/media/items/:id/match', async (request, reply) => {
        const { id } = request.params;
        const { tmdbId } = request.body;
        try {
            // Clear all cached/old metadata keys except custom user states
            database_1.default.prepare(`
          DELETE FROM media_metadata 
          WHERE media_item_id = ? 
          AND metadata_key NOT IN ('my_rating', 'watch_status', 'playback_progress', 'duration')
        `).run(id);
            const movieItem = database_1.default.prepare(`SELECT file_path FROM media_items WHERE id = ?`).get(id);
            if (movieItem && movieItem.file_path) {
                const fileName = path_1.default.parse(movieItem.file_path).name.toLowerCase();
                let edition = null;
                if (/\buncut\b/i.test(fileName))
                    edition = 'Uncut';
                else if (/\bdirector\'?s\.?cut\b/i.test(fileName))
                    edition = "Director's Cut";
                else if (/\bextended\b/i.test(fileName))
                    edition = 'Extended Cut';
                else if (/\btheatrical\b/i.test(fileName))
                    edition = 'Theatrical Cut';
                else if (/\bultimate\b/i.test(fileName))
                    edition = 'Ultimate Edition';
                else if (/\bremastered\b/i.test(fileName))
                    edition = 'Remastered';
                else if (/\bcollector\'?s\.?edition\b/i.test(fileName))
                    edition = "Collector's Edition";
                else if (/\bspecial\.?edition\b/i.test(fileName))
                    edition = 'Special Edition';
                else if (/\b3d\b/i.test(fileName))
                    edition = '3D';
                else if (/\bimax\b/i.test(fileName))
                    edition = 'IMAX';
                if (edition) {
                    database_1.default.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run((0, uuid_1.v4)(), id, 'release_version', edition);
                }
            }
            const tmdbData = await tmdb_1.tmdbService.fetchMovieById(tmdbId);
            if (!tmdbData) {
                return reply.code(404).send({ error: 'TMDB movie details not found' });
            }
            // Get genres
            const genre = tmdbData.genres ? tmdbData.genres.map((g) => g.name).join(', ') : 'Movie';
            // Director (store in metadata with ID)
            if (tmdbData.credits && tmdbData.credits.crew) {
                const dirObj = tmdbData.credits.crew.find((c) => c.job === 'Director');
                if (dirObj) {
                    database_1.default.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run((0, uuid_1.v4)(), id, 'director', JSON.stringify({ id: dirObj.id, name: dirObj.name }));
                }
            }
            // Logo (store in metadata for ClearLOGO display)
            if (tmdbData.logo_path) {
                const logoUrl = tmdb_1.tmdbService.getImageUrl(tmdbData.logo_path, 'w500');
                if (logoUrl) {
                    database_1.default.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run((0, uuid_1.v4)(), id, 'logo_path', logoUrl);
                }
            }
            // Collection
            let collectionName = null;
            let collectionId = null;
            if (tmdbData.belongs_to_collection) {
                collectionName = tmdbData.belongs_to_collection.name;
                collectionId = tmdbData.belongs_to_collection.id.toString();
            }
            const poster_path = tmdb_1.tmdbService.getImageUrl(tmdbData.poster_path, 'w500');
            const fanart_path = tmdb_1.tmdbService.getImageUrl(tmdbData.backdrop_path, 'original');
            const year = tmdbData.release_date ? parseInt(tmdbData.release_date.substring(0, 4), 10) : null;
            // Update database media_item entry (director still stored as string for backward compatibility)
            let directorName = null;
            if (tmdbData.credits && tmdbData.credits.crew) {
                const dirObj = tmdbData.credits.crew.find((c) => c.job === 'Director');
                if (dirObj)
                    directorName = dirObj.name;
            }
            database_1.default.prepare(`
          UPDATE media_items 
          SET title = ?, plot = ?, year = ?, genre = ?, poster_path = ?, fanart_path = ?, tmdb_id = ?, imdb_id = ?, collection_name = ?, collection_id = ?, director = ?, original_title = ?
          WHERE id = ?
        `).run(tmdbData.title, tmdbData.overview || null, year, genre, poster_path, fanart_path, tmdbData.id.toString(), tmdbData.imdb_id || null, collectionName, collectionId, directorName, tmdbData.original_title || null, id);
            // Sub helper to upsert metadata
            const upsertMeta = (key, value) => {
                database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run((0, uuid_1.v4)(), id, key, value);
            };
            // Add additional metadata
            if (tmdbData.vote_average) {
                upsertMeta('ratings', JSON.stringify({ tmdb: tmdbData.vote_average, tmdb_votes: tmdbData.vote_count }));
            }
            if (tmdbData.credits && tmdbData.credits.cast) {
                const cast = tmdbData.credits.cast.slice(0, 15).map((c) => ({
                    id: c.id,
                    name: c.name,
                    character: c.character,
                    profile_path: tmdb_1.tmdbService.getImageUrl(c.profile_path, 'w500')
                }));
                upsertMeta('cast', JSON.stringify(cast));
            }
            if (tmdbData['watch/providers'] && tmdbData['watch/providers'].results) {
                upsertMeta('watch_providers', JSON.stringify(tmdbData['watch/providers'].results));
            }
            if (tmdbData.trailer_url) {
                upsertMeta('trailer_url', tmdbData.trailer_url);
            }
            else if (tmdbData.videos && tmdbData.videos.results) {
                const trailerObj = tmdbData.videos.results.find((v) => v.site === 'YouTube' && v.type === 'Trailer');
                if (trailerObj) {
                    upsertMeta('trailer_url', `https://www.youtube.com/watch?v=${trailerObj.key}`);
                }
            }
            // Fetch OMDb Awards AND Ratings
            const omdbKey = tmdb_1.tmdbService.getSetting('OMDB_API_KEY');
            if (omdbKey && tmdbData.imdb_id) {
                try {
                    const omdbRes = await axios_1.default.get(`http://www.omdbapi.com/`, {
                        params: { apikey: omdbKey, i: tmdbData.imdb_id }
                    });
                    if (omdbRes.data) {
                        if (omdbRes.data.Awards)
                            upsertMeta('awards', omdbRes.data.Awards);
                        if (omdbRes.data.imdbRating && omdbRes.data.imdbRating !== 'N/A') {
                            upsertMeta('imdb_rating', omdbRes.data.imdbRating);
                        }
                        if (omdbRes.data.imdbVotes && omdbRes.data.imdbVotes !== 'N/A') {
                            upsertMeta('imdb_votes', omdbRes.data.imdbVotes);
                        }
                        if (omdbRes.data.Metascore && omdbRes.data.Metascore !== 'N/A') {
                            upsertMeta('metascore', omdbRes.data.Metascore);
                        }
                        if (Array.isArray(omdbRes.data.Ratings)) {
                            const rtEntry = omdbRes.data.Ratings.find((r) => r.Source === 'Rotten Tomatoes');
                            if (rtEntry)
                                upsertMeta('rt_rating', rtEntry.Value);
                        }
                    }
                }
                catch (omdbErr) {
                    console.error('[ManualMatch] OMDb API fetch failed:', omdbErr);
                }
            }
            // Fetch Simkl & Trakt Ratings on Manual Match
            const simklClientId = tmdb_1.tmdbService.getSetting('SIMKL_CLIENT_ID');
            const traktApiKey = tmdb_1.tmdbService.getSetting('TRAKT_API_KEY');
            if (simklClientId && tmdbData.imdb_id) {
                try {
                    const simklRes = await axios_1.default.get(`https://api.simkl.com/search/id`, {
                        params: { imdb: tmdbData.imdb_id, client_id: simklClientId }
                    });
                    const simklData = Array.isArray(simklRes.data)
                        ? simklRes.data[0]
                        : simklRes.data;
                    if (simklData) {
                        const parsedRatings = extractSimklRatings(simklData);
                        if (parsedRatings.simklRating)
                            upsertMeta('simkl_rating', parsedRatings.simklRating);
                        if (parsedRatings.simklVotes)
                            upsertMeta('simkl_votes', parsedRatings.simklVotes);
                    }
                }
                catch (simklErr) {
                    console.error('[ManualMatch] Simkl/Trakt API fetch failed:', simklErr);
                }
            }
            if (traktApiKey && tmdbData.imdb_id) {
                try {
                    const mediaType = tmdbData.media_type === 'tv' ? 'show' : 'movie';
                    const traktRes = await axios_1.default.get(`https://api.trakt.tv/search/imdb/${tmdbData.imdb_id}`, {
                        params: {
                            type: mediaType,
                            extended: 'full',
                        },
                        headers: {
                            'trakt-api-key': traktApiKey,
                            'trakt-api-version': '2',
                            'User-Agent': 'Loom/1.0',
                        },
                    });
                    const traktData = Array.isArray(traktRes.data) ? traktRes.data[0] : traktRes.data;
                    if (traktData) {
                        const parsedRatings = extractTraktRatings(traktData);
                        if (parsedRatings.traktRating)
                            upsertMeta('trakt_rating', parsedRatings.traktRating);
                        if (parsedRatings.traktVotes)
                            upsertMeta('trakt_votes', parsedRatings.traktVotes);
                    }
                }
                catch (traktErr) {
                    console.error('[ManualMatch] Trakt API fetch failed:', traktErr);
                }
            }
            return reply.send({ success: true });
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to manual-match media item', details: err.message });
        }
    });
    // DELETE /api/media/items/:id
    fastify.delete('/api/media/items/:id', async (request, reply) => {
        const { id } = request.params;
        try {
            const item = database_1.default.prepare(`SELECT id, file_path FROM media_items WHERE id = ?`).get(id);
            if (!item) {
                return reply.code(404).send({ error: 'Media item not found' });
            }
            // Remove related metadata
            database_1.default.prepare(`DELETE FROM media_metadata WHERE media_item_id = ?`).run(id);
            // Remove item from database (Note: file on disk is NOT physically deleted!)
            database_1.default.prepare(`DELETE FROM media_items WHERE id = ?`).run(id);
            return reply.send({ success: true });
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to delete media item', details: err.message });
        }
    });
    // POST /api/media/items/:id/refresh
    fastify.post('/api/media/items/:id/refresh', async (request, reply) => {
        const { id } = request.params;
        try {
            const item = database_1.default.prepare(`SELECT id, file_path FROM media_items WHERE id = ?`).get(id);
            if (!item) {
                return reply.code(404).send({ error: 'Media item not found' });
            }
            // Lock key/metadata check bypass: we trigger ScannerService.processMovieFile
            // to re-fetch and overwrite metadata.
            const { mediaScanner } = await Promise.resolve().then(() => __importStar(require('../services/scanner')));
            const res = await mediaScanner.processMovieFile(item.file_path, false);
            return reply.send({ success: true, status: res });
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to refresh metadata', details: err.message });
        }
    });
    // POST /api/media/items/:id/unmatch
    fastify.post('/api/media/items/:id/unmatch', async (request, reply) => {
        const { id } = request.params;
        try {
            const item = database_1.default.prepare(`SELECT id FROM media_items WHERE id = ?`).get(id);
            if (!item) {
                return reply.code(404).send({ error: 'Media item not found' });
            }
            // Clear matches in DB
            database_1.default.prepare(`
          UPDATE media_items 
          SET tmdb_id = NULL, imdb_id = NULL, collection_name = NULL, collection_id = NULL, original_title = NULL, poster_path = NULL, fanart_path = NULL
          WHERE id = ?
        `).run(id);
            // Delete metadata keys except custom ratings/watch statuses if desired, or keep simple and delete all non-playback metadata keys
            database_1.default.prepare(`
          DELETE FROM media_metadata 
          WHERE media_item_id = ? 
          AND metadata_key NOT IN ('my_rating', 'watch_status', 'playback_progress', 'duration')
        `).run(id);
            return reply.send({ success: true });
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to unmatch media item', details: err.message });
        }
    });
    // POST /api/media/items/:id/analyze
    fastify.post('/api/media/items/:id/analyze', async (request, reply) => {
        const { id } = request.params;
        try {
            const item = database_1.default.prepare(`SELECT id, file_path FROM media_items WHERE id = ?`).get(id);
            if (!item) {
                return reply.code(404).send({ error: 'Media item not found' });
            }
            // Re-analyze using the public processMovieFile or re-probe
            const { mediaScanner } = await Promise.resolve().then(() => __importStar(require('../services/scanner')));
            const res = await mediaScanner.processMovieFile(item.file_path, true);
            return reply.send({ success: true, status: res });
        }
        catch (err) {
            console.error(err);
            return reply.code(500).send({ error: 'Failed to analyze media item', details: err.message });
        }
    });
    // GET /api/media/collections/:collectionId
    fastify.get('/api/media/collections/:collectionId', async (request, reply) => {
        const { collectionId } = request.params;
        try {
            const items = database_1.default.prepare(`
          SELECT id, title, year, poster_path, collection_name, collection_id, type, file_path
          FROM media_items
          WHERE collection_id = ?
          ORDER BY COALESCE(year, 9999) ASC, title ASC
        `).all(collectionId);
            const itemsWithMetadata = items.map(item => {
                const metadataRows = database_1.default.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(item.id);
                const metadata = {};
                metadataRows.forEach(row => {
                    metadata[row.metadata_key] = row.metadata_value;
                });
                return {
                    ...item,
                    metadata,
                };
            });
            return reply.send({
                collectionId,
                items: itemsWithMetadata,
            });
        }
        catch (error) {
            request.log.error(error);
            return reply.code(500).send({ error: 'Failed to fetch collection items', details: error.message });
        }
    });
    // GET /api/media/:id/similar — Get similar/recommended movies from library
    fastify.get('/api/media/:id/similar', async (request, reply) => {
        const { id } = request.params;
        try {
            const movie = database_1.default.prepare(`SELECT tmdb_id, title FROM media_items WHERE id = ?`).get(id);
            if (!movie || !movie.tmdb_id) {
                return reply.code(404).send({ error: 'Movie not found or no TMDB ID' });
            }
            // Fetch similar movies from TMDB
            const apiKey = database_1.default.prepare(`SELECT value FROM system_settings WHERE key = 'TMDB_API_KEY'`).get();
            if (!apiKey || !apiKey.value) {
                return reply.code(400).send({ error: 'TMDB API key not configured' });
            }
            let similarMovies = [];
            try {
                const response = await axios_1.default.get(`https://api.themoviedb.org/3/movie/${movie.tmdb_id}/similar`, {
                    params: {
                        api_key: apiKey.value,
                        language: 'sv-SE'
                    }
                });
                similarMovies = response.data.results || [];
            }
            catch (tmdbErr) {
                request.log.warn('Failed to fetch similar movies from TMDB:', tmdbErr.message);
                return reply.send({ id, items: [] });
            }
            // Filter to only items in library. Prefer TMDB ID, fall back to title match.
            const normalizedSimilar = similarMovies.map((m) => ({
                id: m.id,
                title: (m.title || '').toString().trim().toLowerCase(),
            }));
            if (normalizedSimilar.length === 0) {
                return reply.send({ id, items: [] });
            }
            const tmdbIds = normalizedSimilar.map((m) => m.id).filter(Boolean);
            const libraryRows = database_1.default.prepare(`
          SELECT id, title, year, poster_path, tmdb_id
          FROM media_items
          ORDER BY year DESC
        `).all();
            const libraryItems = libraryRows.filter((row) => {
                const tmdbIdMatch = row.tmdb_id && tmdbIds.includes(Number(row.tmdb_id));
                const titleMatch = normalizedSimilar.some((item) => item.title && item.title === (row.title || '').toString().trim().toLowerCase());
                return tmdbIdMatch || titleMatch;
            });
            return reply.send({
                id,
                items: libraryItems,
            });
        }
        catch (error) {
            request.log.error(error);
            return reply.code(500).send({ error: 'Failed to fetch similar items', details: error.message });
        }
    });
    // ─────────────────────────────────────────────────────────────
    // Playlist Routes
    // ─────────────────────────────────────────────────────────────
    // POST /api/playlists — Create a new playlist
    fastify.post('/api/playlists', async (request, reply) => {
        const { name } = request.body;
        if (!name || !name.trim()) {
            return reply.code(400).send({ error: 'Playlist name is required' });
        }
        try {
            const id = `pl_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
            database_1.default.prepare(`
          CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `).run();
            database_1.default.prepare(`INSERT INTO playlists (id, name) VALUES (?, ?)`).run(id, name.trim());
            return reply.status(201).send({ id, name: name.trim() });
        }
        catch (err) {
            if (err.message?.includes('UNIQUE')) {
                return reply.code(409).send({ error: 'Playlist already exists' });
            }
            return reply.code(500).send({ error: 'Failed to create playlist', details: err.message });
        }
    });
    // POST /api/playlists/:id/items — Add a media item to a playlist
    fastify.post('/api/playlists/:id/items', async (request, reply) => {
        const { id } = request.params;
        const { mediaItemId } = request.body;
        if (!mediaItemId) {
            return reply.code(400).send({ error: 'mediaItemId is required' });
        }
        try {
            database_1.default.prepare(`
          CREATE TABLE IF NOT EXISTS playlist_items (
            id TEXT PRIMARY KEY,
            playlist_id TEXT NOT NULL,
            media_item_id TEXT NOT NULL,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `).run();
            const itemId = `pli_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
            database_1.default.prepare(`INSERT INTO playlist_items (id, playlist_id, media_item_id) VALUES (?, ?, ?)`)
                .run(itemId, id, mediaItemId);
            return reply.status(201).send({ id: itemId, playlist_id: id, media_item_id: mediaItemId });
        }
        catch (err) {
            return reply.code(500).send({ error: 'Failed to add item to playlist', details: err.message });
        }
    });
    // ─────────────────────────────────────────────────────────────
    // Watchlist & Download Request Routes
    // ─────────────────────────────────────────────────────────────
    // GET /api/watchlist — Retrieve all watchlist items
    fastify.get('/api/watchlist', async (request, reply) => {
        try {
            const items = database_1.default.prepare(`SELECT * FROM watchlist ORDER BY added_at DESC`).all();
            return reply.send(items);
        }
        catch (err) {
            return reply.code(500).send({ error: 'Failed to fetch watchlist', details: err.message });
        }
    });
    // POST /api/watchlist — Add an item to the watchlist
    fastify.post('/api/watchlist', async (request, reply) => {
        const { tmdbId, title, type, year, posterPath } = request.body;
        if (!tmdbId || !title || !type) {
            return reply.code(400).send({ error: 'tmdbId, title, and type are required' });
        }
        try {
            const id = `wl_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
            database_1.default.prepare(`
          INSERT INTO watchlist (id, tmdb_id, title, type, year, poster_path, status)
          VALUES (?, ?, ?, ?, ?, ?, 'pending')
          ON CONFLICT(tmdb_id) DO UPDATE SET status='pending'
        `).run(id, tmdbId.toString(), title, type, year ?? null, posterPath ?? null);
            return reply.status(201).send({ id, tmdb_id: tmdbId, title, type, year, poster_path: posterPath, status: 'pending' });
        }
        catch (err) {
            return reply.code(500).send({ error: 'Failed to add item to watchlist', details: err.message });
        }
    });
    // DELETE /api/watchlist/:tmdbId — Remove an item from the watchlist
    fastify.delete('/api/watchlist/:tmdbId', async (request, reply) => {
        const { tmdbId } = request.params;
        try {
            database_1.default.prepare(`DELETE FROM watchlist WHERE tmdb_id = ?`).run(tmdbId.toString());
            return reply.send({ success: true, message: 'Removed from watchlist' });
        }
        catch (err) {
            return reply.code(500).send({ error: 'Failed to remove from watchlist', details: err.message });
        }
    });
}
