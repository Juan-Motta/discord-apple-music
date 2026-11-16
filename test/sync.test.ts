import { strict as assert } from "node:assert";
import { describe, it } from "node:test";

import type { PlaybackSnapshot } from "../src/core/now-playing.ts";
import type { Activity } from "../src/core/presence.ts";
import { PresenceSync } from "../src/core/sync.ts";

function setup(snapshots: PlaybackSnapshot[]) {
    const published: (Activity | null)[] = [];
    let clock = 0;
    const sync = new PresenceSync({
        player: { read: async () => snapshots.shift() ?? { state: "idle" } },
        artwork: { resolve: async () => null },
        publisher: { publish: async a => void published.push(a) },
        now: () => (clock += 1_000),
    });
    return { sync, published };
}

const track = { id: "1", title: "Song", artist: "Artist", album: "Album", durationSec: 100 };

describe("PresenceSync", () => {
    it("publishes once per change, not on every tick", async () => {
        const { sync, published } = setup([
            { state: "playing", track, positionSec: 1 },
            { state: "playing", track, positionSec: 2 },
            { state: "idle" },
            { state: "idle" },
        ]);
        for (let i = 0; i < 4; i++) await sync.tick();
        assert.equal(published.length, 2);
        assert.equal(published[0]?.details, "Song");
        assert.equal(published[1], null);
    });

    it("does not publish an initial idle state", async () => {
        const { sync, published } = setup([{ state: "idle" }]);
        await sync.tick();
        assert.equal(published.length, 0);
    });

    it("re-publishes the same activity after reset", async () => {
        const { sync, published } = setup([
            { state: "playing", track, positionSec: 1 },
            { state: "playing", track, positionSec: 2 },
        ]);
        await sync.tick();
        sync.reset();
        await sync.tick();
        assert.equal(published.length, 2);
    });
});
