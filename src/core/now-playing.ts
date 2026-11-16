export interface Track {
    id: string;
    title: string;
    artist: string;
    album: string;
    durationSec: number;
}

export type PlaybackSnapshot =
    | { state: "playing"; track: Track; positionSec: number }
    | { state: "idle" }; // paused, stopped, or Music not running

export interface Artwork {
    imageUrl: string;
    trackUrl?: string;
    artistUrl?: string;
    albumUrl?: string;
}
