import Foundation
import PresenceCore

public enum ITunesEntity: String, Sendable {
    case song, album
}

public struct ITunesResult: Decodable, Equatable, Sendable {
    var trackName: String?
    var artistName: String?
    var collectionName: String?
    var artworkUrl100: String?
    var trackViewUrl: String?
    var artistViewUrl: String?
    var collectionViewUrl: String?
}

public typealias ITunesSearch = @Sendable (_ term: String, _ entity: ITunesEntity) async throws -> [ITunesResult]

/// Public iTunes Search API; no key required.
public let searchITunes: ITunesSearch = { term, entity in
    var components = URLComponents(string: "https://itunes.apple.com/search")!
    components.queryItems = [
        .init(name: "term", value: term),
        .init(name: "media", value: "music"),
        .init(name: "entity", value: entity.rawValue),
        .init(name: "limit", value: "25"),
    ]
    var request = URLRequest(url: components.url!)
    request.timeoutInterval = 5
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    struct Page: Decodable { var results: [ITunesResult] }
    return try JSONDecoder().decode(Page.self, from: data).results
}

/// Case-, accent- and punctuation-insensitive form, so "Sān-Z" matches "San-Z".
func normalize(_ value: String?) -> String {
    (value ?? "")
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
}

/// Catalogs credit artists differently ("A & B" vs "A, B & C"), so compare by the lead artist.
func sameArtist(_ a: String?, _ b: String?) -> Bool {
    func lead(_ value: String?) -> String {
        let separators = [",", "&", " feat.", " ft.", " x "]
        var head = value ?? ""
        for separator in separators {
            if let range = head.range(of: separator, options: .caseInsensitive) { head = String(head[..<range.lowerBound]) }
        }
        return normalize(head)
    }
    return !lead(a).isEmpty && lead(a) == lead(b)
}

/// Drops iTunes affiliate tracking (`uo`) and any other listed query parameters.
func cleanURL(_ url: String?, removing extra: [String] = []) -> String? {
    guard let url, var components = URLComponents(string: url) else { return nil }
    let drop = Set(["uo"] + extra)
    components.queryItems = components.queryItems?.filter { !drop.contains($0.name) }
    if components.queryItems?.isEmpty == true { components.queryItems = nil }
    return components.string
}

func artwork(from result: ITunesResult, includeTrack: Bool) -> Artwork? {
    guard let small = result.artworkUrl100 else { return nil }
    return Artwork(
        imageURL: small.replacingOccurrences(of: "100x100", with: "512x512"),
        trackURL: includeTrack ? cleanURL(result.trackViewUrl) : nil,
        artistURL: cleanURL(result.artistViewUrl),
        // collectionViewUrl carries `i=<trackId>`, which would open the song instead of the album.
        albumURL: cleanURL(result.collectionViewUrl, removing: ["i"])
    )
}

/// Looks up cover art and Apple Music links. Only exact matches are accepted:
/// showing no cover beats showing another song's cover.
public actor ITunesArtworkResolver: ArtworkResolver {
    private let search: ITunesSearch
    private var cache: [String: Artwork?] = [:]
    private var order: [String] = []
    private let cacheLimit = 200

    public init(search: @escaping ITunesSearch = searchITunes) {
        self.search = search
    }

    public func resolve(_ track: Track) async -> Artwork? {
        if let cached = cache[track.id] { return cached }
        // `try?` would flatten "no match" (nil) into "failed", so keep the two apart.
        let result: Artwork?
        do {
            result = try await lookup(track)
        } catch {
            return nil // network failure: retry next time instead of caching the miss
        }
        if order.count >= cacheLimit { cache[order.removeFirst()] = nil }
        order.append(track.id)
        cache[track.id] = .some(result)
        return result
    }

    private func lookup(_ track: Track) async throws -> Artwork? {
        let title = normalize(track.title)
        let album = normalize(track.album)
        let isSong = { (r: ITunesResult) in normalize(r.trackName) == title && sameArtist(r.artistName, track.artist) }

        // The full artist credit sometimes hides the song from search, so also try with the album.
        for term in ["\(track.title) \(track.artist)", "\(track.title) \(track.album)"] {
            let results = try await search(term, .song)
            if let match = results.first(where: { isSong($0) && normalize($0.collectionName) == album })
                ?? results.first(where: isSong)
            {
                return artwork(from: match, includeTrack: true)
            }
        }

        guard !album.isEmpty else { return nil }
        let albums = try await search("\(track.album) \(track.artist)", .album)
        let match = albums.first { normalize($0.collectionName) == album && sameArtist($0.artistName, track.artist) }
        return match.flatMap { artwork(from: $0, includeTrack: false) }
    }
}
