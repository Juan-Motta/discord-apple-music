// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiscordAppleMusic",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: what to show in Discord and when to update. No macOS or network APIs.
        .target(name: "PresenceCore"),
        // macOS adapters shared by the app and the background agent.
        .target(name: "PresenceKit", dependencies: ["PresenceCore"]),
        // Headless process that keeps the presence in sync; registered as a login item.
        // Packaged by build-app.sh as a helper bundle (Bundle/AgentInfo.plist) inside the app.
        .executableTarget(name: "DiscordAppleMusicAgent", dependencies: ["PresenceKit"]),
        // Windowed app to turn the agent on/off and change settings.
        .executableTarget(name: "DiscordAppleMusic", dependencies: ["PresenceKit"]),
        .testTarget(name: "PresenceCoreTests", dependencies: ["PresenceCore"]),
        .testTarget(name: "PresenceKitTests", dependencies: ["PresenceKit"]),
    ]
)
