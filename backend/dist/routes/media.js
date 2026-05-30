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
          SELECT mi.* FROM media_items mi
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
    // GET /api/media/items/:id
    // Retrieves full details for a specific media item (Plex-like Media Details page)
    fastify.get('/api/media/items/:id', async (request, reply) => {
        const user = request.user;
        const { id } = request.params;
        try {
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
                versions: [{
                        id: movie.id,
                        file_path: movie.file_path,
                        resolution: metadata.resolution || '1080p'
                    }]
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
            // 2. Fetch movie credits
            const creditsRes = await axios_1.default.get(`https://api.themoviedb.org/3/person/${id}/movie_credits`, {
                params: { api_key: apiKeyRow.value, language: prefLang }
            });
            const castCredits = creditsRes.data.cast || [];
            const crewCredits = creditsRes.data.crew || [];
            // Find all directed movies
            const directedMovies = crewCredits.filter((c) => c.job === 'Director');
            // 3. Match against local library movies!
            const localMovies = database_1.default.prepare(`SELECT id, title, year, tmdb_id, poster_path FROM media_items WHERE type = 'Movie'`).all();
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
                    local_id: localMatch ? localMatch.id : null
                };
            }).sort((a, b) => (b.year || 0) - (a.year || 0));
            const mappedCrew = directedMovies.map((c) => {
                const localMatch = matchLocal(c.id, c.title);
                return {
                    id: c.id,
                    title: c.title,
                    job: c.job,
                    release_date: c.release_date,
                    year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
                    poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
                    local_id: localMatch ? localMatch.id : null
                };
            }).sort((a, b) => (b.year || 0) - (a.year || 0));
            return reply.send({
                id: person.id,
                name: person.name,
                biography: person.biography,
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
    // POST /api/media/items/:id/match
    fastify.post('/api/media/items/:id/match', async (request, reply) => {
        const { id } = request.params;
        const { tmdbId } = request.body;
        try {
            // Clear all cached/old metadata keys except custom user states
            database_1.default.prepare(`
          DELETE FROM media_metadata 
          WHERE media_item_id = ? 
          AND metadata_key NOT IN ('my_rating', 'watch_status', 'playback_progress')
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
          AND metadata_key NOT IN ('my_rating', 'watch_status', 'playback_progress')
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
          SELECT id, title, year, poster_path, collection_name, collection_id
          FROM media_items
          WHERE collection_id = ?
          ORDER BY COALESCE(year, 9999) ASC, title ASC
        `).all(collectionId);
            return reply.send({
                collectionId,
                items,
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
}
