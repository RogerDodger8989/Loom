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
    private processMovieFile;
    /**
     * Helper to extract a clean title from a typical piracy filename like "The.Matrix.1999.1080p.mkv"
     */
    private parseTitleFromFilename;
    /**
     * Helper to extract year from filename
     */
    private parseYearFromFilename;
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
