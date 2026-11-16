import { isSea } from "node:sea";
import { resolve } from "node:path";

import { LaunchAgent } from "./adapters/launch-agent.ts";
import { run } from "./app/run.ts";
import { AGENT_LABEL } from "./config.ts";

const USAGE = `Usage: discord-apple-music <command>

Commands:
  run        Show Apple Music playback in Discord (foreground)
  install    Start automatically at login (LaunchAgent)
  uninstall  Remove the login item and stop it
  status     Show whether the background agent is running`;

/** How launchd should start this same program: the standalone binary, or node + this script. */
function selfInvocation(): string[] {
    return isSea() ? [process.execPath, "run"] : [process.execPath, resolve(process.argv[1]!), "run"];
}

async function main(command = "run"): Promise<void> {
    const agent = new LaunchAgent(AGENT_LABEL);

    switch (command) {
        case "run":
            run();
            return;
        case "install":
            await agent.install(selfInvocation());
            console.log(`Installed. It now starts at login.\nLogs: ${agent.logPath}`);
            console.log("If macOS asks to allow controlling \"Music\", click Allow.");
            return;
        case "uninstall":
            await agent.uninstall();
            console.log("Uninstalled.");
            return;
        case "status": {
            const pid = await agent.status();
            console.log(pid === null ? "Not installed." : pid ? `Running (pid ${pid}).` : "Installed but not running.");
            console.log(`Logs: ${agent.logPath}`);
            return;
        }
        default:
            console.error(`Unknown command: ${command}\n\n${USAGE}`);
            process.exitCode = 1;
    }
}

const [command] = process.argv.slice(2);
if (command === "-h" || command === "--help" || command === "help") {
    console.log(USAGE);
} else {
    main(command).catch(error => {
        console.error((error as Error).message);
        process.exitCode = 1;
    });
}
