import * as fs from 'fs';
import * as path from 'path';
import * as childProcess from 'child_process';
import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';
import { tmdbService } from './tmdb';
import axios from 'axios';

export class ScannerService {
  /**
   * Scan a specific library path for media files and their NFOs
   */
  public async scanLibrary(libraryPath: string, type: 'Movie' | 'Show' | 'Music', preferLocalNfo?: boolean): Promise<{ added: number, updated: number }> {
    if (!fs.existsSync(libraryPath)) {
      console.error(`[Scanner] Path does not exist: ${libraryPath}`);
      return { added: 0, updated: 0 };
    }

    let itemsAdded = 0;
    let itemsUpdated = 0;
    const files = this.getAllFiles(libraryPath);

    // Common video extensions
    const videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'];

    for (const file of files) {
      const ext = path.extname(file).toLowerCase();
      
      if (videoExts.includes(ext)) {
        if (type === 'Movie') {
          const result = await this.processMovieFile(file, preferLocalNfo);
          if (result === 'added') itemsAdded++;
          else if (result === 'updated') itemsUpdated++;
        } else if (type === 'Show') {
          // TODO: Process TV Shows
        }
      }
    }

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
    let tmdbTagline: string | null = null;
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
        if (!metadata.year && tmdbData.release_date) metadata.year = parseInt(tmdbData.release_date.substring(0, 4), 10);
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
          tmdbRatings = { tmdb: tmdbData.vote_average };
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
        if (tmdbData.videos && tmdbData.videos.results) {
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

        // Query Simkl API for awards AND ratings
        const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
        if (simklClientId && imdbId) {
          try {
            const simklRes = await axios.get(`https://api.simkl.com/search/id`, {
              params: { imdb: imdbId, client_id: simklClientId }
            });
            if (simklRes.data && Array.isArray(simklRes.data) && simklRes.data.length > 0) {
              const simklData = simklRes.data[0];
              if (simklData.ratings && simklData.ratings.simkl) {
                const ratingVal = simklData.ratings.simkl.rating;
                if (ratingVal) {
                  simklRating = ratingVal.toString();
                }
              }
            }
          } catch (simklErr) {
            console.error(`[Scanner] Simkl API request failed for ${imdbId}:`, simklErr);
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
          if (omdbMetascore) upsertMetadata(mediaId, 'metascore', omdbMetascore);
          if (omdbRtRating) upsertMetadata(mediaId, 'rt_rating', omdbRtRating);
          if (simklRating) upsertMetadata(mediaId, 'simkl_rating', simklRating);
          if (tmdbTagline) upsertMetadata(mediaId, 'tagline', tmdbTagline);
          if (tmdbKeywords) upsertMetadata(mediaId, 'keywords', JSON.stringify(tmdbKeywords));
          if (tmdbProductionCompanies) upsertMetadata(mediaId, 'production_companies', JSON.stringify(tmdbProductionCompanies));
          if (tmdbProductionCountries) upsertMetadata(mediaId, 'production_countries', JSON.stringify(tmdbProductionCountries));
          if (metadata.director && typeof metadata.director === 'object') {
            upsertMetadata(mediaId, 'director', JSON.stringify(metadata.director));
          }
          if (probeResult.audioTracks.length > 0) upsertMetadata(mediaId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
          if (probeResult.subtitleTracks.length > 0) upsertMetadata(mediaId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
          
          return 'updated';
        }
        
        if (tmdbRatings) upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
        if (tmdbCast) upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
        if (tmdbProviders) upsertMetadata(mediaId, 'watch_providers', JSON.stringify(tmdbProviders));
        if (tmdbTrailer) upsertMetadata(mediaId, 'trailer_url', tmdbTrailer);
        if (omdbAwards) upsertMetadata(mediaId, 'awards', omdbAwards);
        if (omdbImdbRating) upsertMetadata(mediaId, 'imdb_rating', omdbImdbRating);
        if (omdbMetascore) upsertMetadata(mediaId, 'metascore', omdbMetascore);
        if (omdbRtRating) upsertMetadata(mediaId, 'rt_rating', omdbRtRating);
        if (simklRating) upsertMetadata(mediaId, 'simkl_rating', simklRating);
        if (metadata.director && typeof metadata.director === 'object') {
          upsertMetadata(mediaId, 'director', JSON.stringify(metadata.director));
        }
        if (probeResult.audioTracks.length > 0) upsertMetadata(mediaId, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
        if (probeResult.subtitleTracks.length > 0) upsertMetadata(mediaId, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
        
        return 'skipped';
      } else {
        // Insert new
        const id = uuidv4();
        db.prepare(`
          INSERT INTO media_items (id, title, type, plot, year, genre, poster_path, fanart_path, tmdb_id, imdb_id, collection_name, collection_id, director, original_title, file_path)
          VALUES (?, ?, 'Movie', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          id, 
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
          filePath
        );
        
        if (tmdbRatings) upsertMetadata(id, 'ratings', JSON.stringify(tmdbRatings));
        if (tmdbCast) upsertMetadata(id, 'cast', JSON.stringify(tmdbCast));
        if (tmdbProviders) upsertMetadata(id, 'watch_providers', JSON.stringify(tmdbProviders));
        if (tmdbTrailer) upsertMetadata(id, 'trailer_url', tmdbTrailer);
        if (omdbAwards || tmdbAwards) upsertMetadata(id, 'awards', omdbAwards || tmdbAwards as string);
        if (omdbImdbRating) upsertMetadata(id, 'imdb_rating', omdbImdbRating);
        if (omdbMetascore) upsertMetadata(id, 'metascore', omdbMetascore);
        if (omdbRtRating) upsertMetadata(id, 'rt_rating', omdbRtRating);
        if (simklRating) upsertMetadata(id, 'simkl_rating', simklRating);
        if (tmdbTagline) upsertMetadata(id, 'tagline', tmdbTagline);
        if (tmdbKeywords) upsertMetadata(id, 'keywords', JSON.stringify(tmdbKeywords));
        if (tmdbProductionCompanies) upsertMetadata(id, 'production_companies', JSON.stringify(tmdbProductionCompanies));
        if (tmdbProductionCountries) upsertMetadata(id, 'production_countries', JSON.stringify(tmdbProductionCountries));
        if (metadata.director && typeof metadata.director === 'object') {
          upsertMetadata(id, 'director', JSON.stringify(metadata.director));
        }
        if (probeResult.audioTracks.length > 0) upsertMetadata(id, 'audio_tracks', JSON.stringify(probeResult.audioTracks));
        if (probeResult.subtitleTracks.length > 0) upsertMetadata(id, 'subtitle_tracks', JSON.stringify(probeResult.subtitleTracks));
        
        return 'added';
      }
    } catch (e) {
      console.error(`[Scanner] Error saving to DB for ${filePath}:`, e);
      return 'skipped';
    }
  }

  /**
   * Helper to extract a clean title from a typical piracy filename like "The.Matrix.1999.1080p.mkv"
   */
  private parseTitleFromFilename(filename: string): string {
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
  private parseYearFromFilename(filename: string): number | null {
    const match = filename.match(/\b(19|20)\d{2}\b/);
    if (match) {
      return parseInt(match[0], 10);
    }
    return null;
  }

  /**
   * Run ffprobe on a video file to detect audio and subtitle tracks.
   * Returns empty arrays if ffprobe is not installed or fails.
   */
  private probeMediaFile(filePath: string): Promise<{
    audioTracks: Array<{ index: number; language: string; codec: string; channels: number; label: string }>;
    subtitleTracks: Array<{ index: number; language: string; codec: string; label: string }>;
  }> {
    return new Promise((resolve) => {
      const cmd = `ffprobe -v quiet -print_format json -show_streams "${filePath.replace(/"/g, '\\"')}"`;
      childProcess.exec(cmd, { timeout: 15000 }, (err, stdout) => {
        if (err) {
          // ffprobe not found or failed — return empty gracefully
          resolve({ audioTracks: [], subtitleTracks: [] });
          return;
        }
        try {
          const probe = JSON.parse(stdout);
          const streams: any[] = probe.streams || [];

          const audioTracks = streams
            .filter((s) => s.codec_type === 'audio')
            .map((s, i) => {
              const lang = (s.tags?.language || 'und').toUpperCase();
              const codec = (s.codec_name || 'unknown').toUpperCase();
              const channels = s.channels || 2;
              const chLabel = channels >= 6 ? '5.1' : channels >= 8 ? '7.1' : 'Stereo';
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
              return {
                index: s.index ?? i,
                language: lang,
                codec,
                label: `${lang === 'SWE' ? 'Svenska' : lang === 'ENG' ? 'English' : lang} (${codec})`,
              };
            });

          resolve({ audioTracks, subtitleTracks });
        } catch {
          resolve({ audioTracks: [], subtitleTracks: [] });
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
