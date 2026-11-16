import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { connect, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { PresencePublisher } from "../core/ports.ts";
import type { Activity } from "../core/presence.ts";
import { log } from "../log.ts";

const OP_HANDSHAKE = 0;
const OP_FRAME = 1;
const OP_CLOSE = 2;
const MAX_PIPES = 10;

/**
 * Discord creates its socket in the per-user temp dir. Processes started by launchd may not
 * inherit TMPDIR, and Node would then fall back to /tmp, so ask the OS directly.
 */
function socketDir(): string {
    if (process.env.TMPDIR) return process.env.TMPDIR;
    try {
        return execFileSync("getconf", ["DARWIN_USER_TEMP_DIR"], { encoding: "utf8" }).trim();
    } catch {
        return tmpdir();
    }
}

function encode(op: number, payload: unknown): Buffer {
    const json = Buffer.from(JSON.stringify(payload), "utf8");
    const header = Buffer.alloc(8);
    header.writeInt32LE(op, 0);
    header.writeInt32LE(json.length, 4);
    return Buffer.concat([header, json]);
}

/**
 * Talks to the local Discord client over its IPC unix socket.
 * Emits "disconnect" when the connection drops so callers can re-publish later.
 */
export class DiscordIpcPublisher extends EventEmitter implements PresencePublisher {
    private socket: Socket | null = null;
    private connecting: Promise<Socket> | null = null;
    private readonly clientId: string;

    constructor(clientId: string) {
        super();
        this.clientId = clientId;
    }

    async publish(activity: Activity | null): Promise<void> {
        const socket = await this.ensureConnected();
        log.info(activity ? `[discord] ${activity.details} — ${activity.state}` : "[discord] cleared");
        socket.write(encode(OP_FRAME, {
            cmd: "SET_ACTIVITY",
            nonce: randomUUID(),
            // Omitting `activity` clears the presence.
            args: activity ? { pid: process.pid, activity } : { pid: process.pid },
        }));
    }

    close(): void {
        this.socket?.end();
        this.socket = null;
    }

    private ensureConnected(): Promise<Socket> {
        if (this.socket) return Promise.resolve(this.socket);
        this.connecting ??= this.connectAny().finally(() => (this.connecting = null));
        return this.connecting;
    }

    private async connectAny(): Promise<Socket> {
        const dir = socketDir();
        for (let i = 0; i < MAX_PIPES; i++) {
            try {
                return await this.handshake(join(dir, `discord-ipc-${i}`));
            } catch (error) {
                if ((error as Error).message.startsWith("Discord rejected")) throw error;
            }
        }
        throw new Error("Discord is not running (no IPC socket found)");
    }

    private handshake(path: string): Promise<Socket> {
        return new Promise((resolve, reject) => {
            const socket = connect(path);
            let pending = Buffer.alloc(0);
            let ready = false;

            socket.once("connect", () => socket.write(encode(OP_HANDSHAKE, { v: 1, client_id: this.clientId })));
            socket.on("error", err => {
                if (!ready) reject(err);
            });
            socket.on("close", () => {
                if (!ready) return reject(new Error(`IPC closed during handshake on ${path}`));
                this.socket = null;
                this.emit("disconnect");
            });
            socket.on("data", chunk => {
                pending = Buffer.concat([pending, chunk]);
                while (pending.length >= 8) {
                    const length = pending.readInt32LE(4);
                    if (pending.length < 8 + length) return;
                    const op = pending.readInt32LE(0);
                    const data = JSON.parse(pending.subarray(8, 8 + length).toString("utf8"));
                    pending = pending.subarray(8 + length);

                    if (op === OP_CLOSE) {
                        if (!ready) reject(new Error(`Discord rejected the handshake: ${data.message}`));
                        socket.destroy();
                    } else if (data.evt === "READY" && !ready) {
                        ready = true;
                        this.socket = socket;
                        resolve(socket);
                    } else if (data.evt === "ERROR") {
                        log.error("[discord] command failed:", data.data?.message ?? data);
                    }
                }
            });
        });
    }
}
