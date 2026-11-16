import { strict as assert } from "node:assert";
import { describe, it } from "node:test";

import type { PlaybackSnapshot } from "../src/core/now-playing.ts";
import { ACTIVITY_TYPE_LISTENING, fitText, needsUpdate, toActivity } from "../src/core/presence.ts";

const NOW = 1_000_000;
const playing: PlaybackSnapshot = {
    state: "playing",
    positionSec: 30,
    track: { id: "A1", title: "Song", artist: "Artist", album: "Album", durationSec: 200 },
};

describe("toActivity", () => {
    it("maps a playing track to a Listening activity with a progress bar", () => {
        const activity = toActivity(playing, null, NOW);
        assert.equal(activity?.type, ACTIVITY_TYPE_LISTENING);
        assert.equal(activity?.details, "Song");
        assert.equal(activity?.state, "Artist");
        assert.deepEqual(activity?.timestamps, { start: NOW - 30_000, end: NOW + 170_000 });
    });

    it("sends no image assets when cover art is unknown", () => {
        assert.equal(toActivity(playing, null, NOW)?.assets, undefined);
    });

    it("clears the presence when nothing is playing", () => {
        assert.equal(toActivity({ state: "idle" }, null, NOW), null);
    });

    it("adds artwork, album tooltip and Apple Music button when artwork is known", () => {
        const activity = toActivity(playing, { imageUrl: "https://img/x.jpg", trackUrl: "https://music/x" }, NOW);
        assert.deepEqual(activity?.assets, {
            large_image: "https://img/x.jpg",
            large_text: "Album",
        });
        assert.deepEqual(activity?.buttons, [{ label: "Listen on Apple Music", url: "https://music/x" }]);
    });

    it("makes title, artist and cover clickable when links are known", () => {
        const activity = toActivity(playing, {
            imageUrl: "https://img/x.jpg",
            trackUrl: "https://music/track",
            artistUrl: "https://music/artist",
            albumUrl: "https://music/album",
        }, NOW);
        assert.equal(activity?.details_url, "https://music/track");
        assert.equal(activity?.state_url, "https://music/artist");
        assert.equal(activity?.assets?.large_url, "https://music/album");
    });

    it("omits link fields when the lookup has no links", () => {
        const activity = toActivity(playing, { imageUrl: "https://img/x.jpg" }, NOW);
        assert.equal("details_url" in activity!, false);
        assert.equal("state_url" in activity!, false);
        assert.equal("large_url" in activity!.assets!, false);
    });

    it("omits timestamps for streams without duration", () => {
        const radio: PlaybackSnapshot = { ...playing, track: { ...playing.track, durationSec: 0 } };
        assert.equal(toActivity(radio, null, NOW)?.timestamps, undefined);
    });
});

describe("fitText", () => {
    it("pads 1-char text and truncates text over 128 chars", () => {
        assert.equal(fitText("X"), "X ");
        const long = fitText("a".repeat(200));
        assert.equal(long.length, 128);
        assert.ok(long.endsWith("…"));
    });
});

describe("needsUpdate", () => {
    const base = toActivity(playing, null, NOW);

    it("ignores the natural clock drift of a continuing track", () => {
        const later = toActivity({ ...playing, positionSec: 35 }, null, NOW + 5_000 + 500);
        assert.equal(needsUpdate(base, later), false);
    });

    it("detects a seek", () => {
        const seeked = toActivity({ ...playing, positionSec: 120 }, null, NOW + 5_000);
        assert.equal(needsUpdate(base, seeked), true);
    });

    it("detects track change, pause and artwork arrival", () => {
        const other = toActivity({ ...playing, track: { ...playing.track, title: "Other" } }, null, NOW);
        assert.equal(needsUpdate(base, other), true);
        assert.equal(needsUpdate(base, null), true);
        assert.equal(needsUpdate(null, null), false);
        assert.equal(needsUpdate(base, toActivity(playing, { imageUrl: "https://img" }, NOW)), true);
    });
});
