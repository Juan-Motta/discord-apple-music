import AppKit
import Observation
import PresenceKit

/// The app's version and whether a newer release can be installed.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case installing(AvailableUpdate)
        case failed(String, AvailableUpdate?)
    }

    private(set) var state = State.idle

    let versionText = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private var currentVersion: AppVersion? { AppVersion(versionText) }

    func check() async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        // Development builds have no version to compare against.
        guard let current = currentVersion else { return }
        state = .checking
        do {
            state = try await UpdateFeed.check(current: current).map(State.available) ?? .upToDate
        } catch {
            state = .failed("Couldn't check for updates.", nil)
        }
    }

    func install(_ update: AvailableUpdate) async {
        state = .installing(update)
        do {
            try await AppInstaller.install(update)
            AppInstaller.relaunch()
        } catch {
            state = .failed(error.localizedDescription, update)
        }
    }

    func openReleasePage(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.pageURL)
    }
}
