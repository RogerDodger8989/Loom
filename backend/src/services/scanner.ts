import * as fs from 'fs';
import * as path from 'path';
import xml2js from 'xml2js';
import db from '../config/database';
import crypto from 'crypto';

interface ScanResult {
  addedMovies: number;
  addedEpisodes: number;
  addedTracks: number;
  errors: string[];
}

class MediaScanner {
  private parser = new xml2js.Parser({ explicitArray: false, ignoreAttrs: true });

  // Supported extensions
  private videoExtensions = new Set(['.mp4', '.mkv', '.avi', '.mov', '.m4v']);
  private audioExtensions = new Set(['.mp3', '.flac', '.m4a', '.ogg']);

  /**
   * Scans a directory recursively for files matching the given type
   */
  public async scanLibrary(
    basePath: string,
    type: 'Movie' | 'Show' | 'Music',
    preferLocalNfo: boolean
  ): Promise<ScanResult> {
    console.log(`[Scanner] Starting scan on path "${basePath}" for type "${type}". Prefer NFO: ${preferLocalNfo}`);
    
    const result: ScanResult = {
      addedMovies: 0,
      addedEpisodes: 0,
      addedTracks: 0,
      errors: []
    };

    if (!fs.existsSync(basePath)) {
      result.errors.push(`Base path "${basePath}" does not exist`);
      return result;
    }

    try {
      const files = this.getAllFiles(basePath);
      
      for (const file of files) {
        const ext = path.extname(file).toLowerCase();
        
        if (type === 'Movie' && this.videoExtensions.has(ext)) {
          await this.processMovieFile(file, preferLocalNfo, result);
        } else if (type === 'Show' && this.videoExtensions.has(ext)) {
          await this.processShowEpisodeFile(file, preferLocalNfo, result);
        } else if (type === 'Music' && this.audioExtensions.has(ext)) {
          await this.processMusicFile(file, result);
        }
      }
    } catch (err: any) {
      console.error(`[Scanner] Fatal scan error:`, err);
      result.errors.push(err.message || String(err));
    }

    console.log(`[Scanner] Scan completed. Added movies: ${result.addedMovies}, episodes: ${result.addedEpisodes}, tracks: ${result.addedTracks}. Errors: ${result.errors.length}`);
    return result;
  }

  /**
   * Walk the directory tree recursively
   */
  private getAllFiles(dirPath: string, fileList: string[] = []): string[] {
    const files = fs.readdirSync(dirPath);
    for (const file of files) {
      const filepath = path.join(dirPath, file);
      const stat = fs.statSync(filepath);
      if (stat.isDirectory()) {
        this.getAllFiles(filepath, fileList);
      } else {
        fileList.push(filepath);
      }
    }
    return fileList;
  }

  /**
   * Process a physical Movie file
   */
  private async processMovieFile(filePath: string, preferLocalNfo: boolean, result: ScanResult) {
    try {
      const fileName = path.basename(filePath, path.extname(filePath));
      const fileDir = path.dirname(filePath);
      
      // Look for a movie .nfo file (e.g. filename.nfo or movie.nfo)
      let nfoPath = path.join(fileDir, `${fileName}.nfo`);
      if (!fs.existsSync(nfoPath)) {
        nfoPath = path.join(fileDir, 'movie.nfo');
      }

      let title = fileName;
      let plot = '';
      let tmdbId = '';
      let imdbId = '';
      let year = '';

      const resolution = this.detectResolution(fileName);

      if (preferLocalNfo && fs.existsSync(nfoPath)) {
        const nfoContent = fs.readFileSync(nfoPath, 'utf8');
        try {
          const parsed = await this.parser.parseStringPromise(nfoContent);
          if (parsed && parsed.movie) {
            const m = parsed.movie;
            title = m.title || title;
            plot = m.plot || '';
            tmdbId = m.tmdbid || '';
            imdbId = m.imdbid || '';
            year = m.year || '';
          }
        } catch (nfoErr) {
          console.warn(`[Scanner] Error parsing NFO for ${fileName}:`, nfoErr);
        }
      } else {
        // Fallback: parse title & year from name
        const match = fileName.match(/^(.+?)(?:\s*\(?(\d{4})\)?)?$/);
        if (match) {
          title = match[1].trim();
          year = match[2] || '';
        }
        
        // Mock DB TMDB queries for 100% offgrid matching
        tmdbId = `tmdb_${crypto.createHash('md5').update(title + year).digest('hex').substring(0, 8)}`;
        imdbId = `tt_${crypto.createHash('md5').update(title + year).digest('hex').substring(0, 7)}`;
        plot = `This is a locally matched movie titled "${title}" (${year}).`;
      }

      // Generate a unique ID based on file path to support multiple versions cleanly
      const mediaId = 'movie_' + crypto.createHash('sha1').update(filePath).digest('hex').substring(0, 16);

      // 1. Insert movie basic details
      db.prepare(`
        INSERT OR REPLACE INTO media_items (id, title, type, tmdb_id, imdb_id, file_path, added_at)
        VALUES (?, ?, 'Movie', ?, ?, ?, CURRENT_TIMESTAMP)
      `).run(mediaId, title, tmdbId || null, imdbId || null, filePath);

      // 2. Save metadata and handle admin locking
      const metadata = {
        title,
        plot,
        year,
        resolution
      };

      for (const [key, value] of Object.entries(metadata)) {
        if (!value) continue;
        
        // Check if metadata key is locked for this specific mediaId
        const existingLock = db.prepare(`
          SELECT is_locked FROM media_metadata 
          WHERE media_item_id = ? AND metadata_key = ?
        `).all(mediaId, key)[0] as { is_locked: number } | undefined;

        if (existingLock && existingLock.is_locked === 1) {
          console.log(`[Scanner] Key "${key}" is LOCKED for movie "${title}". Skipping overwrite.`);
          continue;
        }

        // Insert metadata
        db.prepare(`
          INSERT OR REPLACE INTO media_metadata (id, media_item_id, metadata_key, metadata_value, is_locked)
          VALUES (?, ?, ?, ?, COALESCE((SELECT is_locked FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?), 0))
        `).run(`${mediaId}_${key}`, mediaId, key, value, mediaId, key);
      }

      result.addedMovies++;
    } catch (err: any) {
      console.error(`[Scanner] Error processing movie: ${filePath}`, err);
      result.errors.push(`Movie file "${filePath}": ${err.message || String(err)}`);
    }
  }

  /**
   * Process a physical Show Episode file (e.g. S01E01)
   */
  private async processShowEpisodeFile(filePath: string, preferLocalNfo: boolean, result: ScanResult) {
    try {
      const fileName = path.basename(filePath, path.extname(filePath));
      const fileDir = path.dirname(filePath);
      
      // Basic naming parse, e.g. "Game of Thrones - S01E03 - Lord Snow" or "S01E03"
      const epMatch = fileName.match(/S(\d+)E(\d+)/i);
      if (!epMatch) {
        // Skip files that don't look like episodes to keep DB clean
        return;
      }
      
      const seasonNum = parseInt(epMatch[1]);
      const episodeNum = parseInt(epMatch[2]);
      
      // Parse show title from directory name or parent directory
      const showDirName = path.basename(path.resolve(fileDir, '..'));
      let showTitle = showDirName;
      
      // Clean up show title from naming noise
      showTitle = showTitle.replace(/\(\d{4}\)/g, '').trim();

      const showId = 'show_' + crypto.createHash('sha1').update(showTitle).digest('hex').substring(0, 16);

      // Ensure the Show exists in media_items
      db.prepare(`
        INSERT OR IGNORE INTO media_items (id, title, type, added_at)
        VALUES (?, ?, 'Show', CURRENT_TIMESTAMP)
      `).run(showId, showTitle);

      // Generate a unique ID for episode based on path
      const episodeId = 'episode_' + crypto.createHash('sha1').update(filePath).digest('hex').substring(0, 16);
      
      let epTitle = `Episode ${episodeNum}`;

      // If NFO parsing is preferred
      const nfoPath = path.join(fileDir, `${fileName}.nfo`);
      if (preferLocalNfo && fs.existsSync(nfoPath)) {
        try {
          const nfoContent = fs.readFileSync(nfoPath, 'utf8');
          const parsed = await this.parser.parseStringPromise(nfoContent);
          if (parsed && parsed.episodedetails) {
            epTitle = parsed.episodedetails.title || epTitle;
          }
        } catch (err) {
          console.warn(`[Scanner] Error parsing Episode NFO for ${fileName}:`, err);
        }
      }

      // Insert episode
      db.prepare(`
        INSERT OR REPLACE INTO episodes (id, show_id, season_number, episode_number, title, file_path)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(episodeId, showId, seasonNum, episodeNum, epTitle, filePath);

      // Auto-extract and register standard chapter-based intro marker if it exists or mock one
      // In real-world, chapter info or a visual tool would generate these
      db.prepare(`
        INSERT OR IGNORE INTO episode_markers (id, episode_id, marker_type, start_time_seconds, end_time_seconds)
        VALUES (?, ?, 'INTRO', 0, 90)
      `).run(`${episodeId}_intro`, episodeId);

      result.addedEpisodes++;
    } catch (err: any) {
      console.error(`[Scanner] Error processing show episode: ${filePath}`, err);
      result.errors.push(`Episode file "${filePath}": ${err.message || String(err)}`);
    }
  }

  /**
   * Process a Music Track
   */
  private async processMusicFile(filePath: string, result: ScanResult) {
    try {
      const fileName = path.basename(filePath, path.extname(filePath));
      
      // Parse file naming for offgrid MP3 scanning: "01 - Title" or "Artist - Title"
      let title = fileName;
      let artist = 'Unknown Artist';
      let album = 'Unknown Album';
      let trackNumber = 1;

      // Try matching standard "01 - Title" or "01. Title"
      const trackMatch = fileName.match(/^(\d+)[\s.-]+(.+)$/);
      if (trackMatch) {
        trackNumber = parseInt(trackMatch[1]);
        title = trackMatch[2].trim();
      }

      // Read parent directory for artist and album structure
      // e.g. /Music/ArtistName/AlbumName/01 - Track.mp3
      const parentDir = path.dirname(filePath);
      const parentDirName = path.basename(parentDir);
      const grandParentDirName = path.basename(path.dirname(parentDir));

      if (grandParentDirName && grandParentDirName !== 'Music' && grandParentDirName !== '.') {
        artist = grandParentDirName;
        album = parentDirName;
      } else {
        album = parentDirName;
      }

      const trackId = 'track_' + crypto.createHash('sha1').update(filePath).digest('hex').substring(0, 16);

      db.prepare(`
        INSERT OR REPLACE INTO music_tracks (id, title, artist, album, file_path, track_number, duration_seconds)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(trackId, title, artist, album, filePath, trackNumber, 240); // default mock 4-minute duration

      result.addedTracks++;
    } catch (err: any) {
      console.error(`[Scanner] Error processing music track: ${filePath}`, err);
      result.errors.push(`Music file "${filePath}": ${err.message || String(err)}`);
    }
  }

  /**
   * Detects video resolution tags in filenames (e.g. 4K, 2160p, 1080p, 720p)
   */
  private detectResolution(fileName: string): string {
    const lowerName = fileName.toLowerCase();
    if (lowerName.includes('2160p') || lowerName.includes('4k') || lowerName.includes('uhd')) {
      return '4K';
    }
    if (lowerName.includes('1080p') || lowerName.includes('fhd')) {
      return '1080p';
    }
    if (lowerName.includes('720p') || lowerName.includes('hd')) {
      return '720p';
    }
    return '1080p'; // Default fallback badge
  }
}

export const mediaScanner = new MediaScanner();
