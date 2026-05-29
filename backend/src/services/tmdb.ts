import axios from 'axios';
import db from '../config/database';

const TMDB_BASE_URL = 'https://api.themoviedb.org/3';

export interface TMDBMovie {
  id: number;
  title: string;
  overview: string;
  release_date: string;
  poster_path: string | null;
  backdrop_path: string | null;
  vote_average?: number;
  credits?: {
    cast: any[];
    crew: any[];
  };
}

export class TMDBService {
  /**
   * Helper to fetch the TMDB API Key from the database
   */
  private getApiKey(): string {
    try {
      const row = db.prepare("SELECT value FROM system_settings WHERE key = 'TMDB_API_KEY'").get() as { value: string } | undefined;
      return row ? row.value : '';
    } catch (e) {
      return '';
    }
  }

  /**
   * Search TMDB for a movie by title and optionally year
   */
  public async searchMovie(title: string, year?: number): Promise<Partial<TMDBMovie> | null> {
    const apiKey = this.getApiKey();

    if (!apiKey) {
      console.log(`[TMDB] No API key found. Returning mock data for: ${title}`);
      return this.getMockMovie(title, year);
    }

    try {
      const response = await axios.get(`${TMDB_BASE_URL}/search/movie`, {
        params: {
          api_key: apiKey,
          query: title,
          year: year,
          language: 'sv-SE' // Prefer Swedish descriptions if available
        }
      });

      if (response.data && response.data.results && response.data.results.length > 0) {
        const match = response.data.results[0];
        // Fetch full details including credits
        try {
          const detailResponse = await axios.get(`${TMDB_BASE_URL}/movie/${match.id}`, {
            params: {
              api_key: apiKey,
              language: 'sv-SE',
              append_to_response: 'credits'
            }
          });
          return detailResponse.data;
        } catch (detailErr) {
          console.error(`[TMDB] Failed to fetch full details for ${match.id}:`, detailErr);
          return match; // fallback to basic search result
        }
      }
      return null;
    } catch (e) {
      console.error(`[TMDB] Failed to search for ${title}:`, e);
      return null;
    }
  }

  /**
   * Generate mock data if TMDB API key is not configured
   */
  private getMockMovie(title: string, year?: number): Partial<TMDBMovie> {
    return {
      title: title,
      overview: `(Mock Data) En fantastisk film om ${title}. Denna data hämtades eftersom ingen TMDB API-nyckel var konfigurerad.`,
      release_date: year ? `${year}-01-01` : '2023-01-01',
      poster_path: null, // TMDB format is /path.jpg
      backdrop_path: null,
      vote_average: 0.0,
      credits: { cast: [], crew: [] }
    };
  }

  /**
   * Helper to convert a TMDB image path to a full URL
   */
  public getImageUrl(path: string | null, size: 'w500' | 'original' = 'w500'): string | null {
    if (!path) return null;
    return `https://image.tmdb.org/t/p/${size}${path}`;
  }
}

export const tmdbService = new TMDBService();
