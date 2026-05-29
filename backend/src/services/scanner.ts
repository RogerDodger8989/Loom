import * as fs from 'fs';
import * as path from 'path';
import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';
import { tmdbService } from './tmdb';

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
  private async processMovieFile(filePath: string, preferLocalNfo: boolean = true): Promise<'added' | 'updated' | 'skipped'> {
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
    }

    let tmdbRatings: any = null;
    let tmdbCast: any = null;

    // 2. TMDB API Fetch (if preferLocalNfo is false, OR if local NFO is missing/incomplete)
    if (!preferLocalNfo || (!hasLocalNfo && !metadata.plot)) {
      const tmdbData = await tmdbService.searchMovie(metadata.title, metadata.year);
      if (tmdbData) {
        // TMDB overrides/complements
        if (!metadata.plot && tmdbData.overview) metadata.plot = tmdbData.overview;
        if (!metadata.year && tmdbData.release_date) metadata.year = parseInt(tmdbData.release_date.substring(0, 4), 10);
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

        if (updateFields.length > 0) {
          params.push(filePath);
          db.prepare(`
            UPDATE media_items 
            SET ${updateFields.join(', ')}
            WHERE file_path = ?
          `).run(...params);
          
          if (tmdbRatings) upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
          if (tmdbCast) upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
          
          return 'updated';
        }
        
        if (tmdbRatings) upsertMetadata(mediaId, 'ratings', JSON.stringify(tmdbRatings));
        if (tmdbCast) upsertMetadata(mediaId, 'cast', JSON.stringify(tmdbCast));
        
        return 'skipped';
      } else {
        // Insert new
        const id = uuidv4();
        db.prepare(`
          INSERT INTO media_items (id, title, type, plot, year, genre, poster_path, fanart_path, file_path)
          VALUES (?, ?, 'Movie', ?, ?, ?, ?, ?, ?)
        `).run(id, metadata.title, metadata.plot, metadata.year, metadata.genre, metadata.poster_path, metadata.fanart_path, filePath);
        
        if (tmdbRatings) upsertMetadata(id, 'ratings', JSON.stringify(tmdbRatings));
        if (tmdbCast) upsertMetadata(id, 'cast', JSON.stringify(tmdbCast));
        
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
