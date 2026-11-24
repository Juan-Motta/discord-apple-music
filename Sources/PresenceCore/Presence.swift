import Foundation

public enum ActivityType {
    public static let listening = 2
}

/// Discord Rich Presence activity, encoded with Discord's field names.
public struct Activity: Codable, Equatable, Sendable {
    public struct Timestamps: Codable, Equatable, Sendable {
        /// Unix epoch milliseconds.
        public var start: Int64
        public var end: Int64
    }

    public struct Assets: Codable, Equatable, Sendable {
        public var largeImage: String?
        public var largeText: String?
        public var largeURL: String?

        enum CodingKeys: String, CodingKey {
            case largeImage = "large_image", largeText = "large_text", largeURL = "large_url"
        }
    }

    public struct Button: Codable, Equatable, Sendable {
        public var label: String
        public var url: String
    }

    public var type: Int
    public var statusDisplayType: Int
    public var details: String
    public var state: String
    /// Clickable title / artist; unlike buttons, the owner sees these too.
    public var detailsURL: String?
    public var stateURL: String?
    public var timestamps: Timestamps?
    public var assets: Assets?
    /// Other people see buttons; Discord never shows your own buttons to you.
    public var buttons: [Button]?

    enum CodingKeys: String, CodingKey {
        case type, details, state, timestamps, assets, buttons
        case statusDisplayType = "status_display_type"
        case detailsURL = "details_url"
        case stateURL = "state_url"
    }
}

private let maxText = 128
private let minText = 2
/// Position drift beyond this means the user seeked, so the progress bar must be re-sent.
let seekToleranceMs: Int64 = 3_000

/// Discord rejects text fields shorter than 2 or longer than 128 characters.
public func fitText(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count > maxText { return String(trimmed.prefix(maxText - 1)) + "…" }
    return trimmed.count < minText ? trimmed.padding(toLength: minText, withPad: " ", startingAt: 0) : trimmed
}

public func makeActivity(_ snapshot: PlaybackSnapshot, artwork: Artwork?, now: Date, settings: Settings) -> Activity? {
    guard case let .playing(track, position) = snapshot else { return nil }

    let statusDisplayType = switch settings.statusDisplay {
    case .artist: 1
    case .song, .songAndArtist: 2
    }

    let title = track.title.isEmpty ? "Unknown track" : track.title
    let artist = track.artist.isEmpty ? "Unknown artist" : track.artist
    let combined = settings.statusDisplay == .songAndArtist
    let albumOnSecondLine = combined && !track.album.isEmpty

    var activity = Activity(
        type: ActivityType.listening,
        statusDisplayType: statusDisplayType,
        details: fitText(combined ? "\(title) – \(artist)" : title),
        state: fitText(albumOnSecondLine ? track.album : artist)
    )

    if track.duration > 0 {
        let start = Int64(((now.timeIntervalSince1970 - position) * 1000).rounded())
        activity.timestamps = .init(start: start, end: start + Int64((track.duration * 1000).rounded()))
    }

    guard let artwork else { return activity }

    if settings.showCoverArt {
        activity.assets = .init(
            largeImage: artwork.imageURL,
            largeText: track.album.isEmpty ? nil : fitText(track.album),
            largeURL: settings.clickableLinks ? artwork.albumURL : nil
        )
    }
    if settings.clickableLinks {
        activity.detailsURL = artwork.trackURL
        activity.stateURL = albumOnSecondLine ? artwork.albumURL : artwork.artistURL
    }
    if settings.showButton, let trackURL = artwork.trackURL {
        activity.buttons = [.init(label: "Listen on Apple Music", url: trackURL)]
    }
    return activity
}

/// Re-publishing on every check would hit Discord's rate limit, so only meaningful changes count.
public func needsUpdate(_ previous: Activity?, _ next: Activity?) -> Bool {
    guard let previous, let next else { return (previous == nil) != (next == nil) }
    var a = previous, b = next
    a.timestamps = nil
    b.timestamps = nil
    if a != b { return true }
    let drift = abs((previous.timestamps?.start ?? 0) - (next.timestamps?.start ?? 0))
    return drift > seekToleranceMs || (previous.timestamps == nil) != (next.timestamps == nil)
}
