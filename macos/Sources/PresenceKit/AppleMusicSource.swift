import AppKit
import PresenceCore

public enum MusicAccess: Sendable {
    case granted
    /// The user denied (or has not yet granted) Automation access to Music.
    case denied
}

/// Reads the Music app's player through AppleScript.
public final class AppleMusicSource: PlayerSource, @unchecked Sendable {
    static let separator = "\u{1F}" // ASCII unit separator: never appears in titles
    static let notAuthorized = -1743
    private static let bundleID = "com.apple.Music"

    // Numbers are returned as integer milliseconds: AppleScript formats reals with the
    // system locale ("208,5" in Spanish), which would not parse reliably.
    private static let source = """
        if application "Music" is not running then return ""
        tell application "Music"
            if player state is not playing then return ""
            set t to current track
            set sep to (ASCII character 31)
            set d to 0
            try
                set d to ((duration of t) * 1000) as integer
            end try
            set p to ((player position) * 1000) as integer
            return (persistent ID of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (d as text) & sep & (p as text)
        end tell
        """

    private let script = NSAppleScript(source: source)!
    private let lock = NSLock()
    private var lastAccess = MusicAccess.granted

    public init() {}

    public var access: MusicAccess { lock.withLock { lastAccess } }

    public func read() async -> PlaybackSnapshot {
        // Checking first avoids sending Apple Events (and a permission prompt) while Music is closed.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else {
            return .idle
        }
        return await MainActor.run { self.execute() }
    }

    @MainActor
    private func execute() -> PlaybackSnapshot {
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        let code = error?[NSAppleScript.errorNumber] as? Int
        lock.withLock { lastAccess = code == Self.notAuthorized ? .denied : .granted }
        guard error == nil else { return .idle }
        return Self.parse(result.stringValue ?? "")
    }

    static func parse(_ raw: String) -> PlaybackSnapshot {
        let fields = raw.components(separatedBy: separator)
        guard fields.count == 6, let durationMs = Double(fields[4]), let positionMs = Double(fields[5]) else {
            return .idle
        }
        let track = Track(id: fields[0], title: fields[1], artist: fields[2], album: fields[3], duration: durationMs / 1000)
        return .playing(track, position: positionMs / 1000)
    }

    /// Music posts this whenever playback starts, pauses, stops or the track changes.
    public static let playerInfoNotification = Notification.Name("com.apple.Music.playerInfo")
}
