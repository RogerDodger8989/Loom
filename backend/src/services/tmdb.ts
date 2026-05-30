import axios from 'axios';
import db from '../config/database';

const TMDB_BASE_URL = 'https://api.themoviedb.org/3';

export interface TMDBMovie {
  id: number;
  title: string;
  original_title?: string;
  tagline?: string;
  overview: string;
  release_date: string;
  poster_path: string | null;
  backdrop_path: string | null;
  vote_average?: number;
  imdb_id?: string | null;
  external_ids?: {
    imdb_id?: string | null;
  };
  logo_path?: string | null;
  genres?: Array<{ id: number; name: string }>;
  keywords?: {
    keywords?: Array<{ id: number; name: string }>;
  };
  production_companies?: Array<{
    id: number;
    name: string;
    logo_path: string | null;
    origin_country?: string;
  }>;
  production_countries?: Array<{
    iso_3166_1: string;
    name: string;
  }>;
  belongs_to_collection?: {
    id: number;
    name: string;
    poster_path: string | null;
    backdrop_path: string | null;
  } | null;
  credits?: {
    cast: any[];
    crew: any[];
  };
  'watch/providers'?: {
    results: {
      [countryCode: string]: {
        link: string;
        flatrate?: any[];
        rent?: any[];
        buy?: any[];
      };
    };
  };
  videos?: {
    results: any[];
  };
}

export class TMDBService {
  /**
   * Helper to fetch the TMDB API Key from the database
   */
  private getApiKey(): string {
    return this.getSetting('TMDB_API_KEY');
  }

  /**
   * Helper to fetch any system setting from database
   */
  public getSetting(key: string): string {
    try {
      const row = db.prepare("SELECT value FROM system_settings WHERE key = ?").get(key) as { value: string } | undefined;
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

    const prefLang = this.getSetting('METADATA_LANGUAGE') || 'sv-SE';
    const fallbackLang = this.getSetting('METADATA_FALLBACK_LANGUAGE') || 'en-US';

    try {
      const response = await axios.get(`${TMDB_BASE_URL}/search/movie`, {
        params: {
          api_key: apiKey,
          query: title,
          year: year,
          language: prefLang
        }
      });

      if (response.data && response.data.results && response.data.results.length > 0) {
        let match = response.data.results[0];
        
        // Intelligent selection: Prioritize exact year matches and popular releases to avoid matching obscure documentaries
        if (year) {
          const exactYearMatches = response.data.results.filter((m: any) => {
            const relYear = m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null;
            return relYear === year;
          });
          if (exactYearMatches.length > 0) {
            match = exactYearMatches.reduce((prev: any, current: any) => 
              ((prev.popularity || 0) > (current.popularity || 0)) ? prev : current
            );
          } else {
            const closeYearMatches = response.data.results.filter((m: any) => {
              const relYear = m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null;
              return relYear && Math.abs(relYear - year) <= 1;
            });
            if (closeYearMatches.length > 0) {
              match = closeYearMatches.reduce((prev: any, current: any) => 
                ((prev.popularity || 0) > (current.popularity || 0)) ? prev : current
              );
            }
          }
        } else {
          // If no year is specified, select the candidate with the highest popularity to avoid obscure releases
          match = response.data.results.reduce((prev: any, current: any) => 
            ((prev.popularity || 0) > (current.popularity || 0)) ? prev : current
          );
        }
        
        try {
          // Fetch full details with preferred language including watch providers, credits, and videos
          const detailResponse = await axios.get(`${TMDB_BASE_URL}/movie/${match.id}`, {
            params: {
              api_key: apiKey,
              language: prefLang,
              append_to_response: 'credits,watch/providers,videos,keywords,similar,external_ids'
            }
          });
          
          let movieData = detailResponse.data;

          // If overview is missing or incomplete, query the fallback language
          if ((!movieData.overview || movieData.overview.trim() === '') && prefLang !== fallbackLang) {
            try {
              const fallbackResponse = await axios.get(`${TMDB_BASE_URL}/movie/${match.id}`, {
                params: {
                  api_key: apiKey,
                  language: fallbackLang,
                  append_to_response: 'credits,watch/providers,videos,keywords,similar,external_ids'
                }
              });
              if (fallbackResponse.data && fallbackResponse.data.overview) {
                movieData.overview = fallbackResponse.data.overview;
                if ((!movieData.tagline || movieData.tagline.trim() === '') && fallbackResponse.data.tagline) {
                  movieData.tagline = fallbackResponse.data.tagline;
                }
                if ((!movieData.credits || !movieData.credits.cast || movieData.credits.cast.length === 0) && fallbackResponse.data.credits) {
                  movieData.credits = fallbackResponse.data.credits;
                }
                if ((!movieData.videos || !movieData.videos.results || fallbackResponse.data.videos.results.length > 0) && fallbackResponse.data.videos) {
                  movieData.videos = fallbackResponse.data.videos;
                }
                if ((!movieData.keywords || !movieData.keywords.keywords || movieData.keywords.keywords.length === 0) && fallbackResponse.data.keywords) {
                  movieData.keywords = fallbackResponse.data.keywords;
                }
              }
            } catch (fallbackErr) {
              console.error(`[TMDB] Fallback language query failed for movie ID ${match.id}:`, fallbackErr);
            }
          }

          return movieData;
        } catch (detailErr) {
          console.error(`[TMDB] Failed to fetch full details for movie ID ${match.id}:`, detailErr);
          return match;
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
      poster_path: null,
      backdrop_path: null,
      vote_average: 0.0,
      credits: { cast: [], crew: [] }
    };
  }

  /**
   * Search candidate movies from TMDB (returns all candidate matches)
   */
  public async searchMovieCandidates(title: string, year?: number): Promise<any[]> {
    const apiKey = this.getApiKey();
    if (!apiKey) return [];

    const prefLang = this.getSetting('METADATA_LANGUAGE') || 'sv-SE';
    try {
      const response = await axios.get(`${TMDB_BASE_URL}/search/movie`, {
        params: {
          api_key: apiKey,
          query: title,
          year: year,
          language: prefLang
        }
      });
      return response.data?.results || [];
    } catch (e) {
      console.error(`[TMDB] Failed to search candidates for ${title}:`, e);
      return [];
    }
  }

  /**
   * Fetch full movie details directly by TMDB ID
   */
  public async fetchMovieById(id: string): Promise<any> {
    const apiKey = this.getApiKey();
    if (!apiKey) return null;

    const prefLang = this.getSetting('METADATA_LANGUAGE') || 'sv-SE';
    const fallbackLang = this.getSetting('METADATA_FALLBACK_LANGUAGE') || 'en-US';

    try {
      const detailResponse = await axios.get(`${TMDB_BASE_URL}/movie/${id}`, {
        params: {
          api_key: apiKey,
          language: prefLang,
          append_to_response: 'credits,watch/providers,videos,keywords,similar,external_ids'
        }
      });
      
      let movieData = detailResponse.data;

      if ((!movieData.overview || movieData.overview.trim() === '') && prefLang !== fallbackLang) {
        try {
          const fallbackResponse = await axios.get(`${TMDB_BASE_URL}/movie/${id}`, {
            params: {
              api_key: apiKey,
              language: fallbackLang,
              append_to_response: 'credits,watch/providers,videos,keywords,similar,external_ids'
            }
          });
          if (fallbackResponse.data && fallbackResponse.data.overview) {
            movieData.overview = fallbackResponse.data.overview;
            if ((!movieData.tagline || movieData.tagline.trim() === '') && fallbackResponse.data.tagline) {
              movieData.tagline = fallbackResponse.data.tagline;
            }
            if ((!movieData.credits || !movieData.credits.cast || movieData.credits.cast.length === 0) && fallbackResponse.data.credits) {
              movieData.credits = fallbackResponse.data.credits;
            }
            if ((!movieData.videos || !movieData.videos.results || fallbackResponse.data.videos.results.length > 0) && fallbackResponse.data.videos) {
              movieData.videos = fallbackResponse.data.videos;
            }
            if ((!movieData.keywords || !movieData.keywords.keywords || movieData.keywords.keywords.length === 0) && fallbackResponse.data.keywords) {
              movieData.keywords = fallbackResponse.data.keywords;
            }
          }
        } catch (fallbackErr) {
          console.error(`[TMDB] Fallback language query failed for movie ID ${id}:`, fallbackErr);
        }
      }

      return movieData;
    } catch (e) {
      console.error(`[TMDB] Failed to fetch movie by ID ${id}:`, e);
      return null;
    }
  }

  /**
   * Fetch a compact awards summary from the public TMDB movie awards page.
   * The TMDB API does not return awards, but the movie page exposes a summary.
   */
  public async fetchAwardsSummary(id: string): Promise<string | null> {
    try {
      const response = await axios.get(`https://www.themoviedb.org/movie/${id}/awards`, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        }
      });

      const html = typeof response.data === 'string' ? response.data : '';
      if (!html) return null;

      const nominationMatch = html.match(/\b(\d+)\s+Nominations?\b/i);
      const winsMatch = html.match(/\b(\d+)\s+Wins?\b/i);

      const nominations = nominationMatch ? Number(nominationMatch[1]) : 0;
      const wins = winsMatch ? Number(winsMatch[1]) : 0;

      if (!wins && !nominations) return null;
      if (wins && nominations) {
        return `${wins} Win${wins === 1 ? '' : 's'} & ${nominations} Nomination${nominations === 1 ? '' : 's'}`;
      }
      if (wins) return `${wins} Win${wins === 1 ? '' : 's'}`;
      return `${nominations} Nomination${nominations === 1 ? '' : 's'}`;
    } catch {
      return null;
    }
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
