import Foundation

public protocol PlayerSource: Sendable {
    func read() async -> PlaybackSnapshot
}

public protocol ArtworkResolver: Sendable {
    func resolve(_ track: Track) async -> Artwork?
}

public protocol PresencePublisher: Sendable {
    func publish(_ activity: Activity?) async throws
}

/// Reads the player once per tick and publishes the presence only when it changed.
public actor PresenceSync {
    private let player: PlayerSource
    private let artwork: ArtworkResolver
    private let publisher: PresencePublisher
    private let now: @Sendable () -> Date

    /// What Discord is currently showing (as far as this process knows).
    public private(set) var current: Activity?

    public init(
        player: PlayerSource,
        artwork: ArtworkResolver,
        publisher: PresencePublisher,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.player = player
        self.artwork = artwork
        self.publisher = publisher
        self.now = now
    }

    public func tick(settings: Settings) async throws {
        let snapshot = await player.read()
        var art: Artwork?
        if case let .playing(track, _) = snapshot { art = await artwork.resolve(track) }
        let next = makeActivity(snapshot, artwork: art, now: now(), settings: settings)

        guard needsUpdate(current, next) else { return }
        try await publisher.publish(next)
        current = next
    }

    /// Forces the next tick to re-publish, e.g. after Discord reconnects.
    public func reset() {
        current = nil
    }
}
