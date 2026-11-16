# discord-apple-music

Show what you're playing in **Apple Music** on your Discord profile as **"Listening to Apple Music"**, the same way Spotify does: song, artist, album cover, a live progress bar, and links that open the track in Apple Music.

macOS only. No Discord mods required: it talks to the regular Discord desktop app over its local Rich Presence socket.

## Requirements

- macOS on Apple Silicon, with the Music app
- Discord desktop app, running

## Install with Homebrew

```bash
brew install juan-motta/tap/discord-apple-music
```

```bash
brew services start discord-apple-music
```

`brew services` starts it now and at every login. Use it instead of `discord-apple-music install`, not both, or two copies will run. Logs go to `$(brew --prefix)/var/log/discord-apple-music.log`.

## Install manually (no Node.js needed)

1. Download `discord-apple-music-<version>-macos-arm64.zip` from [Releases](https://github.com/Juan-Motta/discord-apple-music/releases) and unzip it.
2. Move the binary somewhere permanent, then install it as a login item:

```bash
mkdir -p ~/.local/bin && mv ~/Downloads/discord-apple-music ~/.local/bin/
```

```bash
~/.local/bin/discord-apple-music install
```

The binary is signed and notarized by Apple. Other commands: `run` (foreground), `status`, `uninstall`.

The login item points at the binary's location. If you move the binary later, run `install` again.

## Run from source

Requires Node.js 23.6 or newer, which runs the TypeScript sources directly.

```bash
git clone https://github.com/Juan-Motta/discord-apple-music.git
cd discord-apple-music
npm start
```

Play something in Apple Music and check your Discord profile. Press Ctrl+C to stop; the status clears.

### Start automatically at login (from source)

```bash
npm run agent:install     # install and start now
npm run agent:status      # is it running?
npm run agent:uninstall   # remove it
```

This installs a LaunchAgent (`~/Library/LaunchAgents/dev.discord-apple-music.plist`) that starts at login and restarts if it stops. Logs go to `~/Library/Logs/discord-apple-music.log`.

The agent points at this folder and at the Node.js binary that ran the install. If you move the folder or switch Node versions (nvm, fnm), run `npm run agent:install` again.

## Permissions

The first time it reads Apple Music, macOS asks whether `discord-apple-music` (or `node`, when running from source) may control **Music**. Click **Allow**.

If you clicked Don't Allow, nothing shows in Discord and the log says `Not allowed to control Music`. Enable it in **System Settings → Privacy & Security → Automation**, then run `install` again.

## How it behaves

- **Paused or stopped:** the status disappears, like Spotify.
- **Discord closed:** keeps waiting and reconnects when Discord opens.
- **Updates:** checks Music every 5 seconds, but only talks to Discord when the song changes, you pause, you seek, or the cover art arrives.
- **Cover art and links:** looked up through the public iTunes Search API. Songs that aren't in the Apple Music catalog (your own uploads) show without a cover.
- **The "Listen on Apple Music" button:** other people see it on your profile, but Discord never shows your own buttons to you. The song title, artist, and cover are also clickable links, and those you can see.

## Use your own Discord application

By default it uses a shared Discord application named "Apple Music". To use your own name or icon, create an application at <https://discord.com/developers/applications> and set its Application ID:

```bash
DISCORD_CLIENT_ID=<your application id> npm start
```

## Development

```bash
npm test
```

```
src/core/       pure logic: what to show and when to update (no macOS or Discord APIs)
src/adapters/   Apple Music (JXA), Discord IPC, iTunes artwork, LaunchAgent
src/app/run.ts  wires adapters into the sync loop
src/cli.ts      run | install | uninstall | status
```

`src/core` has no platform dependencies, so it can be reused by other front ends, such as a Vencord user plugin.

### Building a release

The release is a [Node.js single executable](https://nodejs.org/api/single-executable-applications.html): the sources bundled with esbuild and embedded into the Node.js binary, then signed with a Developer ID certificate and notarized.

```bash
npm install
npm run build            # test, bundle, build and sign -> dist/*.zip (no notarization)
npm run release          # same, plus Apple notarization
npm run release:publish  # same, then tag, create the GitHub Release and update the Homebrew tap
```

To ship a new version, bump `version` in `package.json`, commit and push to `main`, then run `npm run release:publish`. It refuses to start unless the working tree is clean, `main` matches `origin/main`, and that version has no tag or release yet.

The tap step edits `Formula/discord-apple-music.rb` in [Juan-Motta/homebrew-tap](https://github.com/Juan-Motta/homebrew-tap) through the GitHub API. To preview it without changing anything:

```bash
scripts/update-tap.sh <version> <asset url> <sha256> --dry-run
```

Notarization needs a notarytool keychain profile, created once:

```bash
xcrun notarytool store-credentials discord-apple-music --apple-id <apple id> --team-id <team id>
```

The binary matches the architecture of the Node.js that builds it (`arm64` on Apple Silicon).

## License

MIT
