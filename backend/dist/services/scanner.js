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
exports.mediaScanner = exports.ScannerService = void 0;
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const childProcess = __importStar(require("child_process"));
const uuid_1 = require("uuid");
const database_1 = __importDefault(require("../config/database"));
const tmdb_1 = require("./tmdb");
const marker_service_1 = require("./marker_service");
const scan_events_1 = require("./scan_events");
const axios_1 = __importDefault(require("axios"));
function triggerChapterScan(filePath, mediaItemId, episodeId) {
    setImmediate(async () => {
        try {
            const count = await (0, marker_service_1.scanChaptersForItem)(filePath, mediaItemId, episodeId);
            if (count > 0)
                console.log(`[Scanner] Chapters: ${count} found in ${path.basename(filePath)}`);
        }
        catch (_) { }
    });
}
const ffprobe = require('@ffprobe-installer/ffprobe');
class ScannerService {
    /**
     * Scan a specific library path for media files and their NFOs
     */
    async scanLibrary(libraryPath, type, preferLocalNfo) {
        if (!fs.existsSync(libraryPath)) {
            console.error(`[Scanner] Path does not exist: ${libraryPath}`);
            (0, scan_events_1.emitScanEvent)('scan_error', `Sökväg finns ej: ${libraryPath}`, type);
            return { added: 0, updated: 0 };
        }
        (0, scan_events_1.emitScanEvent)('scan_start', `Startar skanning av ${path.basename(libraryPath)} (${type})`, type);
        // Load user-configured skip words and min file size from settings
        const skipWordsRaw = database_1.default.prepare("SELECT value FROM system_settings WHERE key='SCAN_SKIP_WORDS'").get()?.value || '';
        const minSizeMb = parseFloat(database_1.default.prepare("SELECT value FROM system_settings WHERE key='SCAN_MIN_SIZE_MB'").get()?.value || '0');
        const minSizeBytes = minSizeMb > 0 ? minSizeMb * 1024 * 1024 : 0;
        const extraSkipWords = skipWordsRaw
            .split(',')
            .map((w) => w.trim().toLowerCase())
            .filter((w) => w.length > 0);
        let itemsAdded = 0;
        let itemsUpdated = 0;
        const files = this.getAllFiles(libraryPath);
        // Common video extensions
        const videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'];
        for (const file of files) {
            const ext = path.extname(file).toLowerCase();
            if (videoExts.includes(ext)) {
                // Check size filter
                if (minSizeBytes > 0) {
                    try {
                        const stat = fs.statSync(file);
                        if (stat.size < minSizeBytes) {
                            (0, scan_events_1.emitScanEvent)('item_skipped', `Hoppas över (för liten ${(stat.size / 1024 / 1024).toFixed(1)} MB): ${path.basename(file)}`, type);
                            continue;
                        }
                    }
                    catch (_) { }
                }
                if (this.isSupplementalVideo(file, extraSkipWords)) {
                    (0, scan_events_1.emitScanEvent)('item_skipped', `Hoppas över (tilläggsinnehåll): ${path.basename(file)}`, type);
                    continue;
                }
                (0, scan_events_1.emitScanEvent)('file_found', `Hittade: ${path.basename(file)}`, type);
                if (type === 'Movie') {
                    const result = await this.processMovieFile(file, preferLocalNfo);
                    if (result === 'added')
                        itemsAdded++;
                    else if (result === 'updated')
                        itemsUpdated++;
                }
                else if (type === 'Show') {
                    const result = await this.processEpisodeFile(file, libraryPath, preferLocalNfo);
                    if (result === 'added')
                        itemsAdded++;
                    else if (result === 'updated')
                        itemsUpdated++;
                }
            }
        }
        (0, scan_events_1.emitScanEvent)('scan_complete', `Klar! Tillagda: ${itemsAdded}, Uppdaterade: ${itemsUpdated}`, type);
        return { added: itemsAdded, updated: itemsUpdated };
    }
    /**
     * Process a single movie video file
     * Returns 'added', 'updated', or 'skipped'
     */
    async processMovieFile(filePath, preferLocalNfo = true) {
        const dir = path.dirname(filePath);
        const fileNameWithoutExt = path.parse(filePath).name;
        const nfoPath = path.join(dir, `${fileNameWithoutExt}.nfo`);
        const fallbackNfoPath = path.join(dir, 'movie.nfo');
        let metadata = {
            title: this.parseTitleFromFilename(fileNameWithoutExt),
            plot: null,
            year: this.parseYearFromFilename(fileNameWithoutExt),
            genre: null,
            poster_path: null,
            fanart_path: null,
        };
        let hasLocalNfo = false;
        // 1. Try Local Parsing (if preferred)
        if (preferLocalNfo) {
            if (fs.existsSync(nfoPath)) {
                metadata = { ...metadata, ...this.parseNfo(nfoPath) };
                hasLocalNfo = true;
            }
            else if (fs.existsSync(fallbackNfoPath)) {
                metadata = { ...metadata, ...this.parseNfo(fallbackNfoPath) };
                hasLocalNfo = true;
            }
            // Look for artwork
            const possiblePosters = ['poster.jpg', 'folder.jpg', `${fileNameWithoutExt}-poster.jpg`];
            for (const p of possiblePosters) {
                const pPath = path.join(dir, p);
                if (fs.existsSync(pPath)) {
                    metadata.poster_path = pPath;
                    break;
                }
            }
            const possibleFanart = ['fanart.jpg', 'background.jpg', `${fileNameWithoutExt}-fanart.jpg`];
            for (const p of possibleFanart) {
                const pPath = path.join(dir, p);
                if (fs.existsSync(pPath)) {
                    metadata.fanart_path = pPath;
                    break;
                }
            }
        }
        let tmdbRatings = null;
        let tmdbCast = null;
        let tmdbProviders = null;
        let tmdbTrailer = null;
        let omdbAwards = null;
        let tmdbAwards = null;
        let omdbImdbRating = null;
        let omdbMetascore = null;
        let omdbRtRating = null;
        let simklRating = null;
        let simklVotes = null;
        let traktRating = null;
        let traktVotes = null;
        let tmdbTagline = null;
        let omdbImdbVotes = null;
        let tmdbKeywords = null;
        let tmdbProductionCompanies = null;
        let tmdbProductionCountries = null;
        // Run ffprobe to detect real audio/subtitle tracks
        const probeResult = await this.probeMediaFile(filePath);
        // 2. TMDB API Fetch (Always query online source to enrich metadata with cast, watch providers, original title, awards, etc.)
        const needsOnlineData = true;
        if (needsOnlineData) {
            const tmdbData = await tmdb_1.tmdbService.searchMovie(metadata.title, metadata.year);
            if (tmdbData) {
                // TMDB overrides/complements
                if (!metadata.plot && tmdbData.overview)
                    metadata.plot = tmdbData.overview;
                if (tmdbData.release_date) {
                    if (!metadata.year)
                        metadata.year = parseInt(tmdbData.release_date.substring(0, 4), 10);
                    metadata.release_date = tmdbData.release_date;
                }
                if (tmdbData.tagline)
                    tmdbTagline = tmdbData.tagline;
                // Save genres as comma-separated values
                if (tmdbData.genres) {
                    metadata.genre = tmdbData.genres.map((g) => g.name).join(', ');
                }
                if (tmdbData.keywords?.keywords) {
                    tmdbKeywords = tmdbData.keywords.keywords.map((k) => k.name);
                }
                if (tmdbData.production_companies) {
                    const mainCompanies = tmdbData.production_companies
                        .filter((company) => company && company.name)
                        .slice(0, 2);
                    tmdbProductionCompanies = mainCompanies.map((company) => ({
                        id: company.id,
                        name: company.name,
                        logo_path: company.logo_path ? tmdb_1.tmdbService.getImageUrl(company.logo_path, 'w500') : null,
                        origin_country: company.origin_country || null
                    }));
                }
                if (tmdbData.production_countries) {
                    tmdbProductionCountries = tmdbData.production_countries.map((country) => ({
                        iso_3166_1: country.iso_3166_1,
                        name: country.name
                    }));
                }
                // Save TMDB / IMDb IDs
                if (tmdbData.id)
                    metadata.tmdb_id = tmdbData.id.toString();
                if (tmdbData.imdb_id)
                    metadata.imdb_id = tmdbData.imdb_id;
                const imdbId = tmdbData.imdb_id || tmdbData.external_ids?.imdb_id || null;
                // Save original_title
                if (tmdbData.original_title)
                    metadata.original_title = tmdbData.original_title;
                // Save director (with ID for clickability)
                let tmdbDirector = null;
                if (tmdbData.credits && tmdbData.credits.crew) {
                    const dirObj = tmdbData.credits.crew.find((c) => c.job === 'Director');
                    if (dirObj) {
                        tmdbDirector = { id: dirObj.id, name: dirObj.name };
                        metadata.director = tmdbDirector;
                    }
                }
                // Save logo_path for ClearLOGO display
                if (tmdbData.logo_path) {
                    metadata.logo_path = tmdb_1.tmdbService.getImageUrl(tmdbData.logo_path, 'w500');
                }
                // Save collection details
                if (tmdbData.belongs_to_collection) {
                    metadata.collection_name = tmdbData.belongs_to_collection.name;
                    metadata.collection_id = tmdbData.belongs_to_collection.id.toString();
                }
                // Only use TMDB images if we didn't find local ones
                if (!metadata.poster_path && tmdbData.poster_path) {
                    metadata.poster_path = tmdb_1.tmdbService.getImageUrl(tmdbData.poster_path, 'w500');
                }
                if (!metadata.fanart_path && tmdbData.backdrop_path) {
                    metadata.fanart_path = tmdb_1.tmdbService.getImageUrl(tmdbData.backdrop_path, 'original');
                }
                if (tmdbData.vote_average) {
                    tmdbRatings = { tmdb: tmdbData.vote_average, tmdb_votes: tmdbData.vote_count };
                }
                if (tmdbData.credits && tmdbData.credits.cast) {
                    tmdbCast = tmdbData.credits.cast.slice(0, 15).map((c) => ({
                        id: c.id,
                        name: c.name,
                        character: c.character,
                        profile_path: tmdb_1.tmdbService.getImageUrl(c.profile_path, 'w500')
                    }));
                }
                // Extract watch providers
                if (tmdbData['watch/providers'] && tmdbData['watch/providers'].results) {
                    tmdbProviders = tmdbData['watch/providers'].results;
                }
                // Extract YouTube trailer link
                if (tmdbData.trailer_url) {
                    tmdbTrailer = tmdbData.trailer_url;
                }
                else if (tmdbData.videos && tmdbData.videos.results) {
                    const trailerObj = tmdbData.videos.results.find((v) => v.site === 'YouTube' && v.type === 'Trailer');
                    if (trailerObj) {
                        tmdbTrailer = `https://www.youtube.com/watch?v=${trailerObj.key}`;
                    }
                }
                // Query OMDb API for awards AND ratings
                const omdbKey = tmdb_1.tmdbService.getSetting('OMDB_API_KEY');
                if (omdbKey && imdbId) {
                    try {
                        const omdbRes = await axios_1.default.get(`http://www.omdbapi.com/`, {
                            params: { apikey: omdbKey, i: imdbId }
                        });
                        if (omdbRes.data) {
                            if (omdbRes.data.Awards)
                                omdbAwards = omdbRes.data.Awards;
                            if (omdbRes.data.imdbRating && omdbRes.data.imdbRating !== 'N/A') {
                                omdbImdbRating = omdbRes.data.imdbRating;
                            }
                            if (omdbRes.data.imdbVotes && omdbRes.data.imdbVotes !== 'N/A') {
                                omdbImdbVotes = omdbRes.data.imdbVotes;
                            }
                            if (omdbRes.data.Metascore && omdbRes.data.Metascore !== 'N/A') {
                                omdbMetascore = omdbRes.data.Metascore;
                            }
                            // Rotten Tomatoes is in the Ratings array
                            if (Array.isArray(omdbRes.data.Ratings)) {
                                const rtEntry = omdbRes.data.Ratings.find((r) => r.Source === 'Rotten Tomatoes');
                                if (rtEntry)
                                    omdbRtRating = rtEntry.Value; // e.g. "87%"
                            }
                        }
                    }
                    catch (omdbErr) {
                        console.error(`[Scanner] OMDb API request failed for ${imdbId}:`, omdbErr);
                    }
                }
                // Query Simkl API for awards and ratings, and Trakt for its own ratings
                const simklClientId = tmdb_1.tmdbService.getSetting('SIMKL_CLIENT_ID');
                const traktApiKey = tmdb_1.tmdbService.getSetting('TRAKT_API_KEY');
                if (simklClientId && imdbId) {
                    try {
                        const simklLookupRes = await axios_1.default.get(`https://api.simkl.com/search/id`, {
                            params: { imdb: imdbId, client_id: simklClientId }
                        });
                        const simklLookupData = Array.isArray(simklLookupRes.data)
                            ? simklLookupRes.data[0]
                            : simklLookupRes.data;
                        const simklId = this.extractSimklId(simklLookupData);
                        if (simklId) {
                            const simklRatingsRes = await axios_1.default.get(`https://api.simkl.com/ratings`, {
                                params: {
                                    simkl: simklId,
                                    fields: 'rank,droprate,simkl,ext,has_trailer,reactions,year',
                                    client_id: simklClientId,
                                }
                            });
                            const parsedSimklRatings = this.extractSimklRatings(simklRatingsRes.data);
                            simklRating = parsedSimklRatings.simklRating;
                            simklVotes = parsedSimklRatings.simklVotes;
                        }
                    }
                    catch (simklErr) {
                        console.error(`[Scanner] Simkl/Trakt API request failed for ${imdbId}:`, simklErr);
                    }
                }
                if (traktApiKey && imdbId) {
                    try {
                        const traktRes = await axios_1.default.get(`https://api.trakt.tv/search/imdb/${imdbId}`, {
                            params: {
                                type: 'movie',
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
                            const parsedTraktRatings = this.extractTraktRatings(traktData);
                            traktRating = parsedTraktRatings.traktRating;
                            traktVotes = parsedTraktRatings.traktVotes;
                        }
                    }
                    catch (traktErr) {
                        console.error(`[Scanner] Trakt API request failed for ${imdbId}:`, traktErr);
                    }
                }
                if (!omdbAwards && tmdbData.id) {
                    tmdbAwards = await tmdb_1.tmdbService.fetchAwardsSummary(tmdbData.id.toString());
                }
            }
        }
        // Helper to upsert metadata
        const upsertMetadata = (itemId, key, value) => {
            // Check if locked first
            const lock = database_1.default.prepare('SELECT is_locked FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?').get(itemId, key);
            if (lock && lock.is_locked === 1)
                return;
            database_1.default.prepare(`
        INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
        VALUES (?, ?, ?, ?)
        ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
      `).run((0, uuid_1.v4)(), itemId, key, value);
        };
        // 3. Insert or Update DB
        try {
            const existing = database_1.default.prepare('SELECT id FROM media_items WHERE file_path = ?').all(filePath);
            const directorName = metadata.director && typeof metadata.director === 'object'
                ? metadata.director.name
                : metadata.director || null;
            if (existing && existing.length > 0) {
                const mediaId = existing[0].id;
                // Fetch locks from media_metadata table
                const locks = database_1.default.prepare('SELECT metadata_key FROM media_metadata WHERE media_item_id = ? AND is_locked = 1').all(mediaId);
                const lockedKeys = locks.map(l => l.metadata_key);
                // Build UPDATE query dynamically to respect locks
                let updateFields = [];
                let params = [];
                if (!lockedKeys.includes('title')) {
                    updateFields.push('title = ?');
                    params.push(metadata.title);
                }
                if (!lockedKeys.includes('plot')) {
                    updateFields.push('plot = ?');
                    params.push(metadata.plot);
                }
                if (!lockedKeys.includes('year')) {
                    updateFields.push('year = ?');
                    params.push(metadata.year);
                }
                if (!lockedKeys.includes('genre')) {
                    updateFields.push('genre = ?');
                    params.push(metadata.genre);
                }
                if (!lockedKeys.includes('poster_path')) {
                    updateFields.push('poster_path = ?');
                    params.push(metadata.poster_path);
                }
                if (!lockedKeys.includes('fanart_path')) {
                    updateFields.push('fanart_path = ?');
                    params.push(metadata.fanart_path);
                }
                if (!lockedKeys.includes('tmdb_id')) {
                    updateFields.push('tmdb_id = ?');
                    params.push(metadata.tmdb_id || null);
                }
                if (!lockedKeys.includes('imdb_id')) {
                    updateFields.push('imdb_id = ?');
                    params.push(metadata.imdb_id || null);
                }
                if (!lockedKeys.includes('collection_name')) {
                    updateFields.push('collection_name = ?');
                    params.push(metadata.collection_name || null);
                }
                if (!lockedKeys.includes('collection_id')) {
                    updateFields.push('collection_id = ?');
                    params.push(metadata.collection_id || null);
                }
                if (!lockedKeys.includes('director')) {
                    updateFields.push('director = ?');
                    params.push(directorName);
                }
                if (!lockedKeys.includes('original_title')) {
                    updateFields.push('original_title = ?');
                    params.push(metadata.original_title || null);
                }
                if (metadata.release_date) {
                    updateFields.push('release_date = ?');
                    params.push(metadata.release_date);
                }
                if (updateFields.length > 0) {
                    params.push(filePath);
                    database_1.default.prepare(`
            UPDATE media_items 
            SET ${updateFields.join(', ')}
            WHERE file_path = ?
          `).run(...params);
                    if (tmdbRatings)
                        upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
                    if (tmdbCast)
                        upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
                    if (tmdbProviders)
                        upsertMetadata(mediaId, 'watch_providers', JSON.stringify(tmdbProviders));
                    if (tmdbTrailer)
                        upsertMetadata(mediaId, 'trailer_url', tmdbTrailer);
                    if (omdbAwards || tmdbAwards)
                        upsertMetadata(mediaId, 'awards', omdbAwards || tmdbAwards);
                    if (omdbImdbRating)
                        upsertMetadata(mediaId, 'imdb_rating', omdbImdbRating);
                    if (omdbImdbVotes)
                        upsertMetadata(mediaId, 'imdb_votes', omdbImdbVotes);
                    if (omdbMetascore)
                        upsertMetadata(mediaId, 'metascore', omdbMetascore);
                    if (omdbRtRating)
                        upsertMetadata(mediaId, 'rt_rating', omdbRtRating);
                    if (simklRating)
                        upsertMetadata(mediaId, 'simkl_rating', simklRating);
                    if (simklVotes)
                        upsertMetadata(mediaId, 'simkl_votes', simklVotes);
                    if (traktRating)
                        upsertMetadata(mediaId, 'trakt_rating', traktRating);
                    if (traktVotes)
                        upsertMetadata(mediaId, 'trakt_votes', traktVotes);
                    if (tmdbTagline)
                        upsertMetadata(mediaId, 'tagline', tmdbTagline);
                    if (tmdbKeywords)
                        upsertMetadata(mediaId, 'keywords', JSON.stringify(tmdbKeywords));
                    if (tmdbProductionCompanies)
                        upsertMetadata(mediaId, 'production_companies', JSON.stringify(tmdbProductionCompanies));
                    if (tmdbProductionCountries)
                        upsertMetadata(mediaId, 'production_countries', JSON.stringify(tmdbProductionCountries));
                    if (metadata.director && typeof metadata.director === 'object') {
                        upsertMetadata(mediaId, 'director', JSON.stringify(metadata.director));
                    }
                    if (probeResult.audioTracks.length > 0)
                        upsertMetadata(mediaId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
                    if (probeResult.subtitleTracks.length > 0)
                        upsertMetadata(mediaId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
                    // Always write resolution – bypass the user-lock since it is a file property.
                    if (probeResult.resolution) {
                        database_1.default.prepare('INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) VALUES (?,?,\'resolution\',?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value').run((0, uuid_1.v4)(), mediaId, probeResult.resolution);
                    }
                    const edition = this.parseEditionFromFilename(fileNameWithoutExt);
                    if (edition) {
                        upsertMetadata(mediaId, 'release_version', edition);
                    }
                    triggerChapterScan(filePath, mediaId, null);
                    (0, scan_events_1.emitScanEvent)('item_updated', `Uppdaterad: ${metadata.title || path.basename(filePath)}`, 'Movie');
                    return 'updated';
                }
                if (tmdbRatings)
                    upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
                if (tmdbCast)
                    upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
                if (tmdbProviders)
                    upsertMetadata(mediaId, 'watch_providers', JSON.stringify(tmdbProviders));
                if (tmdbTrailer)
                    upsertMetadata(mediaId, 'trailer_url', tmdbTrailer);
                if (omdbAwards)
                    upsertMetadata(mediaId, 'awards', omdbAwards);
                if (omdbImdbRating)
                    upsertMetadata(mediaId, 'imdb_rating', omdbImdbRating);
                if (omdbImdbVotes)
                    upsertMetadata(mediaId, 'imdb_votes', omdbImdbVotes);
                if (omdbMetascore)
                    upsertMetadata(mediaId, 'metascore', omdbMetascore);
                if (omdbRtRating)
                    upsertMetadata(mediaId, 'rt_rating', omdbRtRating);
                if (simklRating)
                    upsertMetadata(mediaId, 'simkl_rating', simklRating);
                if (metadata.director && typeof metadata.director === 'object') {
                    upsertMetadata(mediaId, 'director', JSON.stringify(metadata.director));
                }
                if (probeResult.audioTracks.length > 0)
                    upsertMetadata(mediaId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
                if (probeResult.subtitleTracks.length > 0)
                    upsertMetadata(mediaId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
                if (probeResult.resolution) {
                    database_1.default.prepare('INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) VALUES (?,?,\'resolution\',?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value').run((0, uuid_1.v4)(), mediaId, probeResult.resolution);
                }
                const edition = this.parseEditionFromFilename(fileNameWithoutExt);
                if (edition) {
                    upsertMetadata(mediaId, 'release_version', edition);
                }
                triggerChapterScan(filePath, mediaId, null);
                (0, scan_events_1.emitScanEvent)('item_updated', `Uppdaterad (metadata): ${metadata.title || path.basename(filePath)}`, 'Movie');
                return 'skipped';
            }
            else {
                // Insert new
                const id = (0, uuid_1.v4)();
                database_1.default.prepare(`
          INSERT INTO media_items (id, title, type, plot, year, genre, poster_path, fanart_path, tmdb_id, imdb_id, collection_name, collection_id, director, original_title, file_path, release_date)
          VALUES (?, ?, 'Movie', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(id, metadata.title, metadata.plot, metadata.year, metadata.genre, metadata.poster_path, metadata.fanart_path, metadata.tmdb_id || null, metadata.imdb_id || null, metadata.collection_name || null, metadata.collection_id || null, directorName, metadata.original_title || null, filePath, metadata.release_date || null);
                if (tmdbRatings)
                    upsertMetadata(id, 'ratings', JSON.stringify(tmdbRatings));
                if (tmdbCast)
                    upsertMetadata(id, 'cast', JSON.stringify(tmdbCast));
                if (tmdbProviders)
                    upsertMetadata(id, 'watch_providers', JSON.stringify(tmdbProviders));
                if (tmdbTrailer)
                    upsertMetadata(id, 'trailer_url', tmdbTrailer);
                if (omdbAwards || tmdbAwards)
                    upsertMetadata(id, 'awards', omdbAwards || tmdbAwards);
                if (omdbImdbRating)
                    upsertMetadata(id, 'imdb_rating', omdbImdbRating);
                if (omdbImdbVotes)
                    upsertMetadata(id, 'imdb_votes', omdbImdbVotes);
                if (omdbMetascore)
                    upsertMetadata(id, 'metascore', omdbMetascore);
                if (omdbRtRating)
                    upsertMetadata(id, 'rt_rating', omdbRtRating);
                if (simklRating)
                    upsertMetadata(id, 'simkl_rating', simklRating);
                if (simklVotes)
                    upsertMetadata(id, 'simkl_votes', simklVotes);
                if (traktRating)
                    upsertMetadata(id, 'trakt_rating', traktRating);
                if (traktVotes)
                    upsertMetadata(id, 'trakt_votes', traktVotes);
                if (tmdbTagline)
                    upsertMetadata(id, 'tagline', tmdbTagline);
                if (tmdbKeywords)
                    upsertMetadata(id, 'keywords', JSON.stringify(tmdbKeywords));
                if (tmdbProductionCompanies)
                    upsertMetadata(id, 'production_companies', JSON.stringify(tmdbProductionCompanies));
                if (tmdbProductionCountries)
                    upsertMetadata(id, 'production_countries', JSON.stringify(tmdbProductionCountries));
                if (metadata.director && typeof metadata.director === 'object') {
                    upsertMetadata(id, 'director', JSON.stringify(metadata.director));
                }
                if (probeResult.audioTracks.length > 0)
                    upsertMetadata(id, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
                if (probeResult.subtitleTracks.length > 0)
                    upsertMetadata(id, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
                if (probeResult.resolution) {
                    database_1.default.prepare('INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) VALUES (?,?,\'resolution\',?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value').run((0, uuid_1.v4)(), id, probeResult.resolution);
                }
                const edition = this.parseEditionFromFilename(fileNameWithoutExt);
                if (edition) {
                    upsertMetadata(id, 'release_version', edition);
                }
                triggerChapterScan(filePath, id, null);
                (0, scan_events_1.emitScanEvent)('item_added', `Tillagd: ${metadata.title || path.basename(filePath)} ${metadata.year ? `(${metadata.year})` : ''}`, 'Movie');
                return 'added';
            }
        }
        catch (e) {
            console.error(`[Scanner] Error saving to DB for ${filePath}:`, e);
            (0, scan_events_1.emitScanEvent)('scan_error', `Fel vid import: ${path.basename(filePath)}`, 'Movie');
            return 'skipped';
        }
    }
    /**
     * Parse season+episode numbers from a filename.
     * Supports: S01E01, s1e1, 1x01, Season 1 Episode 1, etc.
     */
    parseEpisodeNumbers(filename) {
        const patterns = [
            /[Ss](\d{1,3})[Ee](\d{1,3})/, // S01E01
            /(\d{1,2})x(\d{1,3})/, // 1x01
            /[Ss]eason\s*(\d+)\s*[Ee]pisode\s*(\d+)/i,
        ];
        for (const re of patterns) {
            const m = filename.match(re);
            if (m)
                return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
        }
        return null;
    }
    /**
     * Determine the show's root folder relative to the library scan path.
     * Example: libraryPath="C:/Shows", filePath="C:/Shows/Breaking Bad/Season 1/ep.mkv"
     *   → showDir = "C:/Shows/Breaking Bad"
     */
    getShowDirectory(libraryPath, filePath) {
        const rel = path.relative(libraryPath, filePath);
        const parts = rel.split(path.sep);
        // The first segment is always the show folder
        return path.join(libraryPath, parts[0]);
    }
    /**
     * Search TMDB for a TV show by title and optional year.
     */
    async searchTVShow(title, year) {
        const apiKey = database_1.default.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get()?.value;
        if (!apiKey)
            return null;
        const prefLang = database_1.default.prepare("SELECT value FROM system_settings WHERE key='METADATA_LANGUAGE'").get()?.value || 'sv-SE';
        try {
            const resp = await axios_1.default.get('https://api.themoviedb.org/3/search/tv', {
                params: { api_key: apiKey, query: title, language: prefLang, first_air_date_year: year }
            });
            const results = resp.data?.results || [];
            if (results.length === 0)
                return null;
            // Prefer exact year match
            if (year) {
                const exact = results.find((r) => r.first_air_date?.startsWith(year.toString()));
                if (exact)
                    return exact;
            }
            return results[0];
        }
        catch (e) {
            return null;
        }
    }
    /**
     * Process a single TV episode file.
     * Creates/updates the parent show in media_items and the episode in episodes.
     */
    async processEpisodeFile(filePath, libraryPath, preferLocalNfo = true) {
        try {
            const fileNameWithoutExt = path.parse(filePath).name;
            const parsed = this.parseEpisodeNumbers(fileNameWithoutExt);
            if (!parsed) {
                console.log(`[Scanner] Could not parse S/E from: ${path.basename(filePath)}`);
                (0, scan_events_1.emitScanEvent)('item_skipped', `Kan inte tolka S/E: ${path.basename(filePath)}`, 'Show');
                return 'skipped';
            }
            const { season, episode: episodeNum } = parsed;
            // Determine show directory and title
            const showDir = this.getShowDirectory(libraryPath, filePath);
            const showDirName = path.basename(showDir);
            const showTitle = this.parseTitleFromFilename(showDirName);
            const showYear = this.parseYearFromFilename(showDirName) ?? undefined;
            // ── 1. Find or create show in media_items ──────────────────
            let showRow = database_1.default.prepare(`
        SELECT id, title, tmdb_id FROM media_items WHERE type='Show' AND (
          lower(title) = lower(?) OR lower(title) = lower(?)
        ) AND deleted_at IS NULL LIMIT 1
      `).get(showTitle, showDirName);
            let showId;
            let tmdbShowId = null;
            if (!showRow) {
                // Look up TMDB
                const tmdbShow = await this.searchTVShow(showTitle, showYear);
                const posterUrl = tmdbShow?.poster_path ? tmdb_1.tmdbService.getImageUrl(tmdbShow.poster_path, 'w500') : null;
                const fanartUrl = tmdbShow?.backdrop_path ? tmdb_1.tmdbService.getImageUrl(tmdbShow.backdrop_path, 'original') : null;
                const genre = tmdbShow?.genres?.map((g) => g.name).join(', ') || null;
                const plot = tmdbShow?.overview || null;
                const year = tmdbShow?.first_air_date ? parseInt(tmdbShow.first_air_date.substring(0, 4), 10) : showYear ?? null;
                const displayTitle = tmdbShow?.name || showTitle;
                tmdbShowId = tmdbShow?.id?.toString() || null;
                showId = (0, uuid_1.v4)();
                database_1.default.prepare(`
          INSERT INTO media_items (id, title, type, plot, year, genre, poster_path, fanart_path, tmdb_id)
          VALUES (?, ?, 'Show', ?, ?, ?, ?, ?, ?)
        `).run(showId, displayTitle, plot, year, genre, posterUrl, fanartUrl, tmdbShowId);
                console.log(`[Scanner] Created show: ${displayTitle}`);
            }
            else {
                showId = showRow.id;
                tmdbShowId = showRow.tmdb_id;
            }
            // ── 2. Probe file for audio/subtitle tracks ────────────────
            const probeResult = await this.probeMediaFile(filePath);
            // ── 3. Look up TMDB episode title if available ─────────────
            let episodeTitle = null;
            let episodeAirDate = null;
            if (tmdbShowId) {
                try {
                    const apiKey = database_1.default.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get()?.value;
                    const prefLang = database_1.default.prepare("SELECT value FROM system_settings WHERE key='METADATA_LANGUAGE'").get()?.value || 'sv-SE';
                    if (apiKey) {
                        const epResp = await axios_1.default.get(`https://api.themoviedb.org/3/tv/${tmdbShowId}/season/${season}/episode/${episodeNum}`, { params: { api_key: apiKey, language: prefLang } });
                        episodeTitle = epResp.data?.name || null;
                        episodeAirDate = epResp.data?.air_date || null;
                    }
                }
                catch (_) { }
            }
            // ── 4. Upsert episode ─────────────────────────────────────
            const existing = database_1.default.prepare(`
        SELECT id FROM episodes WHERE show_id = ? AND season_number = ? AND episode_number = ?
      `).get(showId, season, episodeNum);
            let episodeId;
            if (existing) {
                database_1.default.prepare(`UPDATE episodes SET file_path = ?, title = COALESCE(?, title), air_date = COALESCE(?, air_date) WHERE id = ?`)
                    .run(filePath, episodeTitle, episodeAirDate, existing.id);
                episodeId = existing.id;
                // Update track metadata
                if (probeResult.audioTracks.length > 0 || probeResult.subtitleTracks.length > 0) {
                    const upsertEpMeta = (key, val) => {
                        database_1.default.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run((0, uuid_1.v4)(), showId, `ep_${episodeId}_${key}`, val);
                    };
                    if (probeResult.audioTracks.length > 0)
                        upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
                    if (probeResult.subtitleTracks.length > 0)
                        upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
                }
                triggerChapterScan(filePath, null, episodeId);
                (0, scan_events_1.emitScanEvent)('item_updated', `Uppdaterad: ${showDirName} S${String(season).padStart(2, '0')}E${String(episodeNum).padStart(2, '0')}`, 'Show');
                return 'updated';
            }
            else {
                episodeId = (0, uuid_1.v4)();
                database_1.default.prepare(`
          INSERT INTO episodes (id, show_id, season_number, episode_number, title, file_path, air_date)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(episodeId, showId, season, episodeNum, episodeTitle, filePath, episodeAirDate);
                console.log(`[Scanner] Added S${String(season).padStart(2, '0')}E${String(episodeNum).padStart(2, '0')} of ${showDirName}`);
                // Store track metadata on the show's media_item
                const upsertEpMeta = (key, val) => {
                    database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run((0, uuid_1.v4)(), showId, `ep_${episodeId}_${key}`, val);
                };
                if (probeResult.audioTracks.length > 0)
                    upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
                if (probeResult.subtitleTracks.length > 0)
                    upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
                // Mark show as having a season premiere if this is E01 of a new season (season > 1)
                if (episodeNum === 1 && season > 1) {
                    database_1.default.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, 'has_season_premiere', '1')
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value='1'
          `).run((0, uuid_1.v4)(), showId);
                    (0, scan_events_1.emitScanEvent)('item_added', `🎬 Säsongspremiär! ${showDirName} S${String(season).padStart(2, '0')}E01`, 'Show');
                }
                else {
                    (0, scan_events_1.emitScanEvent)('item_added', `Tillagd: ${showDirName} S${String(season).padStart(2, '0')}E${String(episodeNum).padStart(2, '0')}`, 'Show');
                }
                triggerChapterScan(filePath, null, episodeId);
                return 'added';
            }
        }
        catch (e) {
            console.error(`[Scanner] Error processing episode ${filePath}:`, e);
            (0, scan_events_1.emitScanEvent)('scan_error', `Fel vid import: ${path.basename(filePath)}`, 'Show');
            return 'skipped';
        }
    }
    /**
     * Helper to parse release versions/editions from filename
     */
    parseEditionFromFilename(filename) {
        const filenameLower = filename.toLowerCase();
        if (/\buncut\b/i.test(filenameLower))
            return 'Uncut';
        if (/\bdirector\'?s\.?cut\b/i.test(filenameLower))
            return "Director's Cut";
        if (/\bextended\b/i.test(filenameLower))
            return 'Extended Cut';
        if (/\btheatrical\b/i.test(filenameLower))
            return 'Theatrical Cut';
        if (/\bultimate\b/i.test(filenameLower))
            return 'Ultimate Edition';
        if (/\bremastered\b/i.test(filenameLower))
            return 'Remastered';
        if (/\bcollector\'?s\.?edition\b/i.test(filenameLower))
            return "Collector's Edition";
        if (/\bspecial\.?edition\b/i.test(filenameLower))
            return 'Special Edition';
        if (/\b3d\b/i.test(filenameLower))
            return '3D';
        if (/\bimax\b/i.test(filenameLower))
            return 'IMAX';
        return null;
    }
    /**
     * Helper to extract a clean title from a typical piracy filename like "The.Matrix.1999.1080p.mkv"
     */
    parseTitleFromFilename(filename) {
        // Remove year and anything after it
        let title = filename.replace(/\.(19|20)\d{2}\..*/i, '');
        // Remove common quality tags
        title = title.replace(/\b(1080p|720p|2160p|4k|bluray|webrip|x264|x265)\b.*/i, '');
        // Replace dots with spaces
        title = title.replace(/\./g, ' ');
        return title.trim();
    }
    /**
     * Helper to extract year from filename
     */
    parseYearFromFilename(filename) {
        const match = filename.match(/\b(19|20)\d{2}\b/);
        if (match) {
            return parseInt(match[0], 10);
        }
        return null;
    }
    /**
     * Skip non-primary movie assets (trailers, samples, extras) so they are not imported as standalone films.
     * Optionally also checks user-configured extra skip words.
     */
    isSupplementalVideo(filePath, extraSkipWords = []) {
        const name = path.parse(filePath).name.toLowerCase();
        if (/(\b|_|\.|-)(trailer|teaser|sample|featurette|behind.?the.?scenes|extras?)(\b|_|\.|-)/i.test(name)) {
            return true;
        }
        for (const word of extraSkipWords) {
            if (name.includes(word))
                return true;
        }
        return false;
    }
    normalizeRatingValue(value) {
        if (value === undefined || value === null)
            return null;
        const cleaned = value.toString().trim().replace(',', '.').replace(/[^0-9.]/g, '');
        if (!cleaned)
            return null;
        const parsed = Number.parseFloat(cleaned);
        return Number.isFinite(parsed) ? parsed.toString() : null;
    }
    normalizeVotesValue(value) {
        if (value === undefined || value === null)
            return null;
        const cleaned = value.toString().replace(/[^0-9]/g, '');
        if (!cleaned)
            return null;
        const parsed = Number.parseInt(cleaned, 10);
        return Number.isFinite(parsed) ? parsed.toString() : null;
    }
    extractSimklId(payload) {
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
    extractSimklRatings(payload) {
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
                || this.normalizeRatingValue(ratings?.simkl?.rating)
                || this.normalizeRatingValue(ratings?.simkl_rating)
                || this.normalizeRatingValue(candidate?.simkl?.rating)
                || this.normalizeRatingValue(candidate?.simkl_rating)
                || this.normalizeRatingValue(candidate?.simklRating)
                || this.normalizeRatingValue(candidate?.rating);
            simklVotes = simklVotes
                || this.normalizeVotesValue(ratings?.simkl?.votes)
                || this.normalizeVotesValue(ratings?.simkl_votes)
                || this.normalizeVotesValue(candidate?.simkl?.votes)
                || this.normalizeVotesValue(candidate?.simkl_votes)
                || this.normalizeVotesValue(candidate?.simklVotes)
                || this.normalizeVotesValue(candidate?.votes);
            if (simklRating && simklVotes) {
                break;
            }
        }
        return {
            simklRating,
            simklVotes,
        };
    }
    extractTraktRatings(payload) {
        const candidates = [
            payload,
            payload?.movie,
            payload?.show,
            payload?.anime,
            payload?.item,
            payload?.data,
            payload?.result,
        ].filter(Boolean);
        let traktRating = null;
        let traktVotes = null;
        for (const candidate of candidates) {
            const ratings = candidate?.ratings || {};
            const nestedMovie = candidate?.movie || {};
            const nestedShow = candidate?.show || {};
            traktRating = traktRating
                || this.normalizeRatingValue(ratings?.trakt?.rating)
                || this.normalizeRatingValue(ratings?.trakt_rating)
                || this.normalizeRatingValue(candidate?.rating)
                || this.normalizeRatingValue(nestedMovie?.rating)
                || this.normalizeRatingValue(nestedShow?.rating)
                || this.normalizeRatingValue(candidate?.trakt?.rating)
                || this.normalizeRatingValue(candidate?.trakt_rating)
                || this.normalizeRatingValue(candidate?.traktRating);
            traktVotes = traktVotes
                || this.normalizeVotesValue(ratings?.trakt?.votes)
                || this.normalizeVotesValue(ratings?.trakt_votes)
                || this.normalizeVotesValue(candidate?.votes)
                || this.normalizeVotesValue(nestedMovie?.votes)
                || this.normalizeVotesValue(nestedShow?.votes)
                || this.normalizeVotesValue(candidate?.trakt?.votes)
                || this.normalizeVotesValue(candidate?.trakt_votes)
                || this.normalizeVotesValue(candidate?.traktVotes);
            if (traktRating && traktVotes) {
                break;
            }
        }
        return {
            traktRating,
            traktVotes,
        };
    }
    /**
     * Run ffprobe on a video file to detect audio and subtitle tracks.
     * Returns empty arrays if ffprobe is not installed or fails.
     */
    probeMediaFile(filePath) {
        return new Promise((resolve) => {
            const ffprobePath = ffprobe.path;
            const cmd = `"${ffprobePath}" -v quiet -print_format json -show_streams "${filePath.replace(/"/g, '\\"')}"`;
            childProcess.exec(cmd, { timeout: 15000 }, (err, stdout) => {
                if (err) {
                    resolve({ audioTracks: [], subtitleTracks: [], resolution: null });
                    return;
                }
                try {
                    const probe = JSON.parse(stdout);
                    const streams = probe.streams || [];
                    // Derive resolution from the primary video stream.
                    // Skip cover-art codecs (MJPEG etc.) and pick the stream with the largest height.
                    const coverArtCodecs = ['mjpeg', 'png', 'bmp', 'gif', 'tiff', 'webp'];
                    let bestVideo = null;
                    for (const s of streams) {
                        if (s.codec_type !== 'video')
                            continue;
                        if (coverArtCodecs.includes((s.codec_name || '').toLowerCase()))
                            continue;
                        if (bestVideo === null || (s.height || 0) > (bestVideo.height || 0)) {
                            bestVideo = s;
                        }
                    }
                    let resolution = null;
                    if (bestVideo) {
                        const h = bestVideo.height || 0;
                        const w = bestVideo.width || 0;
                        console.log(`[Scanner] ffprobe video stream: codec=${bestVideo.codec_name} w=${w} h=${h}`);
                        // Use width OR height — Scope films (e.g. 1920×800) must be 1080P not 720P.
                        // Use generous thresholds — many encoders produce non-standard widths
                        // e.g. 1916×820 is a Scope 1080P file, NOT 720P.
                        if (w >= 3200 || h >= 2000)
                            resolution = '4K';
                        else if (w >= 1900 || h >= 1000)
                            resolution = '1080P';
                        else if (w >= 1100 || h >= 650)
                            resolution = '720P';
                        else if (w >= 700 || h >= 420)
                            resolution = '480P';
                        else if (h > 0)
                            resolution = `${h}P`;
                        console.log(`[Scanner] Detected resolution: ${resolution}`);
                    }
                    const audioTracks = streams
                        .filter((s) => s.codec_type === 'audio')
                        .map((s, i) => {
                        const lang = (s.tags?.language || 'und').toUpperCase();
                        const codec = (s.codec_name || 'unknown').toUpperCase();
                        const channels = s.channels || 2;
                        const chLabel = channels >= 8 ? '7.1' : channels >= 6 ? '5.1' : 'Stereo';
                        return {
                            index: s.index ?? i,
                            language: lang,
                            codec,
                            channels,
                            label: `${lang === 'SWE' ? 'Svenska' : lang === 'ENG' ? 'English' : lang} (${codec} ${chLabel})`,
                        };
                    });
                    const subtitleTracks = streams
                        .filter((s) => s.codec_type === 'subtitle')
                        .map((s, i) => {
                        const lang = (s.tags?.language || 'und').toUpperCase();
                        const codec = (s.codec_name || 'subrip').toUpperCase();
                        const entry = {
                            index: s.index ?? i,
                            language: lang,
                            codec,
                            label: `${lang === 'SWE' ? 'Svenska' : lang === 'ENG' ? 'English' : lang} (${codec})`,
                        };
                        // Store PGS canvas dimensions — tracks missing these fail to decode in mpv.
                        if (s.width)
                            entry.width = s.width;
                        if (s.height)
                            entry.height = s.height;
                        return entry;
                    });
                    resolve({ audioTracks, subtitleTracks, resolution });
                }
                catch {
                    resolve({ audioTracks: [], subtitleTracks: [], resolution: null });
                }
            });
        });
    }
    /**
     * Extremely simple XML parser to extract basic NFO tags
     */
    parseNfo(nfoPath) {
        try {
            const content = fs.readFileSync(nfoPath, 'utf-8');
            const result = {};
            const titleMatch = content.match(/<title>(.*?)<\/title>/i);
            if (titleMatch)
                result.title = titleMatch[1].trim();
            const plotMatch = content.match(/<plot>(.*?)<\/plot>/is);
            if (plotMatch)
                result.plot = plotMatch[1].trim();
            const yearMatch = content.match(/<year>(\d{4})<\/year>/i);
            if (yearMatch)
                result.year = parseInt(yearMatch[1], 10);
            const genreMatch = content.match(/<genre>(.*?)<\/genre>/i);
            if (genreMatch)
                result.genre = genreMatch[1].trim();
            return result;
        }
        catch (e) {
            console.error(`[Scanner] Failed to parse NFO ${nfoPath}:`, e);
            return {};
        }
    }
    /**
     * Recursively get all files in a directory
     */
    getAllFiles(dirPath, arrayOfFiles = []) {
        try {
            const files = fs.readdirSync(dirPath);
            files.forEach((file) => {
                const fullPath = path.join(dirPath, file);
                if (fs.statSync(fullPath).isDirectory()) {
                    arrayOfFiles = this.getAllFiles(fullPath, arrayOfFiles);
                }
                else {
                    arrayOfFiles.push(fullPath);
                }
            });
        }
        catch (e) {
            console.error(`[Scanner] Error reading directory ${dirPath}:`, e);
        }
        return arrayOfFiles;
    }
}
exports.ScannerService = ScannerService;
exports.mediaScanner = new ScannerService();
