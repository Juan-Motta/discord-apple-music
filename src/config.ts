/** Public Discord application ("Apple Music"). Not a secret: anyone can reuse it. */
export const DEFAULT_CLIENT_ID = "1571938418022420505";

export const AGENT_LABEL = "dev.discord-apple-music";

export const POLL_INTERVAL_MS = 5_000;

export function clientId(): string {
    return process.env.DISCORD_CLIENT_ID || DEFAULT_CLIENT_ID;
}
