import { AppleMusicJxaSource } from "../adapters/apple-music-jxa.ts";
import { DiscordIpcPublisher } from "../adapters/discord-ipc.ts";
import { ITunesArtworkResolver } from "../adapters/itunes-artwork.ts";
import { clientId, POLL_INTERVAL_MS } from "../config.ts";
import { PresenceSync } from "../core/sync.ts";
import { log } from "../log.ts";

/** Runs the sync loop until SIGINT/SIGTERM, then clears the presence. */
export function run(): void {
    const publisher = new DiscordIpcPublisher(clientId());
    const sync = new PresenceSync({
        player: new AppleMusicJxaSource(),
        artwork: new ITunesArtworkResolver(),
        publisher,
    });

    publisher.on("disconnect", () => {
        log.warn("[discord] disconnected; will reconnect on next update");
        sync.reset();
    });

    let lastError = "";
    let timer: NodeJS.Timeout;

    async function loop(): Promise<void> {
        try {
            await sync.tick();
            lastError = "";
        } catch (error) {
            const message = (error as Error).message;
            if (message !== lastError) log.warn("[sync]", message); // avoid log spam while Discord is closed
            lastError = message;
            sync.reset();
        }
        timer = setTimeout(loop, POLL_INTERVAL_MS);
    }

    async function shutdown(): Promise<void> {
        clearTimeout(timer);
        await publisher.publish(null).catch(() => {});
        publisher.close();
        process.exit(0);
    }

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
    timer = setTimeout(loop, 0);
    log.info("Apple Music → Discord presence running. Ctrl+C to stop.");
}
