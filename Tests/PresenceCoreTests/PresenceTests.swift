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
        settings.statusDisplay = .songAndArtist
        #expect(try #require(makeActivity(playing, artwork: nil, now: now, settings: settings)).statusDisplayType == 2)
    }

    @Test func songAndArtistPutsBothOnTheFirstLineAndKeepsArtistAndAlbumBelow() throws {
        var settings = Settings()
        settings.statusDisplay = .songAndArtist
        let activity = try #require(makeActivity(playing, artwork: artwork, now: now, settings: settings))
        #expect(activity.statusDisplayType == 2)
        #expect(activity.details == "Song – Artist")
        #expect(activity.state == "Artist")
        #expect(activity.assets?.largeText == "Album")
        #expect(activity.detailsURL == "https://music/track")
        #expect(activity.stateURL == "https://music/artist")
    }

    @Test func songAndArtistKeepsTheArtistWhenThereIsNoAlbum() throws {
        var settings = Settings()
        settings.statusDisplay = .songAndArtist
        let single = PlaybackSnapshot.playing(Track(id: "S", title: "Song", artist: "Artist", album: "", duration: 200), position: 0)
        let activity = try #require(makeActivity(single, artwork: artwork, now: now, settings: settings))
        #expect(activity.details == "Song – Artist")
        #expect(activity.state == "Artist")
        #expect(activity.stateURL == "https://music/artist")
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

@Suite struct StartAtLogin {
    let now = Date(timeIntervalSince1970: 10_000)
    var off: Settings { var s = Settings(); s.startAtLogin = false; return s }

    @Test func runsAtLoginWhenEnabled() {
        #expect(!shouldSkipLaunch(settings: Settings(), now: now, sessionStart: now.addingTimeInterval(-5), lastStartRequest: nil))
    }

    @Test func skipsLoginLaunchWhenDisabled() {
        #expect(shouldSkipLaunch(settings: off, now: now, sessionStart: now.addingTimeInterval(-5), lastStartRequest: nil))
    }

    @Test func runsWhenTheAppAskedEvenRightAfterLogin() {
        #expect(!shouldSkipLaunch(settings: off, now: now, sessionStart: now.addingTimeInterval(-5), lastStartRequest: now.addingTimeInterval(-2)))
    }

    @Test func runsWhenLaunchedLongAfterLogin() {
        // e.g. launchd restarting it after a crash, or the user turning it on later
        #expect(!shouldSkipLaunch(settings: off, now: now, sessionStart: now.addingTimeInterval(-3_600), lastStartRequest: nil))
    }

    @Test func runsWhenTheSessionStartIsUnknown() {
        #expect(!shouldSkipLaunch(settings: off, now: now, sessionStart: nil, lastStartRequest: nil))
    }

    @Test func theRemovedAppNameOptionFallsBackToSongAndKeepsOtherSettings() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"statusDisplay":"appName","showButton":false}"#.utf8))
        #expect(settings.statusDisplay == .song)
        #expect(!settings.showButton)
    }

    @Test func olderSettingsFilesDefaultToStartingAtLogin() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"showButton":false}"#.utf8))
        #expect(settings.startAtLogin)
    }
}
