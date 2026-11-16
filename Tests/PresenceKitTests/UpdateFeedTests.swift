import Foundation
import Testing

@testable import PresenceKit

@Suite struct Versions {
    @Test func parsesTagsWithOrWithoutPrefix() {
        #expect(AppVersion("v0.2.0")?.description == "0.2.0")
        #expect(AppVersion("1.4")?.description == "1.4.0")
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("1.2.3.4") == nil)
    }

    @Test func comparesNumericallyNotAlphabetically() throws {
        let v = { (s: String) throws -> AppVersion in try #require(AppVersion(s)) }
        #expect(try v("0.10.0") > v("0.9.9"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("0.2.0") < v("0.2.1"))
    }
}

@Suite struct LatestRelease {
    let current = AppVersion("0.2.0")!

    func release(tag: String, assets: [String]) -> Data {
        let list = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/x/releases/download/\#(tag)/\#($0)"}"#
        }
        return Data(#"{"tag_name":"\#(tag)","html_url":"https://github.com/x/releases/tag/\#(tag)","assets":[\#(list.joined(separator: ","))]}"#.utf8)
    }

    @Test func offersNewerReleaseWithItsAppZip() throws {
        let data = release(tag: "v0.3.0", assets: ["notes.txt", "DiscordAppleMusic-0.3.0-macos.zip"])
        let update = try #require(try UpdateFeed.update(fromLatestRelease: data, current: current))
        #expect(update.version.description == "0.3.0")
        #expect(update.downloadURL.absoluteString == "https://github.com/x/releases/download/v0.3.0/DiscordAppleMusic-0.3.0-macos.zip")
        #expect(update.pageURL.absoluteString == "https://github.com/x/releases/tag/v0.3.0")
    }

    @Test func ignoresSameOrOlderReleases() throws {
        #expect(try UpdateFeed.update(fromLatestRelease: release(tag: "v0.2.0", assets: ["DiscordAppleMusic-0.2.0-macos.zip"]), current: current) == nil)
        #expect(try UpdateFeed.update(fromLatestRelease: release(tag: "v0.1.0", assets: ["discord-apple-music-0.1.0-macos-arm64.zip"]), current: current) == nil)
    }

    @Test func ignoresNewerReleaseWithoutAppZip() throws {
        #expect(try UpdateFeed.update(fromLatestRelease: release(tag: "v0.3.0", assets: ["other.zip"]), current: current) == nil)
    }

    @Test func rejectsMalformedResponses() {
        #expect(throws: (any Error).self) { try UpdateFeed.update(fromLatestRelease: Data("{}".utf8), current: current) }
    }
}
