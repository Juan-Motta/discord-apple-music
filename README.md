# Discord Apple Music

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/jualopezmo)

Show what you're playing in **Apple Music** on your Discord profile as **"Listening to Apple Music"**, the same way Spotify does: song, artist, album cover, a live progress bar, and links that open the track in Apple Music.

A small native macOS app (about 3 MB). No Discord mods required: it talks to the regular Discord desktop app over its local Rich Presence socket.

## Requirements

- macOS 14 or later (Apple Silicon or Intel), with the Music app
- Discord desktop app, running

## Install

```bash
brew install --cask juan-motta/tap/discord-apple-music
```

Or download `DiscordAppleMusic-<version>-macos.zip` from [Releases](https://github.com/Juan-Motta/discord-apple-music/releases), unzip it and move **Discord Apple Music** to Applications.

The app is signed and notarized by Apple.

## Use

Open **Discord Apple Music** and turn on **Show in Discord**. It keeps working in the background after you close the window and starts at every login, with no menu bar or Dock icon.

Open the app again to turn it off or change what's shown:

- cover art
- clickable song, artist and album
- the "Listen on Apple Music" button
- what the member list shows next to your name: song, artist or "Apple Music"
- your own Discord application ID

## Permissions

The first time it reads Apple Music, macOS asks whether **Discord Apple Music** may control **Music**. Click **Allow**.

If you clicked Don't Allow, nothing shows in Discord and the app says "Allow access to Music". Click **Open Settings** and turn on Music under Discord Apple Music in **Privacy & Security → Automation**.

## How it behaves

- **Paused or stopped:** the status disappears, like Spotify.
- **Discord closed:** keeps waiting and reconnects when Discord opens.
- **Updates:** reacts to Music's own play, pause and track-change notifications, and checks every 15 seconds for seeks. It only talks to Discord when something changed.
- **Cover art and links:** looked up through the public iTunes Search API. Songs that aren't in the Apple Music catalog (your own uploads) show without a cover.
- **The "Listen on Apple Music" button:** other people see it on your profile, but Discord never shows your own buttons to you. The song title, artist, and cover are also clickable links, and those you can see.

## Use your own Discord application

By default it uses a shared Discord application named "Apple Music". To use your own name or icon, create an application at <https://discord.com/developers/applications> and paste its Application ID into the app, under **Advanced**.

## Uninstall

```bash
brew uninstall --cask discord-apple-music
```

If you installed it by hand, turn off **Show in Discord** first, then move the app to the Trash.

## Development

A Swift package, built with the Xcode Command Line Tools (no Xcode project needed):

```
Sources/PresenceCore/             pure logic: what to show and when to update (no macOS APIs)
Sources/PresenceKit/              Apple Music (AppleScript), Discord IPC, iTunes artwork, settings
Sources/DiscordAppleMusicAgent/   background agent, packaged as a helper app inside the app
Sources/DiscordAppleMusic/        the SwiftUI window
Bundle/                           Info.plists, launchd plist, entitlements, icon
```

```bash
swift test
```

```bash
scripts/build-app.sh --no-notarize   # universal, signed app -> dist/
```

### Releasing

```bash
scripts/release.sh               # test, build, sign and notarize -> dist/*.zip
scripts/release.sh --publish     # same, then tag, create the GitHub Release and update the Homebrew cask
```

To ship a new version, bump `VERSION`, commit and push to `main`, then run `scripts/release.sh --publish`. It refuses to start unless the working tree is clean, `main` matches `origin/main`, and that version has no tag or release yet.

The tap step edits `Casks/discord-apple-music.rb` in [Juan-Motta/homebrew-tap](https://github.com/Juan-Motta/homebrew-tap) through the GitHub API. To preview it without changing anything:

```bash
scripts/update-tap.sh <version> <asset url> <sha256> --dry-run
```

Notarization needs a notarytool keychain profile, created once:

```bash
xcrun notarytool store-credentials discord-apple-music --apple-id <apple id> --team-id <team id>
```

## Support

If you enjoy it, you can [buy me a coffee](https://buymeacoffee.com/jualopezmo). There's also a button at the bottom of the app.

## License

MIT
