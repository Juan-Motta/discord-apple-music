import type { Artwork, Track } from "../core/now-playing.ts";
import type { ArtworkResolver } from "../core/ports.ts";

export interface ITunesResult {
    wrapperType?: string;
    trackName?: string;
    collectionName?: string;
    artistName?: string;
    artworkUrl100?: string;
    trackViewUrl?: string;
    artistViewUrl?: string;
    collectionViewUrl?: string;
}

export type ITunesSearch = (term: string, entity: "song" | "album") => Promise<ITunesResult[]>;

export const searchITunes: ITunesSearch = async (term, entity) => {
    const url = new URL("https://itunes.apple.com/search");
    url.searchParams.set("term", term);
    url.searchParams.set("media", "music");
    url.searchParams.set("entity", entity);
    url.searchParams.set("limit", "25");

    const response = await fetch(url, { signal: AbortSignal.timeout(5_000) });
    if (!response.ok) throw new Error(`iTunes search failed: ${response.status}`);
    const { results = [] } = (await response.json()) as { results?: ITunesResult[] };
    return results;
};

/** iTunes appends affiliate tracking (`uo=4`); drop it so links stay clean. */
function cleanUrl(url: string | undefined, ...extraParams: string[]): string | undefined {
    if (!url) return undefined;
    const parsed = new URL(url);
    for (const param of ["uo", ...extraParams]) parsed.searchParams.delete(param);
    return parsed.toString();
}

/** Case-, accent- and punctuation-insensitive form, so "Sān-Z" matches "San-Z". */
function normalize(value: string | undefined): string {
    return (value ?? "")
        .normalize("NFKD")
        .replace(/\p{M}/gu, "")
        .toLowerCase()
        .replace(/[^\p{L}\p{N}]+/gu, "");
}

/** Catalogs credit artists differently ("A & B" vs "A, B & C"), so compare by the lead artist. */
function sameArtist(a: string | undefined, b: string | undefined): boolean {
    const lead = (v: string | undefined) => normalize((v ?? "").split(/,|&| feat\.| ft\.| x /i)[0]);
    return lead(a) !== "" && lead(a) === lead(b);
}

function toArtwork(result: ITunesResult, withTrack: boolean): Artwork | null {
    if (!result.artworkUrl100) return null;
    const artwork: Artwork = { imageUrl: result.artworkUrl100.replace("100x100", "512x512") };
    const trackUrl = withTrack ? cleanUrl(result.trackViewUrl) : undefined;
    const artistUrl = cleanUrl(result.artistViewUrl);
    // collectionViewUrl carries `i=<trackId>`, which would open the song instead of the album.
    const albumUrl = cleanUrl(result.collectionViewUrl, "i");
    if (trackUrl) artwork.trackUrl = trackUrl;
    if (artistUrl) artwork.artistUrl = artistUrl;
    if (albumUrl) artwork.albumUrl = albumUrl;
    return artwork;
}

const CACHE_LIMIT = 200;

/**
 * Looks up cover art through the public iTunes Search API; local tracks have no public URL.
 * Only exact matches are accepted: showing no cover beats showing another song's cover.
 */
export class ITunesArtworkResolver implements ArtworkResolver {
    private readonly cache = new Map<string, Artwork | null>();
    private readonly search: ITunesSearch;

    constructor(search: ITunesSearch = searchITunes) {
        this.search = search;
    }

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
        const title = normalize(track.title);
        const album = normalize(track.album);
        const isSong = (r: ITunesResult) => normalize(r.trackName) === title && sameArtist(r.artistName, track.artist);

        // The full artist credit sometimes hides the song from search, so also try with the album.
        for (const term of [`${track.title} ${track.artist}`, `${track.title} ${track.album}`]) {
            const results = await this.search(term, "song");
            const match = results.find(r => isSong(r) && normalize(r.collectionName) === album) ?? results.find(isSong);
            if (match) return toArtwork(match, true);
        }

        if (!album) return null;
        const albums = await this.search(`${track.album} ${track.artist}`, "album");
        const match = albums.find(r => normalize(r.collectionName) === album && sameArtist(r.artistName, track.artist));
        return match ? toArtwork(match, false) : null;
    }
}
