import { strict as assert } from "node:assert";
import { describe, it } from "node:test";

import { buildPlist } from "../src/adapters/launch-agent.ts";

describe("buildPlist", () => {
    const plist = buildPlist({
        label: "dev.example",
        programArguments: ["/usr/local/bin/node", "/Users/me/R&D <x>/src/cli.ts", "run"],
        logPath: "/Users/me/Library/Logs/example.log",
    });

    it("starts at login and restarts if the process exits", () => {
        assert.match(plist, /<key>RunAtLoad<\/key>\s*<true\/>/);
        assert.match(plist, /<key>KeepAlive<\/key>\s*<true\/>/);
        assert.match(plist, /<key>Label<\/key>\s*<string>dev\.example<\/string>/);
    });

    it("lists every program argument in order, XML-escaped", () => {
        const args = [...plist.matchAll(/<string>([^<]*)<\/string>/g)].map(m => m[1]);
        const start = args.indexOf("/usr/local/bin/node");
        assert.deepEqual(args.slice(start, start + 3), [
            "/usr/local/bin/node",
            "/Users/me/R&amp;D &lt;x&gt;/src/cli.ts",
            "run",
        ]);
    });

    it("sends stdout and stderr to the log file", () => {
        assert.match(plist, /<key>StandardOutPath<\/key>\s*<string>\/Users\/me\/Library\/Logs\/example\.log<\/string>/);
        assert.match(plist, /<key>StandardErrorPath<\/key>\s*<string>\/Users\/me\/Library\/Logs\/example\.log<\/string>/);
    });
});
