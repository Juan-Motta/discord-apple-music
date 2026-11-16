import type { Artwork, PlaybackSnapshot, Track } from "./now-playing.ts";
import type { Activity } from "./presence.ts";

export interface PlayerSource {
    read(): Promise<PlaybackSnapshot>;
}

export interface ArtworkResolver {
    resolve(track: Track): Promise<Artwork | null>;
}

export interface PresencePublisher {
    publish(activity: Activity | null): Promise<void>;
}
