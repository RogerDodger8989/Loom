type MediaLike = {
    title: string;
    type?: string;
    tmdb_id?: string | null;
    imdb_id?: string | null;
    year?: number | null;
};
export declare function syncExternalRatings(media: MediaLike, rawRating: any): Promise<void>;
export declare function importRatingsFromTrakt(): Promise<void>;
export declare function importRatingsFromSimkl(): Promise<void>;
export {};
