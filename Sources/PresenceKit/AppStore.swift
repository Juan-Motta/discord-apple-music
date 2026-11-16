import Foundation
import PresenceCore

/// What the background agent is doing, written for the app window to display.
public struct AgentStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case playing
        case idle
        case discordUnavailable
        case musicAccessDenied
    }

    public var state: State
    public var title: String?
    public var artist: String?
    /// What Discord shows while playing, so the app can preview the card.
    public var album: String?
    public var artworkURL: String?
    public var startedAt: Date?
    public var endsAt: Date?
    public var updatedAt: Date

    public init(
        state: State, title: String? = nil, artist: String? = nil, album: String? = nil,
        artworkURL: String? = nil, startedAt: Date? = nil, endsAt: Date? = nil, updatedAt: Date = Date()
    ) {
        self.state = state
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.updatedAt = updatedAt
    }

    /// The status for an activity being shown in Discord.
    public static func playing(_ activity: Activity) -> AgentStatus {
        let date = { (ms: Int64) in Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
        return AgentStatus(
            state: .playing,
            title: activity.details.trimmingCharacters(in: .whitespaces),
            artist: activity.state.trimmingCharacters(in: .whitespaces),
            album: activity.assets?.largeText,
            artworkURL: activity.assets?.largeImage,
            startedAt: activity.timestamps.map { date($0.start) },
            endsAt: activity.timestamps.map { date($0.end) })
    }
}

/// Settings and status files shared between the app and the agent.
public struct AppStore: Sendable {
    public let directory: URL

    public static let `default` = AppStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Discord Apple Music", isDirectory: true)
    )

    /// Posted by the app after saving settings so the agent reloads them.
    public static let settingsChanged = Notification.Name("dev.discord-apple-music.settingsChanged")
    /// Posted by the agent after writing a new status.
    public static let statusChanged = Notification.Name("dev.discord-apple-music.statusChanged")

    public init(directory: URL) {
        self.directory = directory
    }

    var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    var statusURL: URL { directory.appendingPathComponent("status.json") }

    public func loadSettings() -> Settings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func saveSettings(_ settings: Settings) throws {
        try write(settings, to: settingsURL)
    }

    public func loadStatus() -> AgentStatus? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? Self.decoder.decode(AgentStatus.self, from: data)
    }

    public func saveStatus(_ status: AgentStatus) throws {
        try write(status, to: statusURL)
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
