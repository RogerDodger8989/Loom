import * as fs from 'fs';
import * as path from 'path';
import * as childProcess from 'child_process';
import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';
import { tmdbService } from './tmdb';
import { scanChaptersForItem } from './marker_service';
import { emitScanEvent } from './scan_events';
import axios from 'axios';

function triggerChapterScan(filePath: string, mediaItemId: string | null, episodeId: string | null): void {
  setImmediate(async () => {
    try {
      const count = await scanChaptersForItem(filePath, mediaItemId, episodeId);
      if (count > 0) console.log(`[Scanner] Chapters: ${count} found in ${path.basename(filePath)}`);
    } catch (_) {}
  });
}

const ffprobe = require('@ffprobe-installer/ffprobe');
const ptt = require('parse-torrent-title');

export class ScannerService {
  /**
   * Scan a specific library path for media files and their NFOs
   */
  public async scanLibrary(libraryPath: string, type: 'Movie' | 'Show' | 'Music', preferLocalNfo?: boolean): Promise<{ added: number, updated: number }> {
    if (!fs.existsSync(libraryPath)) {
      console.error(`[Scanner] Path does not exist: ${libraryPath}`);
      emitScanEvent('scan_error', `Sökväg finns ej: ${libraryPath}`, type);
      return { added: 0, updated: 0 };
    }

    emitScanEvent('scan_start', `Startar skanning av ${path.basename(libraryPath)} (${type})`, type);

    // Load user-configured skip words and min file size from settings
    const skipWordsRaw = (db.prepare("SELECT value FROM system_settings WHERE key='SCAN_SKIP_WORDS'").get() as any)?.value || '';
    const minSizeMb = parseFloat((db.prepare("SELECT value FROM system_settings WHERE key='SCAN_MIN_SIZE_MB'").get() as any)?.value || '0');
    const minSizeBytes = minSizeMb > 0 ? minSizeMb * 1024 * 1024 : 0;
    const extraSkipWords = skipWordsRaw
      .split(',')
      .map((w: string) => w.trim().toLowerCase())
      .filter((w: string) => w.length > 0);

    let itemsAdded = 0;
    let itemsUpdated = 0;
    const files = this.getAllFiles(libraryPath);

    // Common video extensions
    const videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'];
    const musicExts = ['.flac', '.mp3', '.ogg', '.vorbis', '.opus', '.m4a'];

    for (const file of files) {
      const ext = path.extname(file).toLowerCase();

      if (videoExts.includes(ext) || musicExts.includes(ext)) {
        // Check size filter
        if (minSizeBytes > 0) {
          try {
            const stat = fs.statSync(file);
            if (stat.size < minSizeBytes) {
              emitScanEvent('item_skipped', `Hoppas över (för liten ${(stat.size / 1024 / 1024).toFixed(1)} MB): ${path.basename(file)}`, type);
              continue;
            }
          } catch (_) {}
        }

        if (this.isSupplementalVideo(file, extraSkipWords)) {
          emitScanEvent('item_skipped', `Hoppas över (tilläggsinnehåll): ${path.basename(file)}`, type);
          continue;
        }

        emitScanEvent('file_found', `Hittade: ${path.basename(file)}`, type);

        if (type === 'Movie' && videoExts.includes(ext)) {
          const result = await this.processMovieFile(file, preferLocalNfo);
          if (result === 'added') itemsAdded++;
          else if (result === 'updated') itemsUpdated++;
        } else if (type === 'Show' && videoExts.includes(ext)) {
          const result = await this.processEpisodeFile(file, libraryPath, preferLocalNfo);
          if (result === 'added') itemsAdded++;
          else if (result === 'updated') itemsUpdated++;
        } else if (type === 'Music' && musicExts.includes(ext)) {
          const result = await this.processMusicFile(file, preferLocalNfo);
          if (result === 'added') itemsAdded++;
          else if (result === 'updated') itemsUpdated++;
        }
      }
    }

    emitScanEvent('scan_complete', `Klar! Tillagda: ${itemsAdded}, Uppdaterade: ${itemsUpdated}`, type);
    return { added: itemsAdded, updated: itemsUpdated };
  }

  /**
   * Process a single movie video file
   * Returns 'added', 'updated', or 'skipped'
   */
  public async processMovieFile(filePath: string, preferLocalNfo: boolean = true): Promise<'added' | 'updated' | 'skipped'> {
    const dir = path.dirname(filePath);
    const fileNameWithoutExt = path.parse(filePath).name;
    const nfoPath = path.join(dir, `${fileNameWithoutExt}.nfo`);
    const fallbackNfoPath = path.join(dir, 'movie.nfo');

    let metadata: any = {
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
      } else if (fs.existsSync(fallbackNfoPath)) {
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

    let tmdbRatings: any = null;
    let tmdbCast: any = null;
    let tmdbProviders: any = null;
    let tmdbTrailer: string | null = null;
    let omdbAwards: string | null = null;
    let tmdbAwards: string | null = null;
    let omdbImdbRating: string | null = null;
    let omdbMetascore: string | null = null;
    let omdbRtRating: string | null = null;
    let simklRating: string | null = null;
    let simklVotes: string | null = null;
    let traktRating: string | null = null;
    let traktVotes: string | null = null;
    let tmdbTagline: string | null = null;
    let omdbImdbVotes: string | null = null;
    let tmdbKeywords: any = null;
    let tmdbProductionCompanies: any = null;
    let tmdbProductionCountries: any = null;

    // Run ffprobe to detect real audio/subtitle tracks
    const probeResult = await this.probeMediaFile(filePath);

    // 2. TMDB API Fetch (Always query online source to enrich metadata with cast, watch providers, original title, awards, etc.)
    const needsOnlineData = true;
    if (needsOnlineData) {
      const tmdbData = await tmdbService.searchMovie(metadata.title, metadata.year);
      if (tmdbData) {
        // TMDB overrides/complements
        if (!metadata.plot && tmdbData.overview) metadata.plot = tmdbData.overview;
        if (tmdbData.release_date) {
          if (!metadata.year) metadata.year = parseInt(tmdbData.release_date.substring(0, 4), 10);
          (metadata as any).release_date = tmdbData.release_date;
        }
        if (tmdbData.tagline) tmdbTagline = tmdbData.tagline;
        
        // Save genres as comma-separated values
        if (tmdbData.genres) {
          metadata.genre = tmdbData.genres.map((g: any) => g.name).join(', ');
        }

        if (tmdbData.keywords?.keywords) {
          tmdbKeywords = tmdbData.keywords.keywords.map((k: any) => k.name);
        }

        if (tmdbData.production_companies) {
          const mainCompanies = tmdbData.production_companies
            .filter((company: any) => company && company.name)
            .slice(0, 2);

          tmdbProductionCompanies = mainCompanies.map((company: any) => ({
            id: company.id,
            name: company.name,
            logo_path: company.logo_path ? tmdbService.getImageUrl(company.logo_path, 'w500') : null,
            origin_country: company.origin_country || null
          }));
        }

        if (tmdbData.production_countries) {
          tmdbProductionCountries = tmdbData.production_countries.map((country: any) => ({
            iso_3166_1: country.iso_3166_1,
            name: country.name
          }));
        }

        // Save TMDB / IMDb IDs
        if (tmdbData.id) metadata.tmdb_id = tmdbData.id.toString();
        if (tmdbData.imdb_id) metadata.imdb_id = tmdbData.imdb_id;
        const imdbId = tmdbData.imdb_id || tmdbData.external_ids?.imdb_id || null;

        // Save original_title
        if (tmdbData.original_title) metadata.original_title = tmdbData.original_title;

        // Save director (with ID for clickability)
        let tmdbDirector = null;
        if (tmdbData.credits && tmdbData.credits.crew) {
          const dirObj = tmdbData.credits.crew.find((c: any) => c.job === 'Director');
          if (dirObj) {
            tmdbDirector = { id: dirObj.id, name: dirObj.name };
            metadata.director = tmdbDirector;
          }
        }

        // Save logo_path for ClearLOGO display
        if (tmdbData.logo_path) {
          metadata.logo_path = tmdbService.getImageUrl(tmdbData.logo_path, 'w500');
        }

        // Save collection details
        if (tmdbData.belongs_to_collection) {
          metadata.collection_name = tmdbData.belongs_to_collection.name;
          metadata.collection_id = tmdbData.belongs_to_collection.id.toString();
        }

        // Only use TMDB images if we didn't find local ones
        if (!metadata.poster_path && tmdbData.poster_path) {
          metadata.poster_path = tmdbService.getImageUrl(tmdbData.poster_path, 'w500');
        }
        if (!metadata.fanart_path && tmdbData.backdrop_path) {
          metadata.fanart_path = tmdbService.getImageUrl(tmdbData.backdrop_path, 'original');
        }
        if (tmdbData.vote_average) {
          tmdbRatings = { tmdb: tmdbData.vote_average, tmdb_votes: tmdbData.vote_count };
        }
        if (tmdbData.credits && tmdbData.credits.cast) {
          tmdbCast = tmdbData.credits.cast.slice(0, 15).map((c: any) => ({
            id: c.id,
            name: c.name,
            character: c.character,
            profile_path: tmdbService.getImageUrl(c.profile_path, 'w500')
          }));
        }

        // Extract watch providers
        if (tmdbData['watch/providers'] && tmdbData['watch/providers'].results) {
          tmdbProviders = tmdbData['watch/providers'].results;
        }

        // Extract YouTube trailer link
        if (tmdbData.trailer_url) {
          tmdbTrailer = tmdbData.trailer_url;
        } else if (tmdbData.videos && tmdbData.videos.results) {
          const trailerObj = tmdbData.videos.results.find((v: any) => v.site === 'YouTube' && v.type === 'Trailer');
          if (trailerObj) {
            tmdbTrailer = `https://www.youtube.com/watch?v=${trailerObj.key}`;
          }
        }

        // Query OMDb API for awards AND ratings
        const omdbKey = tmdbService.getSetting('OMDB_API_KEY');
        if (omdbKey && imdbId) {
          try {
            const omdbRes = await axios.get(`http://www.omdbapi.com/`, {
              params: { apikey: omdbKey, i: imdbId }
            });
            if (omdbRes.data) {
              if (omdbRes.data.Awards) omdbAwards = omdbRes.data.Awards;
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
                const rtEntry = omdbRes.data.Ratings.find((r: any) => r.Source === 'Rotten Tomatoes');
                if (rtEntry) omdbRtRating = rtEntry.Value; // e.g. "87%"
              }
            }
          } catch (omdbErr) {
            console.error(`[Scanner] OMDb API request failed for ${imdbId}:`, omdbErr);
          }
        }

        // Query Simkl API for awards and ratings, and Trakt for its own ratings
        const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
        const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
        if (simklClientId && imdbId) {
          try {
            const simklLookupRes = await axios.get(`https://api.simkl.com/search/id`, {
              params: { imdb: imdbId, client_id: simklClientId }
            });
            const simklLookupData = Array.isArray(simklLookupRes.data)
              ? simklLookupRes.data[0]
              : simklLookupRes.data;

            const simklId = this.extractSimklId(simklLookupData);

            if (simklId) {
              const simklRatingsRes = await axios.get(`https://api.simkl.com/ratings`, {
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
          } catch (simklErr) {
            console.error(`[Scanner] Simkl/Trakt API request failed for ${imdbId}:`, simklErr);
          }
        }

        if (traktApiKey && imdbId) {
          try {
            const traktRes = await axios.get(`https://api.trakt.tv/search/imdb/${imdbId}`, {
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
          } catch (traktErr) {
            console.error(`[Scanner] Trakt API request failed for ${imdbId}:`, traktErr);
          }
        }

        if (!omdbAwards && tmdbData.id) {
          tmdbAwards = await tmdbService.fetchAwardsSummary(tmdbData.id.toString());
        }
      }
    }

    // Helper to upsert metadata
    const upsertMetadata = (itemId: string, key: string, value: string) => {
      // Check if locked first
      const lock = db.prepare('SELECT is_locked FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?').get(itemId, key) as { is_locked: number } | undefined;
      if (lock && lock.is_locked === 1) return;

      db.prepare(`
        INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
        VALUES (?, ?, ?, ?)
        ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
      `).run(uuidv4(), itemId, key, value);
    };

    // 3. Insert or Update DB
    try {
      const existing = db.prepare('SELECT id FROM media_items WHERE file_path = ?').all(filePath) as { id: string }[];
      
      const directorName = metadata.director && typeof metadata.director === 'object'
        ? (metadata.director as any).name
        : metadata.director || null;

      if (existing && existing.length > 0) {
        const mediaId = existing[0].id;
        
        // Fetch locks from media_metadata table
        const locks = db.prepare('SELECT metadata_key FROM media_metadata WHERE media_item_id = ? AND is_locked = 1').all(mediaId) as { metadata_key: string }[];
        const lockedKeys = locks.map(l => l.metadata_key);

        // Build UPDATE query dynamically to respect locks
        let updateFields = [];
        let params = [];
        
        if (!lockedKeys.includes('title')) { updateFields.push('title = ?'); params.push(metadata.title); }
        if (!lockedKeys.includes('plot')) { updateFields.push('plot = ?'); params.push(metadata.plot); }
        if (!lockedKeys.includes('year')) { updateFields.push('year = ?'); params.push(metadata.year); }
        if (!lockedKeys.includes('genre')) { updateFields.push('genre = ?'); params.push(metadata.genre); }
        if (!lockedKeys.includes('poster_path')) { updateFields.push('poster_path = ?'); params.push(metadata.poster_path); }
        if (!lockedKeys.includes('fanart_path')) { updateFields.push('fanart_path = ?'); params.push(metadata.fanart_path); }
        if (!lockedKeys.includes('tmdb_id')) { updateFields.push('tmdb_id = ?'); params.push(metadata.tmdb_id || null); }
        if (!lockedKeys.includes('imdb_id')) { updateFields.push('imdb_id = ?'); params.push(metadata.imdb_id || null); }
        if (!lockedKeys.includes('collection_name')) { updateFields.push('collection_name = ?'); params.push(metadata.collection_name || null); }
        if (!lockedKeys.includes('collection_id')) { updateFields.push('collection_id = ?'); params.push(metadata.collection_id || null); }
        if (!lockedKeys.includes('director')) { updateFields.push('director = ?'); params.push(directorName); }

        if (!lockedKeys.includes('original_title')) { updateFields.push('original_title = ?'); params.push(metadata.original_title || null); }
        if ((metadata as any).release_date) { updateFields.push('release_date = ?'); params.push((metadata as any).release_date); }

        if (updateFields.length > 0) {
          params.push(filePath);
          db.prepare(`
            UPDATE media_items 
            SET ${updateFields.join(', ')}
            WHERE file_path = ?
          `).run(...params);
          
          if (tmdbRatings) upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
          if (tmdbCast) upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
          if (tmdbProviders) upsertMetadata(mediaId, 'watch_providers', JSON.stringify(tmdbProviders));
          if (tmdbTrailer) upsertMetadata(mediaId, 'trailer_url', tmdbTrailer);
            if (omdbAwards || tmdbAwards) upsertMetadata(mediaId, 'awards', omdbAwards || tmdbAwards as string);
          if (omdbImdbRating) upsertMetadata(mediaId, 'imdb_rating', omdbImdbRating);
          if (omdbImdbVotes) upsertMetadata(mediaId, 'imdb_votes', omdbImdbVotes);
          if (omdbMetascore) upsertMetadata(mediaId, 'metascore', omdbMetascore);
          if (omdbRtRating) upsertMetadata(mediaId, 'rt_rating', omdbRtRating);
          if (simklRating) upsertMetadata(mediaId, 'simkl_rating', simklRating);
          if (simklVotes) upsertMetadata(mediaId, 'simkl_votes', simklVotes);
          if (traktRating) upsertMetadata(mediaId, 'trakt_rating', traktRating);
          if (traktVotes) upsertMetadata(mediaId, 'trakt_votes', traktVotes);
          if (tmdbTagline) upsertMetadata(mediaId, 'tagline', tmdbTagline);
          if (tmdbKeywords) upsertMetadata(mediaId, 'keywords', JSON.stringify(tmdbKeywords));
          if (tmdbProductionCompanies) upsertMetadata(mediaId, 'production_companies', JSON.stringify(tmdbProductionCompanies));
          if (tmdbProductionCountries) upsertMetadata(mediaId, 'production_countries', JSON.stringify(tmdbProductionCountries));
          if (metadata.director && typeof metadata.director === 'object') {
            upsertMetadata(mediaId, 'director', JSON.stringify(metadata.director));
          }
          if (probeResult.audioTracks.length > 0) upsertMetadata(mediaId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
          if (probeResult.subtitleTracks.length > 0) upsertMetadata(mediaId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
          // Always write resolution – bypass the user-lock since it is a file property.
          if (probeResult.resolution) {
            db.prepare('INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) VALUES (?,?,\'resolution\',?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value').run(uuidv4(), mediaId, probeResult.resolution);
          }

          const edition = this.parseEditionFromFilename(fileNameWithoutExt);
          if (edition) {
            upsertMetadata(mediaId, 'release_version', edition);
          }

          triggerChapterScan(filePath, mediaId, null);
          emitScanEvent('item_updated', `Uppdaterad: ${metadata.title || path.basename(filePath)}`, 'Movie');
          return 'updated';
        }

        if (tmdbRatings) upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
        if (tmdbCast) upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
        if (tmdbProviders) upsertMetadata(mediaId, 'watch_providers', JSON.stringify(tmdbProviders));
        if (tmdbTrailer) upsertMetadata(mediaId, 'trailer_url', tmdbTrailer);
        if (omdbAwards) upsertMetadata(mediaId, 'awards', omdbAwards);
        if (omdbImdbRating) upsertMetadata(mediaId, 'imdb_rating', omdbImdbRating);
        if (omdbImdbVotes) upsertMetadata(mediaId, 'imdb_votes', omdbImdbVotes);
        if (omdbMetascore) upsertMetadata(mediaId, 'metascore', omdbMetascore);
        if (omdbRtRating) upsertMetadata(mediaId, 'rt_rating', omdbRtRating);
        if (simklRating) upsertMetadata(mediaId, 'simkl_rating', simklRating);
        if (metadata.director && typeof metadata.director === 'object') {
          upsertMetadata(mediaId, 'director', JSON.stringify(metadata.director));
        }
        if (probeResult.audioTracks.length > 0) upsertMetadata(mediaId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
        if (probeResult.subtitleTracks.length > 0) upsertMetadata(mediaId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
        if (probeResult.resolution) {
          db.prepare('INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) VALUES (?,?,\'resolution\',?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value').run(uuidv4(), mediaId, probeResult.resolution);
        }

        const edition = this.parseEditionFromFilename(fileNameWithoutExt);
        if (edition) {
          upsertMetadata(mediaId, 'release_version', edition);
        }

        triggerChapterScan(filePath, mediaId, null);
        emitScanEvent('item_updated', `Uppdaterad (metadata): ${metadata.title || path.basename(filePath)}`, 'Movie');
        return 'skipped';
      } else {
        // Insert new
        let movieId: string | null = null;
        const tmdbMovieId = metadata.tmdb_id;
        const displayTitle = metadata.title;

        // Before inserting, check if a movie with this tmdb_id already exists!
        if (tmdbMovieId) {
          const existingTmdbMovie = db.prepare('SELECT id FROM media_items WHERE type="Movie" AND tmdb_id=? AND deleted_at IS NULL').get(tmdbMovieId) as any;
          if (existingTmdbMovie) {
            movieId = existingTmdbMovie.id;
            
            // Only update file_path if it changed
            const currentRecord = db.prepare('SELECT file_path FROM media_items WHERE id=?').get(movieId) as any;
            if (currentRecord && currentRecord.file_path !== filePath) {
              db.prepare(`UPDATE media_items SET file_path = ? WHERE id = ?`).run(filePath, movieId);
            }
          }
        }

        if (!movieId) {
          movieId = uuidv4();
          db.prepare(`
            INSERT INTO media_items (id, title, type, plot, year, genre, poster_path, fanart_path, tmdb_id, imdb_id, collection_name, collection_id, director, original_title, file_path, release_date)
            VALUES (?, ?, 'Movie', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `).run(
            movieId,
            metadata.title,
            metadata.plot,
            metadata.year,
            metadata.genre,
            metadata.poster_path,
            metadata.fanart_path,
            metadata.tmdb_id || null,
            metadata.imdb_id || null,
            metadata.collection_name || null,
            metadata.collection_id || null,
            directorName,
            metadata.original_title || null,
            filePath,
            (metadata as any).release_date || null
          );
        }
        
        if (tmdbRatings) upsertMetadata(movieId, 'ratings', JSON.stringify(tmdbRatings));
        if (tmdbCast) upsertMetadata(movieId, 'cast', JSON.stringify(tmdbCast));
        if (tmdbProviders) upsertMetadata(movieId, 'watch_providers', JSON.stringify(tmdbProviders));
        if (tmdbTrailer) upsertMetadata(movieId, 'trailer_url', tmdbTrailer);
        if (omdbAwards || tmdbAwards) upsertMetadata(movieId, 'awards', omdbAwards || tmdbAwards as string);
        if (omdbImdbRating) upsertMetadata(movieId, 'imdb_rating', omdbImdbRating);
        if (omdbImdbVotes) upsertMetadata(movieId, 'imdb_votes', omdbImdbVotes);
        if (omdbMetascore) upsertMetadata(movieId, 'metascore', omdbMetascore);
        if (omdbRtRating) upsertMetadata(movieId, 'rt_rating', omdbRtRating);
        if (simklRating) upsertMetadata(movieId, 'simkl_rating', simklRating);
        if (simklVotes) upsertMetadata(movieId, 'simkl_votes', simklVotes);
        if (traktRating) upsertMetadata(movieId, 'trakt_rating', traktRating);
        if (traktVotes) upsertMetadata(movieId, 'trakt_votes', traktVotes);
        if (tmdbTagline) upsertMetadata(movieId, 'tagline', tmdbTagline);
        if (tmdbKeywords) upsertMetadata(movieId, 'keywords', JSON.stringify(tmdbKeywords));
        if (tmdbProductionCompanies) upsertMetadata(movieId, 'production_companies', JSON.stringify(tmdbProductionCompanies));
        if (tmdbProductionCountries) upsertMetadata(movieId, 'production_countries', JSON.stringify(tmdbProductionCountries));
        if (metadata.director && typeof metadata.director === 'object') {
          upsertMetadata(movieId, 'director', JSON.stringify(metadata.director));
        }
        if (probeResult.audioTracks.length > 0) upsertMetadata(movieId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
        if (probeResult.subtitleTracks.length > 0) upsertMetadata(movieId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
        if (probeResult.resolution) {
          db.prepare('INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) VALUES (?,?,\'resolution\',?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value').run(uuidv4(), movieId, probeResult.resolution);
        }

        const edition = this.parseEditionFromFilename(fileNameWithoutExt);
        if (edition) {
          upsertMetadata(movieId, 'release_version', edition);
        }

        triggerChapterScan(filePath, movieId, null);
        emitScanEvent('item_added', `Tillagd: ${metadata.title || path.basename(filePath)} ${metadata.year ? `(${metadata.year})` : ''}`, 'Movie');
        return 'added';
      }
    } catch (e) {
      console.error(`[Scanner] Error saving to DB for ${filePath}:`, e);
      emitScanEvent('scan_error', `Fel vid import: ${path.basename(filePath)}`, 'Movie');
      return 'skipped';
    }
  }

  /**
   * Process a single music file
   */
  public async processMusicFile(filePath: string, _preferLocalNfo: boolean = true): Promise<'added' | 'updated' | 'skipped'> {
    const dir = path.dirname(filePath);
    const fileNameWithoutExt = path.parse(filePath).name;
    const probeResult = await this.probeMediaFile(filePath);
    
    let metadata: any = {
      title: fileNameWithoutExt,
      artist: null,
      album: null,
      year: null,
      genre: null,
      track: null,
      poster_path: null,
      musicbrainz_id: null,
      acoustid_id: null,
      soundtrack_movie_id: null,
    };

    // 1. Läs interna taggar (ID3/Vorbis/FLAC)
    if (probeResult.formatTags) {
      const t = probeResult.formatTags;
      if (t.title) metadata.title = t.title;
      if (t.artist || t.album_artist) metadata.artist = t.artist || t.album_artist;
      if (t.album) metadata.album = t.album;
      if (t.date) metadata.year = parseInt(t.date.substring(0,4), 10);
      if (t.genre) metadata.genre = t.genre;
      if (t.track) metadata.track = t.track;
      if (t.tracknumber) metadata.track = t.tracknumber;
      if (t.musicbrainz_trackid) metadata.musicbrainz_id = t.musicbrainz_trackid;
    }

    // 1b. Fallback: parsa artist och album från mappstruktur när taggar saknas
    // Förväntad struktur: .../ArtistBokstav/Artistnamn/År - Album/spår.flac
    //                 eller .../Artistnamn/Album/spår.flac
    const dirParts = dir.split(path.sep);
    const albumFolder = dirParts[dirParts.length - 1]; // "2005 - Batman Begins"
    const artistFolder = dirParts[dirParts.length - 2]; // "Hans Zimmer"  eller "H" (enbokstavs)
    const grandFolder = dirParts[dirParts.length - 3];  // "H" om struktur är .../H/Hans Zimmer/...

    if (!metadata.album && albumFolder) {
      // Strippa ledande år: "2005 - Batman Begins" → "Batman Begins"
      metadata.album = albumFolder.replace(/^\d{4}\s*[-–]\s*/, '').trim();
    }
    if (!metadata.artist) {
      // Hoppa över enbokstavsmappar (indexeringsmappar som "H", "A")
      if (artistFolder && artistFolder.length > 2) {
        metadata.artist = artistFolder;
      } else if (grandFolder && grandFolder.length > 2) {
        metadata.artist = grandFolder;
      }
    }

    // 2. Extrahera inbäddade covers eller hitta cover.jpg/folder.jpg i mappen
    const possibleCovers = ['cover.jpg', 'cover.png', 'folder.jpg', 'album.jpg'];
    for (const p of possibleCovers) {
      const pPath = path.join(dir, p);
      if (fs.existsSync(pPath)) {
        metadata.poster_path = pPath;
        break;
      }
    }

    // 3. Länka soundtrack till film — testa IMDb-id i mappnamn, sen exakt titelmatch, sen partiell match
    {
      const folderName = path.basename(dir);
      const imdbMatch = folderName.match(/tt\d{7,8}/);
      if (imdbMatch) {
        const movie = db.prepare('SELECT id FROM media_items WHERE imdb_id = ? AND deleted_at IS NULL').get(imdbMatch[0]) as any;
        if (movie) metadata.soundtrack_movie_id = movie.id;
      } else if (metadata.album) {
        const movie = (
          db.prepare("SELECT id FROM media_items WHERE title = ? AND type='Movie' AND deleted_at IS NULL").get(metadata.album) as any
          ?? db.prepare("SELECT id FROM media_items WHERE title LIKE ? AND type='Movie' AND deleted_at IS NULL").get(`%${metadata.album}%`) as any
        );
        if (movie) metadata.soundtrack_movie_id = movie.id;
      }
    }

    const trackNumber = metadata.track ? parseInt(metadata.track, 10) || null : null;

    try {
      const existing = db.prepare('SELECT id FROM music_tracks WHERE file_path = ?').get(filePath) as { id: string } | undefined;

      if (existing) {
        db.prepare(`
          UPDATE music_tracks
          SET title = ?, artist = ?, album = ?, track_number = ?, musicbrainz_id = ?, soundtrack_movie_id = ?
          WHERE file_path = ?
        `).run(metadata.title, metadata.artist, metadata.album, trackNumber, metadata.musicbrainz_id, metadata.soundtrack_movie_id, filePath);

        emitScanEvent('item_updated', `Uppdaterad musik: ${metadata.title}`, 'Music');
        return 'updated';
      } else {
        db.prepare(`
          INSERT INTO music_tracks (id, title, artist, album, file_path, track_number, musicbrainz_id, soundtrack_movie_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(uuidv4(), metadata.title, metadata.artist, metadata.album, filePath, trackNumber, metadata.musicbrainz_id, metadata.soundtrack_movie_id);

        emitScanEvent('item_added', `Tillagd musik: ${metadata.title}`, 'Music');
        return 'added';
      }
    } catch (e: any) {
      console.error(`[Scanner] Error saving to DB for ${filePath}:`, e);
      require('fs').appendFileSync('C:/Users/denni/Desktop/Egna appar/Loom/backend/scanner_error.log', e.toString() + '\n');
      return 'skipped';
    }
  }

  /**
   * Parse season+episode numbers from a filename.
   * Supports: S01E01, s1e1, 1x01, Season 1 Episode 1, etc.
   */
  private parseEpisodeNumbers(filename: string): { season: number; episode: number } | null {
    const patterns = [
      /[Ss](\d{1,3})[Ee](\d{1,3})/,          // S01E01
      /(\d{1,2})x(\d{1,3})/,                   // 1x01
      /[Ss]eason\s*(\d+)\s*[Ee]pisode\s*(\d+)/i,
    ];
    for (const re of patterns) {
      const m = filename.match(re);
      if (m) return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
    }
    return null;
  }

  /**
   * Determine the show's root folder relative to the library scan path.
   * Example: libraryPath="C:/Shows", filePath="C:/Shows/Breaking Bad/Season 1/ep.mkv"
   *   → showDir = "C:/Shows/Breaking Bad"
   */
  private getShowDirectory(libraryPath: string, filePath: string): string {
    const rel = path.relative(libraryPath, filePath);
    const parts = rel.split(path.sep);
    // The first segment is always the show folder
    return path.join(libraryPath, parts[0]);
  }

  /**
   * Search TMDB for a TV show by title and optional year.
   */
  private async searchTVShow(title: string, year?: number): Promise<any | null> {
    const apiKey = (db.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get() as any)?.value;
    if (!apiKey) return null;
    const prefLang = (db.prepare("SELECT value FROM system_settings WHERE key='METADATA_LANGUAGE'").get() as any)?.value || 'sv-SE';
    try {
      const resp = await axios.get('https://api.themoviedb.org/3/search/tv', {
        params: { api_key: apiKey, query: title, language: prefLang, first_air_date_year: year }
      });
      const results: any[] = resp.data?.results || [];
      if (results.length === 0) return null;
      // Prefer exact year match
      if (year) {
        const exact = results.find((r: any) => r.first_air_date?.startsWith(year.toString()));
        if (exact) return exact;
      }
      return results[0];
    } catch (e) {
      return null;
    }
  }

  /**
   * Process a single TV episode file.
   * Creates/updates the parent show in media_items and the episode in episodes.
   */
  public async processEpisodeFile(
    filePath: string,
    libraryPath: string,
    preferLocalNfo: boolean = true
  ): Promise<'added' | 'updated' | 'skipped'> {
    try {
      const fileNameWithoutExt = path.parse(filePath).name;
      const parsed = this.parseEpisodeNumbers(fileNameWithoutExt);
      if (!parsed) {
        console.log(`[Scanner] Could not parse S/E from: ${path.basename(filePath)}`);
        emitScanEvent('item_skipped', `Kan inte tolka S/E: ${path.basename(filePath)}`, 'Show');
        return 'skipped';
      }
      const { season, episode: episodeNum } = parsed;

      // Determine show directory and title
      const showDir = this.getShowDirectory(libraryPath, filePath);
      const showDirName = path.basename(showDir);
      const showTitle = this.parseTitleFromFilename(showDirName);
      const showYear = this.parseYearFromFilename(showDirName) ?? undefined;

      console.log(`[Scanner Debug] filePath: ${filePath}`);
      console.log(`[Scanner Debug] showDirName: "${showDirName}", showTitle: "${showTitle}", showYear: ${showYear}`);

      // ── 1. Find or create show in media_items ──────────────────
      let showRow = db.prepare(`
        SELECT id, title, tmdb_id FROM media_items WHERE type='Show' AND (
          lower(title) = lower(?) OR lower(title) = lower(?)
        ) AND deleted_at IS NULL LIMIT 1
      `).get(showTitle, showDirName) as any;

      console.log(`[Scanner Debug] showRow found:`, showRow);

      let showId: string | undefined = undefined;
      let tmdbShowId: string | null = null;

      if (!showRow) {
        // Look up TMDB
        const tmdbShow = await this.searchTVShow(showTitle, showYear);
        const posterUrl = tmdbShow?.poster_path ? tmdbService.getImageUrl(tmdbShow.poster_path, 'w500') : null;
        const fanartUrl = tmdbShow?.backdrop_path ? tmdbService.getImageUrl(tmdbShow.backdrop_path, 'original') : null;
        const genre = tmdbShow?.genres?.map((g: any) => g.name).join(', ') || null;
        const plot = tmdbShow?.overview || null;
        const year = tmdbShow?.first_air_date ? parseInt(tmdbShow.first_air_date.substring(0, 4), 10) : showYear ?? null;
        const displayTitle = tmdbShow?.name || showTitle;
        tmdbShowId = tmdbShow?.id?.toString() || null;

        // Before inserting, check if a show with this tmdb_id already exists!
        if (tmdbShowId) {
          const existingTmdbShow = db.prepare('SELECT id FROM media_items WHERE type=\'Show\' AND tmdb_id=? AND deleted_at IS NULL').get(tmdbShowId) as any;
          if (existingTmdbShow) {
            showId = existingTmdbShow.id;
          }
        }

        if (!showId) {
          showId = uuidv4();
          db.prepare(`
            INSERT INTO media_items (id, title, type, plot, year, genre, poster_path, fanart_path, tmdb_id)
            VALUES (?, ?, 'Show', ?, ?, ?, ?, ?, ?)
          `).run(showId, displayTitle, plot, year, genre, posterUrl, fanartUrl, tmdbShowId);
          console.log(`[Scanner] Created show: ${displayTitle}`);
        }

        // Fetch full show data to store seasons metadata
        if (tmdbShowId) {
          try {
            const fullShow = await tmdbService.fetchShowById(tmdbShowId);
            if (fullShow?.external_ids?.imdb_id) {
              db.prepare(`UPDATE media_items SET imdb_id = ? WHERE id = ?`).run(fullShow.external_ids.imdb_id, showId);
            }
            if (fullShow) {
              const upsertShowMeta = (key: string, val: string) => {
                db.prepare(`INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
                  VALUES (?,?,?,?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value`)
                  .run(uuidv4(), showId, key, val);
              };
              if (fullShow.number_of_seasons) upsertShowMeta('number_of_seasons', String(fullShow.number_of_seasons));
              if (fullShow.status) upsertShowMeta('status', fullShow.status);
              if (fullShow.next_episode_to_air) upsertShowMeta('next_episode_to_air', JSON.stringify(fullShow.next_episode_to_air));
              if (fullShow.vote_average != null) {
                upsertShowMeta('tmdb_rating', String(fullShow.vote_average));
                upsertShowMeta('ratings', JSON.stringify({ tmdb: fullShow.vote_average, tmdb_votes: fullShow.vote_count }));
              }
              if (fullShow.seasons?.length) {
                const seasonsData = fullShow.seasons.map((s: any) => ({
                  season_number: s.season_number,
                  name: s.name,
                  episode_count: s.episode_count,
                  air_date: s.air_date || null,
                  poster_path: s.poster_path ? tmdbService.getImageUrl(s.poster_path, 'w342') : null,
                  overview: s.overview || null,
                }));
                upsertShowMeta('seasons_json', JSON.stringify(seasonsData));
              }
            }
          } catch (_) {}
        }
      } else {
        showId = showRow.id;
        tmdbShowId = showRow.tmdb_id;
      }

      // ── 2. Probe file for audio/subtitle tracks ────────────────
      const probeResult = await this.probeMediaFile(filePath);

      // ── 3. Check if episode already exists to avoid unnecessary TMDB lookups
      const existing = db.prepare(`
        SELECT id, file_path FROM episodes WHERE show_id = ? AND season_number = ? AND episode_number = ?
      `).get(showId, season, episodeNum) as any;

      let episodeId: string;

      if (existing) {
        episodeId = existing.id;
        
        // Update file path if it changed
        if (existing.file_path !== filePath) {
          db.prepare(`UPDATE episodes SET file_path = ? WHERE id = ?`).run(filePath, episodeId);
        }

        // Always update track metadata in case the file was replaced or probed differently
        if (probeResult.audioTracks.length > 0 || probeResult.subtitleTracks.length > 0) {
          const upsertEpMeta = (key: string, val: string) => {
            db.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run(uuidv4(), showId, `ep_${episodeId}_${key}`, val);
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
              `https://api.themoviedb.org/3/tv/${tmdbShowId}/season/${season}/episode/${episodeNum}`,
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
                  `https://api.themoviedb.org/3/tv/${tmdbShowId}/season/${season}/episode/${episodeNum}`,
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
      db.prepare(`
        INSERT INTO episodes (id, show_id, season_number, episode_number, title, file_path, air_date, overview, still_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(episodeId, showId, season, episodeNum, episodeTitle, filePath, episodeAirDate, episodeOverview, episodeStillPath);
      console.log(`[Scanner] Added S${String(season).padStart(2,'0')}E${String(episodeNum).padStart(2,'0')} of ${showDirName}`);

      // Store track metadata on the show's media_item
      const upsertEpMeta = (key: string, val: string) => {
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), showId, `ep_${episodeId}_${key}`, val);
      };
      if (probeResult.audioTracks.length > 0) upsertEpMeta('audio_tracks', JSON.stringify(probeResult.audioTracks));
      if (probeResult.subtitleTracks.length > 0) upsertEpMeta('subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
      if (episodeGuestStars) upsertEpMeta('guest_stars', JSON.stringify(episodeGuestStars));

        // Mark show as having a season premiere if this is E01 of a new season (season > 1)
        if (episodeNum === 1 && season > 1) {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, 'has_season_premiere', '1')
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value='1'
          `).run(uuidv4(), showId);
          emitScanEvent('item_added', `🎬 Säsongspremiär! ${showDirName} S${String(season).padStart(2,'0')}E01`, 'Show');
        } else {
          emitScanEvent('item_added', `Tillagd: ${showDirName} S${String(season).padStart(2,'0')}E${String(episodeNum).padStart(2,'0')}`, 'Show');
        }

        triggerChapterScan(filePath, null, episodeId);
        return 'added';
    } catch (e) {
      console.error(`[Scanner] Error processing episode ${filePath}:`, e);
      emitScanEvent('scan_error', `Fel vid import: ${path.basename(filePath)}`, 'Show');
      return 'skipped';
    }
  }

  /**
   * Refresh show metadata from TMDB for an already-scanned show item.
   */
  public async refreshShowMetadata(showId: string, tmdbShowId: string): Promise<void> {
    const upsert = (key: string, val: string) => {
      db.prepare(`INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
        VALUES (?,?,?,?) ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value`)
        .run(uuidv4(), showId, key, val);
    };

    const fullShow = await tmdbService.fetchShowById(tmdbShowId);
    if (!fullShow) return;

    const posterUrl  = fullShow.poster_path   ? tmdbService.getImageUrl(fullShow.poster_path,   'w500')    : null;
    const fanartUrl  = fullShow.backdrop_path  ? tmdbService.getImageUrl(fullShow.backdrop_path,  'original') : null;
    const genre      = fullShow.genres?.map((g: any) => g.name).join(', ') || null;
    const plot       = fullShow.overview || null;
    const year       = fullShow.first_air_date ? parseInt(fullShow.first_air_date.substring(0, 4), 10) : null;
    const title      = fullShow.name || null;

    // Force-overwrite all core fields (no COALESCE — refresh means fetch fresh)
    db.prepare(`UPDATE media_items SET
      poster_path    = COALESCE(?, poster_path),
      fanart_path    = COALESCE(?, fanart_path),
      genre          = COALESCE(?, genre),
      plot           = COALESCE(?, plot),
      year           = COALESCE(?, year),
      title          = COALESCE(?, title),
      imdb_id        = COALESCE(?, imdb_id)
      WHERE id = ?`).run(posterUrl, fanartUrl, genre, plot, year, title, fullShow.external_ids?.imdb_id || null, showId);

    if (fullShow.status)            upsert('status',            fullShow.status);
    if (fullShow.last_air_date)     upsert('last_air_date',     fullShow.last_air_date);
    if (fullShow.number_of_seasons) upsert('number_of_seasons', String(fullShow.number_of_seasons));
    if (fullShow.seasons?.length) {
      const seasonsData = fullShow.seasons.map((s: any) => ({
        season_number: s.season_number,
        name:          s.name,
        episode_count: s.episode_count,
        air_date:      s.air_date || null,
        overview:      s.overview || null,
        poster_path:   s.poster_path ? tmdbService.getImageUrl(s.poster_path, 'w342') : null,
      }));
      upsert('seasons_json', JSON.stringify(seasonsData));
    }
    if (fullShow.next_episode_to_air) {
      upsert('next_episode_to_air', JSON.stringify(fullShow.next_episode_to_air));
    } else {
      db.prepare(`DELETE FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'next_episode_to_air'`).run(showId);
    }
    if (fullShow.created_by?.length) {
      upsert('created_by', JSON.stringify(fullShow.created_by.map((c: any) => ({ id: String(c.id), name: c.name }))));
    }
    if (fullShow.networks?.length) {
      upsert('networks', JSON.stringify(fullShow.networks.map((n: any) => n.name)));
    }
    // Production countries — always overwrite so bad data (e.g., wrong country) gets fixed
    if (fullShow.production_countries?.length) {
      upsert('production_countries', JSON.stringify(
        fullShow.production_countries.map((c: any) => ({ iso_3166_1: c.iso_3166_1, name: c.name }))
      ));
    }
    if (fullShow.origin_country?.length) {
      upsert('origin_country', JSON.stringify(fullShow.origin_country));
    }
    // Production companies
    if (fullShow.production_companies?.length) {
      upsert('production_companies', JSON.stringify(
        fullShow.production_companies.slice(0, 3).map((c: any) => ({
          id: c.id, name: c.name,
          logo_path: c.logo_path ? tmdbService.getImageUrl(c.logo_path, 'w500') : null,
          origin_country: c.origin_country || null,
        }))
      ));
    }
    if (fullShow.trailer_url) upsert('trailer_url', fullShow.trailer_url);
    const cast = fullShow.credits?.cast?.slice(0, 20).map((m: any) => ({
      id: String(m.id), name: m.name, character: m.character || '',
      profile_path: m.profile_path ? tmdbService.getImageUrl(m.profile_path, 'w185') : null,
    }));
    if (cast?.length) upsert('cast', JSON.stringify(cast));
    if (fullShow['watch/providers']?.results) upsert('watch_providers', JSON.stringify(fullShow['watch/providers']?.results));
    if (fullShow.logo_path) upsert('logo_path', tmdbService.getImageUrl(fullShow.logo_path, 'original') || '');
    // Trakt / Simkl ratings via existing enrichment if available
    const vote = fullShow.vote_average;
    if (vote != null) upsert('ratings', JSON.stringify({ tmdb: vote, tmdb_votes: fullShow.vote_count }));
    upsert('tmdb_rating', vote != null ? String(vote) : '');
    // Keywords
    if (fullShow.keywords?.results?.length) {
      upsert('keywords', JSON.stringify(fullShow.keywords.results.map((k: any) => k.name)));
    }
    if (fullShow.tagline) upsert('tagline', fullShow.tagline);

    // Backfill episode still_path and overview in background
    const apiKey = (db.prepare("SELECT value FROM system_settings WHERE key='TMDB_API_KEY'").get() as any)?.value;
    const prefLang = (db.prepare("SELECT value FROM system_settings WHERE key='METADATA_LANGUAGE'").get() as any)?.value || 'sv-SE';
    if (apiKey) {
      const episodes = db.prepare(`SELECT id, season_number, episode_number FROM episodes WHERE show_id = ? AND deleted_at IS NULL`).all(showId) as any[];
      setImmediate(async () => {
        for (const ep of episodes) {
          try {
            const epResp = await axios.get(
              `https://api.themoviedb.org/3/tv/${tmdbShowId}/season/${ep.season_number}/episode/${ep.episode_number}`,
              { params: { api_key: apiKey, language: prefLang } }
            );
            const overview = epResp.data?.overview || null;
            const stillPath = epResp.data?.still_path
              ? tmdbService.getImageUrl(epResp.data.still_path, 'w500')
              : null;
            const title = epResp.data?.name || null;
            const airDate = epResp.data?.air_date || null;
            db.prepare(`UPDATE episodes SET title = COALESCE(?, title), air_date = COALESCE(?, air_date), overview = COALESCE(?, overview), still_path = COALESCE(?, still_path) WHERE id = ?`)
              .run(title, airDate, overview, stillPath, ep.id);
          } catch (_) {}
        }
        console.log(`[Scanner] Episode metadata backfill done for show ${showId}`);
      });
    }
  }

  /**
   * Helper to parse release versions/editions from filename
   */
  private parseEditionFromFilename(filename: string): string | null {
    const filenameLower = filename.toLowerCase();
    if (/\buncut\b/i.test(filenameLower)) return 'Uncut';
    if (/\bdirector\'?s\.?cut\b/i.test(filenameLower)) return "Director's Cut";
    if (/\bextended\b/i.test(filenameLower)) return 'Extended Cut';
    if (/\btheatrical\b/i.test(filenameLower)) return 'Theatrical Cut';
    if (/\bultimate\b/i.test(filenameLower)) return 'Ultimate Edition';
    if (/\bremastered\b/i.test(filenameLower)) return 'Remastered';
    if (/\bcollector\'?s\.?edition\b/i.test(filenameLower)) return "Collector's Edition";
    if (/\bspecial\.?edition\b/i.test(filenameLower)) return 'Special Edition';
    if (/\b3d\b/i.test(filenameLower)) return '3D';
    if (/\bimax\b/i.test(filenameLower)) return 'IMAX';
    return null;
  }

  /**
   * Helper to extract a clean title from a typical piracy filename like "The.Matrix.1999.1080p.mkv"
   */
  private parseTitleFromFilename(filename: string): string {
    const info = ptt.parse(filename);
    if (info.title) {
       let title = info.title;
       title = title.replace(/\s*[\(\[]?(19|20)\d{2}[\)\]]?\s*$/i, '');
       return title.trim();
    }
    
    // Fallback
    let title = filename;
    title = title.replace(/[\.\s]*\b(1080p|720p|2160p|4k|bluray|webrip|x264|x265|h264|hevc)\b.*/i, '');
    title = title.replace(/\.(19|20)\d{2}\..*/i, '');
    title = title.replace(/\s*[\(\[]?(19|20)\d{2}[\)\]]?\s*$/i, '');
    title = title.replace(/\./g, ' ');
    
    return title.trim();
  }

  /**
   * Helper to extract year from filename
   */
  private parseYearFromFilename(filename: string): number | null {
    const info = ptt.parse(filename);
    if (info.year) {
      return info.year;
    }
    
    // Fallback
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
  private isSupplementalVideo(filePath: string, extraSkipWords: string[] = []): boolean {
    const name = path.parse(filePath).name.toLowerCase();
    if (/(\b|_|\.|-)(trailer|teaser|sample|featurette|behind.?the.?scenes|extras?)(\b|_|\.|-)/i.test(name)) {
      return true;
    }
    for (const word of extraSkipWords) {
      if (name.includes(word)) return true;
    }
    return false;
  }

  private normalizeRatingValue(value: any): string | null {
    if (value === undefined || value === null) return null;
    const cleaned = value.toString().trim().replace(',', '.').replace(/[^0-9.]/g, '');
    if (!cleaned) return null;
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? parsed.toString() : null;
  }

  private normalizeVotesValue(value: any): string | null {
    if (value === undefined || value === null) return null;
    const cleaned = value.toString().replace(/[^0-9]/g, '');
    if (!cleaned) return null;
    const parsed = Number.parseInt(cleaned, 10);
    return Number.isFinite(parsed) ? parsed.toString() : null;
  }

  private extractSimklId(payload: any): string | null {
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

  private extractSimklRatings(payload: any): {
    simklRating: string | null;
    simklVotes: string | null;
  } {
    const candidates = [
      payload,
      payload?.movie,
      payload?.show,
      payload?.anime,
      payload?.item,
      payload?.data,
      payload?.result,
    ].filter(Boolean);

    let simklRating: string | null = null;
    let simklVotes: string | null = null;

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

  private extractTraktRatings(payload: any): {
    traktRating: string | null;
    traktVotes: string | null;
  } {
    const candidates = [
      payload,
      payload?.movie,
      payload?.show,
      payload?.anime,
      payload?.item,
      payload?.data,
      payload?.result,
    ].filter(Boolean);

    let traktRating: string | null = null;
    let traktVotes: string | null = null;

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
  private probeMediaFile(filePath: string): Promise<{
    audioTracks: Array<{ index: number; language: string; codec: string; channels: number; label: string }>;
    subtitleTracks: Array<{ index: number; language: string; codec: string; label: string }>;
    resolution: string | null;
    formatTags: any;
  }> {
    return new Promise((resolve) => {
      const ffprobePath = ffprobe.path;
      const cmd = `"${ffprobePath}" -v quiet -print_format json -show_format -show_streams "${filePath.replace(/"/g, '\\"')}"`;
      childProcess.exec(cmd, { timeout: 15000 }, (err, stdout) => {
        if (err) {
          resolve({ audioTracks: [], subtitleTracks: [], resolution: null, formatTags: {} });
          return;
        }
        try {
          const probe = JSON.parse(stdout);
          const streams: any[] = probe.streams || [];

          // Derive resolution from the primary video stream.
          // Skip cover-art codecs (MJPEG etc.) and pick the stream with the largest height.
          const coverArtCodecs = ['mjpeg', 'png', 'bmp', 'gif', 'tiff', 'webp'];
          let bestVideo: any = null;
          for (const s of streams) {
            if (s.codec_type !== 'video') continue;
            if (coverArtCodecs.includes((s.codec_name || '').toLowerCase())) continue;
            if (bestVideo === null || (s.height || 0) > (bestVideo.height || 0)) {
              bestVideo = s;
            }
          }
          let resolution: string | null = null;
          if (bestVideo) {
            const h: number = bestVideo.height || 0;
            const w: number = bestVideo.width || 0;
            console.log(`[Scanner] ffprobe video stream: codec=${bestVideo.codec_name} w=${w} h=${h}`);
            // Use width OR height — Scope films (e.g. 1920×800) must be 1080P not 720P.
            // Use generous thresholds — many encoders produce non-standard widths
            // e.g. 1916×820 is a Scope 1080P file, NOT 720P.
            if (w >= 3200 || h >= 2000)      resolution = '4K';
            else if (w >= 1900 || h >= 1000) resolution = '1080P';
            else if (w >= 1100 || h >= 650)  resolution = '720P';
            else if (w >= 700  || h >= 420)  resolution = '480P';
            else if (h > 0)                  resolution = `${h}P`;
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
              const entry: any = {
                index: s.index ?? i,
                language: lang,
                codec,
                label: `${lang === 'SWE' ? 'Svenska' : lang === 'ENG' ? 'English' : lang} (${codec})`,
              };
              // Store PGS canvas dimensions — tracks missing these fail to decode in mpv.
              if (s.width) entry.width = s.width;
              if (s.height) entry.height = s.height;
              return entry;
            });

          resolve({ audioTracks, subtitleTracks, resolution, formatTags: probe.format?.tags || {} });
        } catch {
          resolve({ audioTracks: [], subtitleTracks: [], resolution: null, formatTags: {} });
        }
      });
    });
  }

  /**
   * Extremely simple XML parser to extract basic NFO tags
   */
  private parseNfo(nfoPath: string): Partial<any> {
    try {
      const content = fs.readFileSync(nfoPath, 'utf-8');
      const result: any = {};

      const titleMatch = content.match(/<title>(.*?)<\/title>/i);
      if (titleMatch) result.title = titleMatch[1].trim();

      const plotMatch = content.match(/<plot>(.*?)<\/plot>/is);
      if (plotMatch) result.plot = plotMatch[1].trim();

      const yearMatch = content.match(/<year>(\d{4})<\/year>/i);
      if (yearMatch) result.year = parseInt(yearMatch[1], 10);

      const genreMatch = content.match(/<genre>(.*?)<\/genre>/i);
      if (genreMatch) result.genre = genreMatch[1].trim();

      return result;
    } catch (e) {
      console.error(`[Scanner] Failed to parse NFO ${nfoPath}:`, e);
      return {};
    }
  }

  /**
   * Recursively get all files in a directory
   */
  private getAllFiles(dirPath: string, arrayOfFiles: string[] = []): string[] {
    try {
      const files = fs.readdirSync(dirPath);

      files.forEach((file) => {
        if (file === '.trash') return;
        const fullPath = path.join(dirPath, file);
        if (fs.statSync(fullPath).isDirectory()) {
          arrayOfFiles = this.getAllFiles(fullPath, arrayOfFiles);
        } else {
          arrayOfFiles.push(fullPath);
        }
      });
    } catch (e) {
      console.error(`[Scanner] Error reading directory ${dirPath}:`, e);
    }

    return arrayOfFiles;
  }
}

export const mediaScanner = new ScannerService();
