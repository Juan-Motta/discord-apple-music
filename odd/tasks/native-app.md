# Native macOS app (Swift)

Objective: replace the 145 MB Node binary with a lightweight native app found in /Applications, with a window to turn the presence on/off and configure it.
Branch: `feat/native-app`. Delivery: work-unit commits on the branch, merged by the user. Test runner: `swift test` (swift-testing, Command Line Tools, no Xcode).

## Specs

- **S1** "al intalar es posible tener una pequena interfaz para configurar, algo asi como tener una miniapp que pueda buscar en applications y pueda ahi prenderlo, apagarlo o configurarlo si quiero despues agregar customizacion"
- **S2** "no me gustaria tanto un icono arriba si no una app que se abra y que [ueda buscarla en applications para no llenar de basura la barra superior": no menu bar item; a regular windowed app.
- **S3** "quiero que sea lo mas liviano posible": native Swift, no bundled runtime; event-driven instead of fixed polling.
- **S4** Same presence behavior as the TypeScript version: Listening type, title/artist, progress bar, cover art with exact-match lookup (never another song's cover), clickable links, button, clear on pause, reconnect when Discord restarts.
- **S5** Presence keeps working with the window closed and starts at login (background agent registered via SMAppService).
- **S6** Settings persisted so more customization can be added later.
- **S7** Distributed signed + notarized; Homebrew cask installs into /Applications.
- Assumption: the TypeScript code stays in the repo as the base for a future Vencord plugin.

## Tasks

| ID | Specs | Route | Status | Commit |
| --- | --- | --- | --- | --- |
| T1 | S4 | inline | done | 73c7321 |
| T2 | S3, S4 | inline | done | 3314951 |
| T3 | S3, S5 | inline | done | 5424ab6 |
| T4 | S1, S2, S6 | inline | done | 5291401 |
| T5 | S5, S7 | inline | done | 2d16718, 79eb088, 38034f3, b0e7fdf |
| T6 | S7 | inline | done (publish pending user approval) | see log L8 |

T1 core logic in Swift + tests · T2 adapters (Music, Discord IPC, iTunes, config/status) · T3 background agent · T4 SwiftUI window + SMAppService · T5 bundle/sign/notarize, test on this Mac · T6 cask, release script, README.

Route: inline (no writer trigger: units are sequential and depend on each other).

## Log

- L1 (2026-11-16) user: "una ultima cosa, al intalar es posible tener una pequena interfaz para configurar, algo asi como tener una miniapp que pueda buscar en applications y pueda ahi prenderlo, apagarlo o configurarlo si quiero despues agregar customizacion?"
- L2 user: "no me gustaria tanto un icono arriba si no una app que se abra y que [ueda buscarla en applications para no llenar de basura la barra superior"
- L3 user: "quiero que sea lo mas liviano posible" → option B (Swift rewrite) chosen; user: "si arranca".
- L4 Environment: Swift 6.4.2 via Command Line Tools, no Xcode; swift-testing works; macOS 27.2 arm64. Engram mirror pending (mem_save blocked by a hook in auto mode).
- L5 T5 live test: agent got -1743 with no prompt. Cause: macOS attributes the agent's Apple Events to the app (responsible process), which lacked the apple-events entitlement. Fix 79eb088; verified status "playing" and user confirmed: "si ya se ve".
- L6 user (screenshot of several Dock icons): "por que aparecen tantos iconos". Cause: sending Apple Events registers the process as an app, and the agent inherited the main bundle's Foreground type. setActivationPolicy (38034f3) was not enough; b0e7fdf moves the agent into Contents/Library/LoginItems/DiscordAppleMusicAgent.app with LSBackgroundOnly, drops AppKit from the agent, and re-registers the agent once per app version. Verified type BackgroundOnly; user: "Yes, clean".
- L7 Version bumped to 0.2.0. Notarized build accepted, stapled, spctl "Notarized Developer ID".
- L8 T6: release.sh builds the app and uploads both zips; update-tap.sh also updates casks (version line); cask Casks/discord-apple-music.rb written in the tap (sha filled at publish); README documents the app first and the command-line version second.
- L9 user: "no quiero plugin de vencord" → "eliminemos la version de ts". Removed the TypeScript version (src/, test/, Node packaging), moved the Swift package to the repo root, version now in VERSION, release.sh builds only the app, tap formula removed in favor of the cask. Local brew formula uninstalled. 33 Swift tests pass; release.sh --no-notarize builds from the new layout.
- L10 UI iterations: Liquid Glass tabs (Presence/About), live Discord card preview with clickable links, Start at login, Spanish + language picker, report-a-bug link, donate button, green Show in Discord switch. README screenshot docs/screenshot.png. User: "se ve bien finalmente actualiza el readme y publica tambien un screen que sea llamativo".
