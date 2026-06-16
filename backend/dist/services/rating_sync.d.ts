export declare let syncStatus: {
    isSyncing: boolean;
    progress: number;
    currentStep: string;
    lastSyncResult: any;
};
type MediaLike = {
    title: string;
    type?: string;
    tmdb_id?: string | null;
    imdb_id?: string | null;
    year?: number | null;
};
export declare function syncExternalWatchStatus(userId: string, media: MediaLike, isWatched: boolean): Promise<void>;
export declare function syncExternalRatings(userId: string, media: MediaLike, rawRating: any): Promise<void>;
export declare function importRatingsFromTrakt(userId: string): Promise<number>;
export declare function importRatingsFromSimkl(userId: string): Promise<number>;
export declare function importWatchHistoryFromTrakt(userId: string): Promise<number>;
export declare function importWatchHistoryFromSimkl(userId: string): Promise<number>;
export declare function importPlayHistoryFromTrakt(userId: string): Promise<number>;
export declare function syncAllExternalData(): Promise<void>;
export {};
