import { strict as assert } from "node:assert";
import { describe, it } from "node:test";

import { type ITunesResult, type ITunesSearch, ITunesArtworkResolver } from "../src/adapters/itunes-artwork.ts";
import type { Track } from "../src/core/now-playing.ts";

const track: Track = {
    id: "T1",
    title: "Still Action!",
    artist: "Sān-Z & HOYO-MiX",
    album: "极限委托",
    durationSec: 120,
};

const song = (trackName: string, collectionName: string, art = trackName): ITunesResult => ({
    wrapperType: "track",
    trackName,
    artistName: "Sān-Z & HOYO-MiX",
    collectionName,
    artworkUrl100: `https://img/${art}/100x100bb.jpg`,
    trackViewUrl: `https://music/${trackName}?i=1&uo=4`,
    collectionViewUrl: `https://music/album/${collectionName}?i=1&uo=4`,
});

/** Fake search that answers by entity and records each query. */
function fakeSearch(byEntity: Record<string, ITunesResult[]>) {
    const calls: { term: string; entity: string }[] = [];
    const search: ITunesSearch = async (term, entity) => {
        calls.push({ term, entity });
        return byEntity[entity] ?? [];
    };
    return { search, calls };
}

describe("ITunesArtworkResolver", () => {
    it("never uses an unrelated song by the same artist", async () => {
        const { search } = fakeSearch({ song: [song("Come Alive", "Come Alive - Single")] });
        assert.equal(await new ITunesArtworkResolver(search).resolve(track), null);
    });

    it("picks the result whose title and artist match, not the first one", async () => {
        const { search } = fakeSearch({
            song: [song("Come Alive", "Come Alive - Single"), song("Still Action!", "极限委托", "still")],
        });
        const artwork = await new ITunesArtworkResolver(search).resolve(track);
        assert.equal(artwork?.imageUrl, "https://img/still/512x512bb.jpg");
        assert.equal(artwork?.trackUrl, "https://music/Still%20Action!?i=1");
    });

    it("matches titles ignoring case, accents and punctuation spacing", async () => {
        const { search } = fakeSearch({ song: [song("STILL ACTION !", "极限委托", "still")] });
        const artwork = await new ITunesArtworkResolver(search).resolve({ ...track, artist: "San-Z & HOYO-MiX" });
        assert.equal(artwork?.imageUrl, "https://img/still/512x512bb.jpg");
    });

    it("falls back to the album cover when the song itself is not in the catalog", async () => {
        const album: ITunesResult = {
            wrapperType: "collection",
            artistName: "Sān-Z & HOYO-MiX",
            collectionName: "极限委托",
            artworkUrl100: "https://img/album/100x100bb.jpg",
            collectionViewUrl: "https://music/album/x?uo=4",
        };
        const { search, calls } = fakeSearch({ song: [song("Come Alive", "Come Alive - Single")], album: [album] });
        const artwork = await new ITunesArtworkResolver(search).resolve(track);
        assert.deepEqual(artwork, { imageUrl: "https://img/album/512x512bb.jpg", albumUrl: "https://music/album/x" });
        assert.ok(calls.some(c => c.entity === "album"));
    });

    it("caches misses so a track is looked up only once", async () => {
        const { search, calls } = fakeSearch({});
        const resolver = new ITunesArtworkResolver(search);
        await resolver.resolve(track);
        const afterFirst = calls.length;
        await resolver.resolve(track);
        assert.equal(calls.length, afterFirst);
    });
});
