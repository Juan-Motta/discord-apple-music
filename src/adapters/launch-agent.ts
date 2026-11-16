import { execFile } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);

export interface AgentSpec {
    label: string;
    programArguments: string[];
    logPath: string;
}

const escapeXml = (value: string) =>
    value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function buildPlist({ label, programArguments, logPath }: AgentSpec): string {
    const args = programArguments.map(a => `        <string>${escapeXml(a)}</string>`).join("\n");
    return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${escapeXml(label)}</string>
    <key>ProgramArguments</key>
    <array>
${args}
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>${escapeXml(logPath)}</string>
    <key>StandardErrorPath</key>
    <string>${escapeXml(logPath)}</string>
</dict>
</plist>
`;
}

/** Manages a per-user LaunchAgent so the presence starts at login and restarts on crash. */
export class LaunchAgent {
    private readonly label: string;

    constructor(label: string) {
        this.label = label;
    }

    get plistPath(): string {
        return join(homedir(), "Library", "LaunchAgents", `${this.label}.plist`);
    }

    get logPath(): string {
        return join(homedir(), "Library", "Logs", "discord-apple-music.log");
    }

    private get domain(): string {
        return `gui/${process.getuid!()}`;
    }

    async install(programArguments: string[]): Promise<void> {
        await this.unload(); // reinstalling must replace a running copy, not fail
        await mkdir(join(homedir(), "Library", "LaunchAgents"), { recursive: true });
        await mkdir(join(homedir(), "Library", "Logs"), { recursive: true });
        await writeFile(this.plistPath, buildPlist({ label: this.label, programArguments, logPath: this.logPath }));
        await exec("launchctl", ["bootstrap", this.domain, this.plistPath]);
    }

    async uninstall(): Promise<void> {
        await this.unload();
        await rm(this.plistPath, { force: true });
    }

    /** Returns the running PID, `0` when loaded but not running, or `null` when not installed. */
    async status(): Promise<number | null> {
        try {
            const { stdout } = await exec("launchctl", ["print", `${this.domain}/${this.label}`]);
            return Number(/\bpid = (\d+)/.exec(stdout)?.[1] ?? 0);
        } catch {
            return null;
        }
    }

    private async unload(): Promise<void> {
        await exec("launchctl", ["bootout", `${this.domain}/${this.label}`]).catch(() => {});
    }
}
