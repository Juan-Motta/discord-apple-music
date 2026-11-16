import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { PlaybackSnapshot } from "../core/now-playing.ts";
import type { PlayerSource } from "../core/ports.ts";
import { log } from "../log.ts";

const exec = promisify(execFile);

/** osascript error when the user denied (or never granted) Automation access to Music. */
const NOT_AUTHORIZED = "-1743";

// Checks `running()` first: addressing Music while it is closed would launch it.
// Returns JSON so titles containing newlines or quotes survive the round-trip.
const SCRIPT = `
const music = Application("Music");
let result = { state: "idle" };
if (music.running() && music.playerState() === "playing") {
    const t = music.currentTrack;
    result = {
        state: "playing",
        positionSec: music.playerPosition(),
        track: {
            id: t.persistentID(),
            title: t.name(),
            artist: t.artist(),
            album: t.album(),
            durationSec: t.duration(),
        },
    };
}
JSON.stringify(result);
`;

export class AppleMusicJxaSource implements PlayerSource {
    private warnedNotAuthorized = false;

    async read(): Promise<PlaybackSnapshot> {
        try {
            const { stdout } = await exec("osascript", ["-l", "JavaScript", "-e", SCRIPT], { timeout: 5_000 });
            this.warnedNotAuthorized = false;
            return JSON.parse(stdout) as PlaybackSnapshot;
        } catch (error) {
            const stderr = String((error as { stderr?: string }).stderr ?? "");
            if (stderr.includes(NOT_AUTHORIZED) && !this.warnedNotAuthorized) {
                this.warnedNotAuthorized = true;
                log.error(
                    "[music] Not allowed to control Music. Enable it in System Settings → " +
                        "Privacy & Security → Automation, then restart the agent.",
                );
            }
            // Track metadata can be momentarily unavailable (e.g. while skipping); treat as idle.
            return { state: "idle" };
        }
    }
}
