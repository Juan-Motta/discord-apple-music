import type { ArtworkResolver, PlayerSource, PresencePublisher } from "./ports.ts";
import { type Activity, needsUpdate, toActivity } from "./presence.ts";

export interface SyncDeps {
    player: PlayerSource;
    artwork: ArtworkResolver;
    publisher: PresencePublisher;
    now?: () => number;
}

/** Reads the player once and publishes the presence only when it changed. */
export class PresenceSync {
    private published: Activity | null = null;
    private readonly deps: SyncDeps;

    constructor(deps: SyncDeps) {
        this.deps = deps;
    }

    async tick(): Promise<void> {
        const { player, artwork, publisher, now = Date.now } = this.deps;
        const snapshot = await player.read();
        const art = snapshot.state === "playing" ? await artwork.resolve(snapshot.track) : null;
        const next = toActivity(snapshot, art, now());

        if (!needsUpdate(this.published, next)) return;
        await publisher.publish(next);
        this.published = next;
    }

    /** Forces the next tick to re-publish, e.g. after Discord reconnects. */
    reset(): void {
        this.published = null;
    }
}
