import Foundation
import Testing

@testable import PresenceCore
@testable import PresenceKit

@Suite struct DiscordFrames {
    @Test func encodesOpcodeLengthAndJSON() throws {
        let frame = DiscordFrame.encode(opcode: 1, payload: Data(#"{"a":1}"#.utf8))
        #expect(Array(frame.prefix(8)) == [1, 0, 0, 0, 7, 0, 0, 0])
        #expect(String(decoding: frame.dropFirst(8), as: UTF8.self) == #"{"a":1}"#)
    }

    @Test func decodesFramesSplitAcrossReads() {
        let one = DiscordFrame.encode(opcode: 1, payload: Data(#"{"evt":"READY"}"#.utf8))
        let two = DiscordFrame.encode(opcode: 2, payload: Data(#"{"code":4000}"#.utf8))
        var buffer = DiscordFrameBuffer()
        let all = one + two
        var frames: [DiscordFrame] = []
        frames += buffer.append(all.prefix(5))
        #expect(frames.isEmpty)
        frames += buffer.append(all.dropFirst(5).prefix(20))
        frames += buffer.append(all.dropFirst(25))
        #expect(frames.map(\.opcode) == [1, 2])
        #expect(String(decoding: frames[1].payload, as: UTF8.self) == #"{"code":4000}"#)
    }
}

@Suite struct AppleScriptOutput {
    let sep = AppleMusicSource.separator

    @Test func idleWhenEmpty() {
        #expect(AppleMusicSource.parse("") == .idle)
    }

    @Test func parsesTrackWithMillisecondNumbers() {
        let raw = ["1C60FE", "Still Action!", "Sān-Z & HOYO-MiX", "极限委托", "208547", "21155"].joined(separator: sep)
        #expect(AppleMusicSource.parse(raw) == .playing(
            Track(id: "1C60FE", title: "Still Action!", artist: "Sān-Z & HOYO-MiX", album: "极限委托", duration: 208.547),
            position: 21.155))
    }

    @Test func keepsNewlinesInsideTitles() {
        let raw = ["X", "Line 1\nLine 2", "A", "B", "1000", "0"].joined(separator: sep)
        guard case let .playing(track, _) = AppleMusicSource.parse(raw) else { Issue.record("not playing"); return }
        #expect(track.title == "Line 1\nLine 2")
    }

    @Test func malformedOutputIsIdle() {
        #expect(AppleMusicSource.parse("only one field") == .idle)
    }
}

@Suite struct SettingsStorage {
    func tempStore() -> AppStore {
        AppStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func missingFileGivesDefaults() {
        #expect(tempStore().loadSettings() == Settings())
    }

    @Test func roundTripsSettings() throws {
        let store = tempStore()
        var settings = Settings()
        settings.showButton = false
        settings.statusDisplay = .artist
        try store.saveSettings(settings)
        #expect(store.loadSettings() == settings)
    }

    @Test func unknownAndMissingKeysFallBackToDefaults() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"showButton":false,"futureOption":42}"#.utf8).write(to: store.settingsURL)
        var expected = Settings()
        expected.showButton = false
        #expect(store.loadSettings() == expected)
    }

    @Test func corruptFileGivesDefaults() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.settingsURL)
        #expect(store.loadSettings() == Settings())
    }

    @Test func roundTripsStatus() throws {
        let store = tempStore()
        let status = AgentStatus(state: .playing, title: "Song", artist: "Artist", updatedAt: Date(timeIntervalSince1970: 5))
        try store.saveStatus(status)
        #expect(store.loadStatus() == status)
    }
}

@Suite struct StatusForTheApp {
    @Test func playingStatusCarriesWhatDiscordShows() throws {
        let track = Track(id: "A", title: "Song", artist: "Artist", album: "Album", duration: 200)
        let artwork = Artwork(imageURL: "https://img/x.jpg", trackURL: nil, artistURL: nil, albumURL: nil)
        let activity = try #require(makeActivity(
            .playing(track, position: 30), artwork: artwork, now: Date(timeIntervalSince1970: 1_000), settings: Settings()))
        let status = AgentStatus.playing(activity)
        #expect(status.state == .playing)
        #expect(status.title == "Song")
        #expect(status.artist == "Artist")
        #expect(status.album == "Album")
        #expect(status.artworkURL == "https://img/x.jpg")
        #expect(status.startedAt == Date(timeIntervalSince1970: 970))
        #expect(status.endsAt == Date(timeIntervalSince1970: 1_170))
    }

    @Test func readsStatusFilesWrittenBeforeTheseFields() throws {
        let old = Data(#"{"state":"playing","title":"Song","artist":"Artist","updatedAt":0}"#.utf8)
        let status = try JSONDecoder().decode(AgentStatus.self, from: old)
        #expect(status.title == "Song")
        #expect(status.artworkURL == nil)
    }
}
