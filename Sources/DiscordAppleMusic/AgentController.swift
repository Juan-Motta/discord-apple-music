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
    /// The `Label` inside that plist.
    static let agentLabel = "dev.discord-apple-music.agent"

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
                lastError = String(localized: "Could not save settings: \(error.localizedDescription)")
            }
        }
    }

    init() {
        settings = store.loadSettings()
        refresh()
        Task {
            await reregisterAfterUpdate()
            startIfStopped()
        }
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
                store.requestStart()
                try service.register()
                UserDefaults.standard.set(
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion"), forKey: "registeredAgentVersion")
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// launchd keeps the agent definition from the version that registered it, so after an
    /// update it could point at an outdated layout. Re-registering once per version refreshes it.
    private func reregisterAfterUpdate() async {
        let key = "registeredAgentVersion"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard isOn, UserDefaults.standard.string(forKey: key) != version else { return }
        do {
            try await service.unregister()
            store.requestStart()
            try service.register()
            UserDefaults.standard.set(version, forKey: key)
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// With "Start at login" off the agent skips the login launch, so opening the app starts it.
    /// Does nothing if it is already running.
    private func startIfStopped() {
        guard isOn else { return }
        store.requestStart()
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["kickstart", "gui/\(getuid())/\(Self.agentLabel)"]
        try? launchctl.run()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}
