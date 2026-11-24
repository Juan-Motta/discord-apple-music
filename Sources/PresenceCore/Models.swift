import Foundation

public struct Track: Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds; `0` for streams without a known length.
    public var duration: TimeInterval

    public init(id: String, title: String, artist: String, album: String, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

public enum PlaybackSnapshot: Equatable, Sendable {
    case playing(Track, position: TimeInterval)
    /// Paused, stopped, or Music not running.
    case idle
}

public struct Artwork: Equatable, Sendable {
    public var imageURL: String
    public var trackURL: String?
    public var artistURL: String?
    public var albumURL: String?

    public init(imageURL: String, trackURL: String? = nil, artistURL: String? = nil, albumURL: String? = nil) {
        self.imageURL = imageURL
        self.trackURL = trackURL
        self.artistURL = artistURL
        self.albumURL = albumURL
    }
}

/// User-facing customization. New options get a default so older settings files keep loading.
public struct Settings: Codable, Equatable, Sendable {
    public enum StatusDisplay: String, Codable, CaseIterable, Sendable {
        /// Member list shows the song title.
        case song
        /// Member list shows the artist.
        case artist
        /// Member list shows "Song – Artist". Discord can only show one line of the card there,
        /// so the first line carries both and the second line shows the album instead.
        case songAndArtist
    }

    public var showCoverArt = true
    public var showButton = true
    public var clickableLinks = true
    public var statusDisplay = StatusDisplay.song
    /// Start the presence when you log in. When off, it starts only when you open the app.
    public var startAtLogin = true
    /// Custom Discord application ID; `nil` uses the shared "Apple Music" application.
    public var clientID: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showCoverArt = try c.decodeIfPresent(Bool.self, forKey: .showCoverArt) ?? true
        showButton = try c.decodeIfPresent(Bool.self, forKey: .showButton) ?? true
        clickableLinks = try c.decodeIfPresent(Bool.self, forKey: .clickableLinks) ?? true
        // Decoded by hand so a value this version no longer offers (the old "appName") falls back
        // to the song instead of failing the whole file and resetting every setting.
        statusDisplay = (try? c.decodeIfPresent(String.self, forKey: .statusDisplay))
            .flatMap(StatusDisplay.init(rawValue:)) ?? .song
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? true
        clientID = try c.decodeIfPresent(String.self, forKey: .clientID)
    }
}

public enum DiscordApplication {
    /// Public Discord application named "Apple Music". Not a secret.
    public static let defaultClientID = "1571938418022420505"
}

/// Whether a launch of the agent should do nothing because the user turned off "Start at login".
///
/// launchd starts a registered agent at every login, so the agent itself tells a login launch
/// (shortly after the session began, with no recent request from the app) from one the app asked for.
public func shouldSkipLaunch(
    settings: Settings, now: Date, sessionStart: Date?, lastStartRequest: Date?,
    loginWindow: TimeInterval = 120, requestWindow: TimeInterval = 30
) -> Bool {
    guard !settings.startAtLogin, let sessionStart else { return false }
    if let lastStartRequest, now.timeIntervalSince(lastStartRequest) < requestWindow { return false }
    return now.timeIntervalSince(sessionStart) < loginWindow
}
