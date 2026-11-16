import Foundation
import SwiftUI

/// The app's language: the system's, or a fixed one chosen in About.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"

    var id: Self { self }

    var label: Text {
        switch self {
        case .system: Text("System")
        // Each language is named in itself, as in macOS.
        case .english: Text(verbatim: "English")
        case .spanish: Text(verbatim: "Español")
        }
    }

    /// The choice stored for this app only (not the system-wide preference).
    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        let first = (domain?["AppleLanguages"] as? [String])?.first
        return allCases.first { $0 != .system && first?.hasPrefix($0.rawValue) == true } ?? .system
    }

    /// macOS picks the language when the app launches, so applying it relaunches the app.
    @MainActor
    static func apply(_ language: AppLanguage) {
        guard language != current else { return }
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        AppInstaller.relaunch()
    }
}
