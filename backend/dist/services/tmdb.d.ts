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
    vote_count?: number;
    trailer_url?: string;
    imdb_id?: string | null;
    external_ids?: {
        imdb_id?: string | null;
    };
    logo_path?: string | null;
    genres?: Array<{
        id: number;
        name: string;
    }>;
    keywords?: {
        keywords?: Array<{
            id: number;
            name: string;
        }>;
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
export declare class TMDBService {
    /**
     * Helper to fetch the TMDB API Key from the database
     */
    private getApiKey;
    /**
     * Helper to fetch any system setting from database
     */
    getSetting(key: string): string;
    setSetting(key: string, value: string): void;
    /**
     * Search TMDB for a movie by title and optionally year
     */
    searchMovie(title: string, year?: number): Promise<Partial<TMDBMovie> | null>;
    /**
     * Generate mock data if TMDB API key is not configured
     */
    private getMockMovie;
    /**
     * Search candidate movies from TMDB (returns all candidate matches)
     */
    searchMovieCandidates(title: string, year?: number): Promise<any[]>;
    /**
     * Fetch full movie details directly by TMDB ID
     */
    fetchMovieById(id: string): Promise<any>;
    /**
     * Fetch full show details directly by TMDB ID
     */
    fetchShowById(id: string): Promise<any>;
    /**
     * Fetch a compact awards summary from the public TMDB movie awards page.
     * The TMDB API does not return awards, but the movie page exposes a summary.
     */
    fetchAwardsSummary(id: string): Promise<string | null>;
    /**
     * Helper to convert a TMDB image path to a full URL
     */
    getImageUrl(path: string | null, size?: 'w500' | 'original'): string | null;
}
export declare const tmdbService: TMDBService;
