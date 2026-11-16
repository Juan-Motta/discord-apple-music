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
        /// Member list shows "Apple Music".
        case appName
    }

    public var showCoverArt = true
    public var showButton = true
    public var clickableLinks = true
    public var statusDisplay = StatusDisplay.song
    /// Custom Discord application ID; `nil` uses the shared "Apple Music" application.
    public var clientID: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showCoverArt = try c.decodeIfPresent(Bool.self, forKey: .showCoverArt) ?? true
        showButton = try c.decodeIfPresent(Bool.self, forKey: .showButton) ?? true
        clickableLinks = try c.decodeIfPresent(Bool.self, forKey: .clickableLinks) ?? true
        statusDisplay = try c.decodeIfPresent(StatusDisplay.self, forKey: .statusDisplay) ?? .song
        clientID = try c.decodeIfPresent(String.self, forKey: .clientID)
    }
}

public enum DiscordApplication {
    /// Public Discord application named "Apple Music". Not a secret.
    public static let defaultClientID = "1571938418022420505"
}
