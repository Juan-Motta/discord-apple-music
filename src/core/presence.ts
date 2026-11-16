import type { Artwork, PlaybackSnapshot } from "./now-playing.ts";

export const ACTIVITY_TYPE_LISTENING = 2;
export const STATUS_DISPLAY_DETAILS = 2;

const MIN_TEXT = 2;
const MAX_TEXT = 128;
/** Position drift beyond this means the user seeked, so the progress bar must be re-sent. */
export const SEEK_TOLERANCE_MS = 3_000;

export interface Activity {
    type: number;
    status_display_type: number;
    details: string;
    state: string;
    /** Clickable links on the title / artist lines; unlike buttons, the owner sees them too. */
    details_url?: string;
    state_url?: string;
    timestamps?: { start: number; end: number };
    assets?: { large_image?: string; large_text?: string; large_url?: string };
    buttons?: { label: string; url: string }[];
}

/** Discord rejects text fields shorter than 2 or longer than 128 characters. */
export function fitText(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length > MAX_TEXT) return `${trimmed.slice(0, MAX_TEXT - 1)}…`;
    return trimmed.padEnd(MIN_TEXT, " ");
}

export function toActivity(
    snapshot: PlaybackSnapshot,
    artwork: Artwork | null,
    nowMs: number,
): Activity | null {
    if (snapshot.state !== "playing") return null;
    const { track, positionSec } = snapshot;

    const activity: Activity = {
        type: ACTIVITY_TYPE_LISTENING,
        status_display_type: STATUS_DISPLAY_DETAILS,
        details: fitText(track.title || "Unknown track"),
        state: fitText(track.artist || "Unknown artist"),
    };

    if (track.durationSec > 0) {
        const start = Math.round(nowMs - positionSec * 1000);
        activity.timestamps = { start, end: Math.round(start + track.durationSec * 1000) };
    }

    if (artwork) {
        activity.assets = {
            large_image: artwork.imageUrl,
            ...(track.album && { large_text: fitText(track.album) }),
            ...(artwork.albumUrl && { large_url: artwork.albumUrl }),
        };
        if (artwork.trackUrl) activity.details_url = artwork.trackUrl;
        if (artwork.artistUrl) activity.state_url = artwork.artistUrl;
    }
    if (artwork?.trackUrl) {
        activity.buttons = [{ label: "Listen on Apple Music", url: artwork.trackUrl }];
    }

    return activity;
}

/**
 * Decides whether the published activity is stale. Re-publishing on every poll would hit
 * Discord's SET_ACTIVITY rate limit, so only meaningful changes trigger an update.
 */
export function needsUpdate(previous: Activity | null, next: Activity | null): boolean {
    if (previous === null || next === null) return previous !== next;
    if (
        previous.details !== next.details ||
        previous.state !== next.state ||
        previous.assets?.large_image !== next.assets?.large_image
    ) {
        return true;
    }
    const drift = Math.abs((previous.timestamps?.start ?? 0) - (next.timestamps?.start ?? 0));
    return drift > SEEK_TOLERANCE_MS;
}
