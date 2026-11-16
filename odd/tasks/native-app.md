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
| T1 | S4 | inline | pending | |
| T2 | S3, S4 | inline | pending | |
| T3 | S3, S5 | inline | pending | |
| T4 | S1, S2, S6 | inline | pending | |
| T5 | S5, S7 | inline | pending | |
| T6 | S7 | inline | pending | |

T1 core logic in Swift + tests · T2 adapters (Music, Discord IPC, iTunes, config/status) · T3 background agent · T4 SwiftUI window + SMAppService · T5 bundle/sign/notarize, test on this Mac · T6 cask, release script, README.

Route: inline (no writer trigger: units are sequential and depend on each other).

## Log

- L1 (2026-11-16) user: "una ultima cosa, al intalar es posible tener una pequena interfaz para configurar, algo asi como tener una miniapp que pueda buscar en applications y pueda ahi prenderlo, apagarlo o configurarlo si quiero despues agregar customizacion?"
- L2 user: "no me gustaria tanto un icono arriba si no una app que se abra y que [ueda buscarla en applications para no llenar de basura la barra superior"
- L3 user: "quiero que sea lo mas liviano posible" → option B (Swift rewrite) chosen; user: "si arranca".
- L4 Environment: Swift 6.4.2 via Command Line Tools, no Xcode; swift-testing works; macOS 27.2 arm64. Engram mirror pending (mem_save blocked by a hook in auto mode).
