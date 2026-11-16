import AppKit
import SwiftUI

@main
struct DiscordAppleMusicApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    // Not @State: SwiftUI's macro plugin ships only with Xcode, and the App is created once anyway.
    private let controller = AgentController()

    var body: some Scene {
        Window("Discord Apple Music", id: "main") {
            ContentView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}

/// A regular app (no menu bar item): closing the window quits it.
/// The presence keeps running because the background agent is a separate process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
