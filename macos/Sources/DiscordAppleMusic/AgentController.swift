import AppKit
import Observation
import PresenceCore
import PresenceKit
import ServiceManagement

/// State behind the window: whether the background agent is on, what it reports, and settings.
@MainActor
@Observable
final class AgentController {
    /// Must match the plist shipped in Contents/Library/LaunchAgents.
    static let agentPlist = "dev.discord-apple-music.agent.plist"

    private let store = AppStore.default
    private let service = SMAppService.agent(plistName: agentPlist)

    private(set) var serviceStatus: SMAppService.Status = .notRegistered
    private(set) var agentStatus: AgentStatus?
    private(set) var lastError: String?

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            do {
                try store.saveSettings(settings)
                DistributedNotificationCenter.default().postNotificationName(
                    AppStore.settingsChanged, object: nil, deliverImmediately: true)
            } catch {
                lastError = "Could not save settings: \(error.localizedDescription)"
            }
        }
    }

    init() {
        settings = store.loadSettings()
        refresh()
        DistributedNotificationCenter.default().addObserver(
            forName: AppStore.statusChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var isOn: Bool { serviceStatus == .enabled }

    func refresh() {
        serviceStatus = service.status
        agentStatus = store.loadStatus()
    }

    /// Registering starts the agent now and at every login; unregistering stops it.
    func setOn(_ on: Bool) {
        lastError = nil
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}
