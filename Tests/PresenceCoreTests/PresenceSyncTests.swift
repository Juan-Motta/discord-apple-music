import Foundation
import Testing

@testable import PresenceCore

private actor FakePlayer: PlayerSource {
    var snapshots: [PlaybackSnapshot]
    init(_ snapshots: [PlaybackSnapshot]) { self.snapshots = snapshots }
    func read() async -> PlaybackSnapshot { snapshots.isEmpty ? .idle : snapshots.removeFirst() }
}

private struct NoArtwork: ArtworkResolver {
    func resolve(_ track: Track) async -> Artwork? { nil }
}

private actor RecordingPublisher: PresencePublisher {
    var published: [Activity?] = []
    func publish(_ activity: Activity?) async throws { published.append(activity) }
}

private final class Clock: @unchecked Sendable {
    var seconds: TimeInterval = 0
    func tick() -> Date { seconds += 1; return Date(timeIntervalSince1970: seconds) }
}

private let track = Track(id: "1", title: "Song", artist: "Artist", album: "Album", duration: 100)

private func makeSync(_ snapshots: [PlaybackSnapshot]) -> (PresenceSync, RecordingPublisher) {
    let publisher = RecordingPublisher()
    let clock = Clock()
    let sync = PresenceSync(player: FakePlayer(snapshots), artwork: NoArtwork(), publisher: publisher, now: clock.tick)
    return (sync, publisher)
}

@Suite struct PresenceSyncBehavior {
    @Test func publishesOncePerChange() async throws {
        let (sync, publisher) = makeSync([
            .playing(track, position: 1), .playing(track, position: 2), .idle, .idle,
        ])
        for _ in 0..<4 { try await sync.tick(settings: Settings()) }
        let published = await publisher.published
        #expect(published.count == 2)
        #expect(published.first??.details == "Song")
        #expect(published.last! == nil)
    }

    @Test func initialIdleIsNotPublished() async throws {
        let (sync, publisher) = makeSync([.idle])
        try await sync.tick(settings: Settings())
        #expect(await publisher.published.isEmpty)
    }

    @Test func resetForcesRepublish() async throws {
        let (sync, publisher) = makeSync([.playing(track, position: 1), .playing(track, position: 2)])
        try await sync.tick(settings: Settings())
        await sync.reset()
        try await sync.tick(settings: Settings())
        #expect(await publisher.published.count == 2)
    }

    @Test func reportsWhatIsShowing() async throws {
        let (sync, _) = makeSync([.playing(track, position: 1)])
        try await sync.tick(settings: Settings())
        #expect(await sync.current?.details == "Song")
    }
}
