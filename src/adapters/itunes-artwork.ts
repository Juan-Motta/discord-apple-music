import type { Artwork, Track } from "../core/now-playing.ts";
import type { ArtworkResolver } from "../core/ports.ts";

interface ITunesResult {
    collectionName?: string;
    artistName?: string;
    artworkUrl100?: string;
    trackViewUrl?: string;
    artistViewUrl?: string;
    collectionViewUrl?: string;
}

/** iTunes appends affiliate tracking (`uo=4`); drop it so links stay clean. */
function cleanUrl(url: string | undefined, ...extraParams: string[]): string | undefined {
    if (!url) return undefined;
    const parsed = new URL(url);
    for (const param of ["uo", ...extraParams]) parsed.searchParams.delete(param);
    return parsed.toString();
}

const CACHE_LIMIT = 200;

/** Looks up cover art through the public iTunes Search API; local tracks have no public URL. */
export class ITunesArtworkResolver implements ArtworkResolver {
    private readonly cache = new Map<string, Artwork | null>();

    async resolve(track: Track): Promise<Artwork | null> {
        if (this.cache.has(track.id)) return this.cache.get(track.id) ?? null;

        let artwork: Artwork | null;
        try {
            artwork = await this.lookup(track);
        } catch {
            return null; // network failure: retry on the next tick instead of caching the miss
        }
        if (this.cache.size >= CACHE_LIMIT) this.cache.delete(this.cache.keys().next().value!);
        this.cache.set(track.id, artwork);
        return artwork;
    }

    private async lookup(track: Track): Promise<Artwork | null> {
        const url = new URL("https://itunes.apple.com/search");
        url.searchParams.set("term", `${track.title} ${track.artist}`);
        url.searchParams.set("media", "music");
        url.searchParams.set("entity", "song");
        url.searchParams.set("limit", "10");

        const response = await fetch(url, { signal: AbortSignal.timeout(5_000) });
        if (!response.ok) throw new Error(`iTunes search failed: ${response.status}`);
        const { results = [] } = (await response.json()) as { results?: ITunesResult[] };

        const match = results.find(r => r.collectionName === track.album && r.artistName === track.artist)
            ?? results.find(r => r.collectionName === track.album)
            ?? results[0];
        if (!match?.artworkUrl100) return null;

        return {
            imageUrl: match.artworkUrl100.replace("100x100", "512x512"),
            trackUrl: cleanUrl(match.trackViewUrl),
            artistUrl: cleanUrl(match.artistViewUrl),
            // collectionViewUrl carries `i=<trackId>`, which would open the song instead of the album.
            albumUrl: cleanUrl(match.collectionViewUrl, "i"),
        };
    }
}
