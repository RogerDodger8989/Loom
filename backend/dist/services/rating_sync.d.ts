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
export declare function syncExternalWatchStatus(media: MediaLike, isWatched: boolean): Promise<void>;
export declare function syncExternalRatings(media: MediaLike, rawRating: any): Promise<void>;
export declare function importRatingsFromTrakt(): Promise<number>;
export declare function importRatingsFromSimkl(): Promise<number>;
export declare function importWatchHistoryFromTrakt(): Promise<number>;
export declare function importWatchHistoryFromSimkl(): Promise<number>;
export declare function syncAllExternalData(): Promise<void>;
export {};
