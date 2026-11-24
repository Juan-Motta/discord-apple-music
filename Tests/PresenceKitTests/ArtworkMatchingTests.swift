import Testing

@testable import PresenceCore
@testable import PresenceKit

private let track = Track(id: "T1", title: "Still Action!", artist: "Sān-Z & HOYO-MiX", album: "极限委托", duration: 120)

private func song(_ name: String, album: String, art: String? = nil) -> ITunesResult {
    ITunesResult(
        trackName: name,
        artistName: "Sān-Z & HOYO-MiX",
        collectionName: album,
        artworkUrl100: "https://img/\(art ?? name)/100x100bb.jpg",
        trackViewUrl: "https://music/track?i=1&uo=4",
        artistViewUrl: nil,
        collectionViewUrl: "https://music/album?i=1&uo=4"
    )
}

private actor FakeSearch {
    var calls: [(term: String, entity: ITunesEntity)] = []
    let byEntity: [ITunesEntity: [ITunesResult]]
    init(_ byEntity: [ITunesEntity: [ITunesResult]]) { self.byEntity = byEntity }
    func search(_ term: String, _ entity: ITunesEntity) -> [ITunesResult] {
        calls.append((term, entity))
        return byEntity[entity] ?? []
    }
}

private func resolver(_ fake: FakeSearch) -> ITunesArtworkResolver {
    ITunesArtworkResolver { term, entity in await fake.search(term, entity) }
}

@Suite struct ArtworkMatching {
    @Test func neverUsesAnUnrelatedSongBySameArtist() async {
        let fake = FakeSearch([.song: [song("Come Alive", album: "Come Alive - Single")]])
        #expect(await resolver(fake).resolve(track) == nil)
    }

    @Test func picksTheMatchingResultNotTheFirst() async {
        let fake = FakeSearch([.song: [song("Come Alive", album: "Single"), song("Still Action!", album: "极限委托", art: "still")]])
        let artwork = await resolver(fake).resolve(track)
        #expect(artwork?.imageURL == "https://img/still/512x512bb.jpg")
        #expect(artwork?.trackURL == "https://music/track?i=1")
        #expect(artwork?.albumURL == "https://music/album")
    }

    @Test func ignoresCaseAccentsAndPunctuation() async {
        let fake = FakeSearch([.song: [song("STILL ACTION !", album: "极限委托", art: "still")]])
        var plain = track
        plain.artist = "San-Z & HOYO-MiX"
        #expect(await resolver(fake).resolve(plain)?.imageURL == "https://img/still/512x512bb.jpg")
    }

    @Test func fallsBackToTheAlbumCover() async {
        let album = ITunesResult(
            trackName: nil, artistName: "Sān-Z & HOYO-MiX", collectionName: "极限委托",
            artworkUrl100: "https://img/album/100x100bb.jpg", trackViewUrl: nil, artistViewUrl: nil,
            collectionViewUrl: "https://music/album/x?uo=4")
        let fake = FakeSearch([.song: [song("Come Alive", album: "Single")], .album: [album]])
        let artwork = await resolver(fake).resolve(track)
        #expect(artwork == Artwork(imageURL: "https://img/album/512x512bb.jpg", albumURL: "https://music/album/x"))
    }

    @Test func cachesMisses() async {
        let fake = FakeSearch([:])
        let r = resolver(fake)
        _ = await r.resolve(track)
        let first = await fake.calls.count
        _ = await r.resolve(track)
        #expect(await fake.calls.count == first)
    }

    @Test func doesNotCacheNetworkFailures() async {
        let counter = FakeSearch([:])
        let failing = ITunesArtworkResolver { term, entity in
            _ = await counter.search(term, entity)
            throw URLErrorStub()
        }
        _ = await failing.resolve(track)
        _ = await failing.resolve(track)
        #expect(await counter.calls.count == 2)
    }
}

private struct URLErrorStub: Error {}

@Suite struct HardToSearchSongs {
    // Real case: "1-800" by "bbno$ & Ironmouse" is in the catalog, but iTunes search returns
    // nothing for terms with "$", and never lists the song for "1-800 bbno" either.
    let track = Track(id: "B1", title: "1-800", artist: "bbno$ & Ironmouse", album: "1-800 - Single", duration: 209)

    func catalogSong(art: String) -> ITunesResult {
        ITunesResult(
            trackName: "1-800", artistName: "bbno$ & Ironmouse", collectionName: "1-800 - Single",
            artworkUrl100: "https://img/\(art)/100x100bb.jpg", trackViewUrl: "https://music/1800?i=2",
            artistViewUrl: nil, collectionViewUrl: "https://music/1800-single?i=2")
    }

    @Test func dropsDollarSignsFromSearchTerms() async {
        let fake = FakeSearch([:])
        _ = await resolver(fake).resolve(track)
        let terms = await fake.calls.map(\.term)
        #expect(!terms.isEmpty)
        #expect(terms.allSatisfy { !$0.contains("$") })
    }

    @Test func findsTheSongInTheLeadArtistsCatalogWhenSearchMissesIt() async {
        let parody = ITunesResult(
            trackName: "67 (Parody of \"1-800\" by bbno$)", artistName: "Mobby Rosas", collectionName: "67 - Single",
            artworkUrl100: "https://img/parody/100x100bb.jpg", trackViewUrl: nil, artistViewUrl: nil, collectionViewUrl: nil)
        let artists = [
            ITunesResult(artistName: "Somebody Else", artistId: 1),
            ITunesResult(artistName: "bbno$", artistId: 1161580951),
        ]
        let fake = FakeSearch([.song: [parody], .musicArtist: artists])
        let resolver = ITunesArtworkResolver(
            search: { term, entity in await fake.search(term, entity) },
            artistSongs: { id in id == 1161580951 ? [parody, self.catalogSong(art: "1800")] : [] })
        let artwork = await resolver.resolve(track)
        #expect(artwork?.imageURL == "https://img/1800/512x512bb.jpg")
        #expect(artwork?.trackURL == "https://music/1800?i=2")
        #expect(await fake.calls.contains { $0.entity == .musicArtist && $0.term == "bbno" })
    }

    @Test func artistCatalogStillRequiresAnExactTitleMatch() async {
        let other = ITunesResult(
            trackName: "inshallah", artistName: "bbno$", collectionName: "inshallah - Single",
            artworkUrl100: "https://img/other/100x100bb.jpg", trackViewUrl: nil, artistViewUrl: nil, collectionViewUrl: nil)
        let fake = FakeSearch([.musicArtist: [ITunesResult(artistName: "bbno$", artistId: 7)]])
        let resolver = ITunesArtworkResolver(
            search: { term, entity in await fake.search(term, entity) },
            artistSongs: { _ in [other] })
        #expect(await resolver.resolve(track) == nil)
    }
}
