import Foundation
import Testing

@testable import PresenceCore

private let now = Date(timeIntervalSince1970: 1_000)
private let track = Track(id: "A1", title: "Song", artist: "Artist", album: "Album", duration: 200)
private let playing = PlaybackSnapshot.playing(track, position: 30)
private let artwork = Artwork(
    imageURL: "https://img/x.jpg",
    trackURL: "https://music/track",
    artistURL: "https://music/artist",
    albumURL: "https://music/album"
)

@Suite struct ActivityMapping {
    @Test func playingTrackBecomesListeningActivityWithProgressBar() throws {
        let activity = try #require(makeActivity(playing, artwork: nil, now: now, settings: Settings()))
        #expect(activity.type == ActivityType.listening)
        #expect(activity.details == "Song")
        #expect(activity.state == "Artist")
        #expect(activity.timestamps == Activity.Timestamps(start: 970_000, end: 1_170_000))
        #expect(activity.assets == nil)
    }

    @Test func idleClearsThePresence() {
        #expect(makeActivity(.idle, artwork: nil, now: now, settings: Settings()) == nil)
    }

    @Test func artworkAddsCoverLinksAndButton() throws {
        let activity = try #require(makeActivity(playing, artwork: artwork, now: now, settings: Settings()))
        #expect(activity.assets == Activity.Assets(largeImage: "https://img/x.jpg", largeText: "Album", largeURL: "https://music/album"))
        #expect(activity.detailsURL == "https://music/track")
        #expect(activity.stateURL == "https://music/artist")
        #expect(activity.buttons == [Activity.Button(label: "Listen on Apple Music", url: "https://music/track")])
    }

    @Test func streamsWithoutDurationHaveNoProgressBar() throws {
        let radio = PlaybackSnapshot.playing(Track(id: "R", title: "Radio", artist: "DJ", album: "", duration: 0), position: 5)
        #expect(try #require(makeActivity(radio, artwork: nil, now: now, settings: Settings())).timestamps == nil)
    }

    @Test func settingsCanHideCoverButtonAndLinks() throws {
        var settings = Settings()
        settings.showCoverArt = false
        settings.showButton = false
        settings.clickableLinks = false
        let activity = try #require(makeActivity(playing, artwork: artwork, now: now, settings: settings))
        #expect(activity.assets == nil)
        #expect(activity.buttons == nil)
        #expect(activity.detailsURL == nil)
        #expect(activity.stateURL == nil)
    }

    @Test func statusDisplaySettingPicksWhatTheMemberListShows() throws {
        var settings = Settings()
        #expect(try #require(makeActivity(playing, artwork: nil, now: now, settings: settings)).statusDisplayType == 2)
        settings.statusDisplay = .artist
        #expect(try #require(makeActivity(playing, artwork: nil, now: now, settings: settings)).statusDisplayType == 1)
        settings.statusDisplay = .appName
        #expect(try #require(makeActivity(playing, artwork: nil, now: now, settings: settings)).statusDisplayType == 0)
    }

    @Test func encodesDiscordFieldNames() throws {
        let activity = try #require(makeActivity(playing, artwork: artwork, now: now, settings: Settings()))
        let json = String(decoding: try JSONEncoder().encode(activity), as: UTF8.self)
        for key in ["\"status_display_type\"", "\"details_url\"", "\"state_url\"", "\"large_image\"", "\"large_url\""] {
            #expect(json.contains(key), "missing \(key)")
        }
    }
}

@Suite struct TextFitting {
    @Test func padsShortAndTruncatesLongText() {
        #expect(fitText("X") == "X ")
        let long = fitText(String(repeating: "a", count: 200))
        #expect(long.count == 128)
        #expect(long.hasSuffix("…"))
    }
}

@Suite struct UpdateDecision {
    let base = makeActivity(playing, artwork: nil, now: now, settings: Settings())

    @Test func ignoresNaturalClockDrift() {
        let later = makeActivity(.playing(track, position: 35), artwork: nil, now: now.addingTimeInterval(5.5), settings: Settings())
        #expect(!needsUpdate(base, later))
    }

    @Test func detectsSeek() {
        let seeked = makeActivity(.playing(track, position: 120), artwork: nil, now: now.addingTimeInterval(5), settings: Settings())
        #expect(needsUpdate(base, seeked))
    }

    @Test func detectsTrackChangePauseAndArtworkArrival() {
        let other = makeActivity(
            .playing(Track(id: "B", title: "Other", artist: "Artist", album: "Album", duration: 200), position: 30),
            artwork: nil, now: now, settings: Settings())
        #expect(needsUpdate(base, other))
        #expect(needsUpdate(base, nil))
        #expect(!needsUpdate(nil, nil))
        #expect(needsUpdate(base, makeActivity(playing, artwork: artwork, now: now, settings: Settings())))
    }

    @Test func detectsSettingsChange() {
        var settings = Settings()
        settings.statusDisplay = .artist
        #expect(needsUpdate(base, makeActivity(playing, artwork: nil, now: now, settings: settings)))
    }
}
