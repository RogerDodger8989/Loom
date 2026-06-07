export declare class ScannerService {
    /**
     * Scan a specific library path for media files and their NFOs
     */
    scanLibrary(libraryPath: string, type: 'Movie' | 'Show' | 'Music', preferLocalNfo?: boolean): Promise<{
        added: number;
        updated: number;
    }>;
    /**
     * Process a single movie video file
     * Returns 'added', 'updated', or 'skipped'
     */
    processMovieFile(filePath: string, preferLocalNfo?: boolean): Promise<'added' | 'updated' | 'skipped'>;
    /**
     * Parse season+episode numbers from a filename.
     * Supports: S01E01, s1e1, 1x01, Season 1 Episode 1, etc.
     */
    private parseEpisodeNumbers;
    /**
     * Determine the show's root folder relative to the library scan path.
     * Example: libraryPath="C:/Shows", filePath="C:/Shows/Breaking Bad/Season 1/ep.mkv"
     *   → showDir = "C:/Shows/Breaking Bad"
     */
    private getShowDirectory;
    /**
     * Search TMDB for a TV show by title and optional year.
     */
    private searchTVShow;
    /**
     * Process a single TV episode file.
     * Creates/updates the parent show in media_items and the episode in episodes.
     */
    processEpisodeFile(filePath: string, libraryPath: string, preferLocalNfo?: boolean): Promise<'added' | 'updated' | 'skipped'>;
    /**
     * Helper to parse release versions/editions from filename
     */
    private parseEditionFromFilename;
    /**
     * Helper to extract a clean title from a typical piracy filename like "The.Matrix.1999.1080p.mkv"
     */
    private parseTitleFromFilename;
    /**
     * Helper to extract year from filename
     */
    private parseYearFromFilename;
    /**
     * Skip non-primary movie assets (trailers, samples, extras) so they are not imported as standalone films.
     * Optionally also checks user-configured extra skip words.
     */
    private isSupplementalVideo;
    private normalizeRatingValue;
    private normalizeVotesValue;
    private extractSimklId;
    private extractSimklRatings;
    private extractTraktRatings;
    /**
     * Run ffprobe on a video file to detect audio and subtitle tracks.
     * Returns empty arrays if ffprobe is not installed or fails.
     */
    private probeMediaFile;
    /**
     * Extremely simple XML parser to extract basic NFO tags
     */
    private parseNfo;
    /**
     * Recursively get all files in a directory
     */
    private getAllFiles;
}
export declare const mediaScanner: ScannerService;
