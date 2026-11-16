import Foundation

/// A `major.minor.patch` version, compared numerically ("0.10.0" > "0.9.0").
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    private let parts: [Int]

    /// Accepts "1.2.3", "1.2" or a tag like "v1.2.3".
    public init?(_ string: String) {
        let text = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count) else { return nil }
        let values = numbers.compactMap { $0 }
        guard values.count == numbers.count, values.allSatisfy({ $0 >= 0 }) else { return nil }
        parts = values + Array(repeating: 0, count: 3 - values.count)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// A newer release that ships the app.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: AppVersion
    public let downloadURL: URL
    public let pageURL: URL
}

/// Finds updates in the project's GitHub Releases.
public enum UpdateFeed {
    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/Juan-Motta/discord-apple-music/releases/latest")!

    /// The app archive name a release must carry; matches scripts/release.sh.
    static func archiveName(for version: AppVersion) -> String { "DiscordAppleMusic-\(version)-macos.zip" }

    /// The update described by a GitHub "latest release" response, or nil when that release is
    /// not newer than `current` or does not ship the app.
    public static func update(fromLatestRelease data: Data, current: AppVersion) throws -> AvailableUpdate? {
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let version = AppVersion(release.tag_name), version > current,
              let asset = release.assets.first(where: { $0.name == archiveName(for: version) })
        else { return nil }
        return AvailableUpdate(version: version, downloadURL: asset.browser_download_url, pageURL: release.html_url)
    }

    public static func check(current: AppVersion) async throws -> AvailableUpdate? {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try update(fromLatestRelease: data, current: current)
    }
}
