import Foundation
import PresenceCore
import PresenceKit

/// Keeps the Discord presence in sync with Music.
///
/// Event-driven: Music announces play/pause/track changes, so the agent normally sleeps.
/// A slow timer only catches seeks (Music sends no event for them) and Discord restarts.
@MainActor
final class Agent {
    private static let safetyInterval: TimeInterval = 15

    private let store = AppStore.default
    private let music = AppleMusicSource()
    private let publisher: DiscordIPCPublisher
    private let sync: PresenceSync
    private var settings: Settings
    private var lastStatus: AgentStatus?
    private var running = false
    private var rerun = false

    init() {
        settings = store.loadSettings()
        publisher = DiscordIPCPublisher(clientID: settings.clientID ?? DiscordApplication.defaultClientID)
        sync = PresenceSync(player: music, artwork: ITunesArtworkResolver(), publisher: publisher)
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: AppleMusicSource.playerInfoNotification, object: nil, queue: .main) { _ in
            // Music posts this a moment before its scripting state settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { self.refresh() } }
        }
        center.addObserver(forName: AppStore.settingsChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.reloadSettings() }
        }
        publisher.onDisconnect = { [sync] in
            Task { await sync.reset() }
        }
        Timer.scheduledTimer(withTimeInterval: Self.safetyInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        refresh()
        NSLog("[agent] started")
    }

    private func reloadSettings() {
        settings = store.loadSettings()
        publisher.setClientID(settings.clientID ?? DiscordApplication.defaultClientID)
        Task {
            await sync.reset()
            refresh()
        }
    }

    /// Runs one sync, coalescing triggers that arrive while one is in flight.
    func refresh() {
        guard !running else { rerun = true; return }
        running = true
        Task {
            await runOnce()
            running = false
            if rerun {
                rerun = false
                refresh()
            }
        }
    }

    private func runOnce() async {
        let status: AgentStatus
        do {
            try await sync.tick(settings: settings)
            if music.access == .denied {
                status = AgentStatus(state: .musicAccessDenied)
            } else if let current = await sync.current {
                status = AgentStatus(state: .playing, title: current.details, artist: current.state)
            } else {
                status = AgentStatus(state: .idle)
            }
        } catch {
            await sync.reset()
            status = AgentStatus(state: .discordUnavailable)
        }
        report(status)
    }

    private func report(_ status: AgentStatus) {
        // Compare without the timestamp so an unchanged state doesn't rewrite the file every tick.
        var comparable = status
        comparable.updatedAt = lastStatus?.updatedAt ?? status.updatedAt
        guard comparable != lastStatus else { return }
        lastStatus = status
        try? store.saveStatus(status)
        DistributedNotificationCenter.default().postNotificationName(AppStore.statusChanged, object: nil, deliverImmediately: true)
        NSLog("[agent] %@ %@", status.state.rawValue, status.title ?? "")
    }

    /// Clears the presence before exiting, e.g. when the user turns the app off.
    func stop() async {
        try? await publisher.publish(nil)
        publisher.close()
        report(AgentStatus(state: .idle))
    }
}

let agent = Agent()
agent.start()

signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler {
    _ = MainActor.assumeIsolated {
        Task {
            await agent.stop()
            exit(0)
        }
    }
}
terminate.resume()

// A run loop on the main thread (not dispatchMain) keeps MainActor work, timers and
// NSAppleScript, which must run on the main thread, all on the same thread.
RunLoop.main.run()
