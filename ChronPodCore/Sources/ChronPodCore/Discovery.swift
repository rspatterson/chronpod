// ChronPod — podcast discovery, ported from AntennaPod's net/discovery module
// (ItunesTopListLoader, ItunesPodcastSearcher, FyydPodcastSearcher, PodcastIndexPodcastSearcher,
// CombinedSearcher). GPL-3.0.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A podcast suggested by a directory. Either `feedURL` is known, or `itunesID` must be looked up first.
public struct DiscoveredPodcast: Hashable, Sendable, Identifiable {
    public var id: String { feedURL ?? "itunes:\(itunesID ?? title)" }
    public var title: String
    public var author: String?
    public var imageURL: String?
    public var feedURL: String?
    public var itunesID: String?
    /// Which directory found it ("Apple Podcasts", "fyyd", "Podcast Index").
    public var source: String

    public init(title: String, author: String? = nil, imageURL: String? = nil, feedURL: String? = nil,
                itunesID: String? = nil, source: String) {
        self.title = title
        self.author = author
        self.imageURL = imageURL
        self.feedURL = feedURL
        self.itunesID = itunesID
        self.source = source
    }
}

/// Apple Podcasts categories offered on the Discover screen (Apple genre IDs).
public struct PodcastGenre: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// id 0 = all categories.
    public static let all: [PodcastGenre] = [
        PodcastGenre(id: 0, name: "All Categories"),
        PodcastGenre(id: 1489, name: "News"),
        PodcastGenre(id: 1511, name: "Government"),
        PodcastGenre(id: 1488, name: "True Crime"),
        PodcastGenre(id: 1324, name: "Society & Culture"),
        PodcastGenre(id: 1321, name: "Business"),
        PodcastGenre(id: 1487, name: "History"),
        PodcastGenre(id: 1304, name: "Education"),
        PodcastGenre(id: 1318, name: "Technology"),
        PodcastGenre(id: 1533, name: "Science"),
        PodcastGenre(id: 1512, name: "Health & Fitness"),
        PodcastGenre(id: 1303, name: "Comedy"),
        PodcastGenre(id: 1545, name: "Sports"),
        PodcastGenre(id: 1310, name: "Music"),
        PodcastGenre(id: 1309, name: "TV & Film"),
        PodcastGenre(id: 1301, name: "Arts"),
        PodcastGenre(id: 1483, name: "Fiction"),
        PodcastGenre(id: 1314, name: "Religion & Spirituality"),
        PodcastGenre(id: 1305, name: "Kids & Family"),
        PodcastGenre(id: 1502, name: "Leisure"),
    ]
}

public enum DiscoveryError: Error, LocalizedError {
    case noFeed
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .noFeed: return "Apple's directory has no public feed address for this podcast."
        case .http(let code): return "The podcast directory answered with error \(code)."
        }
    }
}

public enum Discovery {

    /// Countries offered for the Apple top charts.
    public static let countries: [(code: String, name: String)] = [
        ("us", "United States"), ("gb", "United Kingdom"), ("ca", "Canada"), ("au", "Australia"),
        ("ie", "Ireland"), ("nz", "New Zealand"), ("in", "India"), ("de", "Germany"), ("at", "Austria"),
        ("ch", "Switzerland"), ("fr", "France"), ("es", "Spain"), ("mx", "Mexico"), ("it", "Italy"),
        ("nl", "Netherlands"), ("be", "Belgium"), ("se", "Sweden"), ("no", "Norway"), ("dk", "Denmark"),
        ("fi", "Finland"), ("pl", "Poland"), ("br", "Brazil"), ("pt", "Portugal"), ("jp", "Japan"),
        ("kr", "South Korea"), ("za", "South Africa"),
    ]

    // MARK: Apple top charts

    public static func topChartURL(country: String, genre: Int, limit: Int = 25) -> URL {
        let genrePart = genre > 0 ? "genre=\(genre)/" : ""
        return URL(string: "https://itunes.apple.com/\(country.lowercased())/rss/toppodcasts/limit=\(limit)/\(genrePart)explicit=true/json")!
    }

    public static func topPodcasts(country: String, genre: Int, limit: Int = 25,
                                   session: URLSession = .shared) async throws -> [DiscoveredPodcast] {
        let (data, response) = try await session.data(from: topChartURL(country: country, genre: genre, limit: limit))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DiscoveryError.http(http.statusCode)
        }
        return parseTopChart(data)
    }

    /// Parses Apple's legacy RSS-generator JSON ({"feed":{"entry":[...]}}).
    public static func parseTopChart(_ data: Data) -> [DiscoveredPodcast] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any] else { return [] }
        var entries: [[String: Any]] = []
        if let list = feed["entry"] as? [[String: Any]] { entries = list }
        else if let one = feed["entry"] as? [String: Any] { entries = [one] }

        func label(_ obj: Any?) -> String? { (obj as? [String: Any])?["label"] as? String }

        return entries.compactMap { e -> DiscoveredPodcast? in
            guard let title = label(e["im:name"]) else { return nil }
            let idAttrs = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
            let itunesID = idAttrs?["im:id"] as? String
            var image: String?
            if let images = e["im:image"] as? [[String: Any]] {
                // Largest image, preferring one at least 100 px high (as AntennaPod does).
                func height(_ img: [String: Any]) -> Int {
                    let attrs = img["attributes"] as? [String: Any]
                    let h = attrs?["height"] as? String ?? "0"
                    return Int(h) ?? 0
                }
                let sorted = images.sorted { height($0) > height($1) }
                image = sorted.first?["label"] as? String
            }
            return DiscoveredPodcast(title: title, author: label(e["im:artist"]), imageURL: image,
                                     feedURL: nil, itunesID: itunesID, source: "Apple Podcasts")
        }
    }

    /// Finds the RSS feed address for an Apple Podcasts ID.
    public static func lookupFeedURL(itunesID: String, session: URLSession = .shared) async throws -> String {
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(itunesID)")!
        let (data, _) = try await session.data(from: url)
        guard let feed = parseLookup(data) else { throw DiscoveryError.noFeed }
        return feed
    }

    public static func parseLookup(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        return results.compactMap { $0["feedUrl"] as? String }.first
    }

    // MARK: Search providers

    public static func searchApple(_ term: String, session: URLSession = .shared) async throws -> [DiscoveredPodcast] {
        try await PodcastSearch.search(term, session: session).map {
            DiscoveredPodcast(title: $0.title, author: $0.author, imageURL: $0.imageURL, feedURL: $0.feedURL,
                              source: "Apple Podcasts")
        }
    }

    public static func searchFyyd(_ term: String, session: URLSession = .shared) async throws -> [DiscoveredPodcast] {
        var comps = URLComponents(string: "https://api.fyyd.de/0.2/search/podcast")!
        comps.queryItems = [URLQueryItem(name: "title", value: term), URLQueryItem(name: "count", value: "20")]
        let (data, _) = try await session.data(from: comps.url!)
        return parseFyyd(data)
    }

    public static func parseFyyd(_ data: Data) -> [DiscoveredPodcast] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { p -> DiscoveredPodcast? in
            guard let feed = p["xmlURL"] as? String, !feed.isEmpty else { return nil }
            return DiscoveredPodcast(title: (p["title"] as? String) ?? "Unknown",
                                     author: p["author"] as? String,
                                     imageURL: (p["thumbImageURL"] as? String) ?? (p["imgURL"] as? String),
                                     feedURL: feed, source: "fyyd")
        }
    }

    /// Podcast Index needs a free API key and secret (https://api.podcastindex.org).
    public static func searchPodcastIndex(_ term: String, key: String, secret: String,
                                          session: URLSession = .shared) async throws -> [DiscoveredPodcast] {
        var comps = URLComponents(string: "https://api.podcastindex.org/api/1.0/search/byterm")!
        comps.queryItems = [URLQueryItem(name: "q", value: term), URLQueryItem(name: "max", value: "20")]
        var req = URLRequest(url: comps.url!)
        for (k, v) in podcastIndexHeaders(key: key, secret: secret, now: Date()) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DiscoveryError.http(http.statusCode)
        }
        return parsePodcastIndex(data)
    }

    public static func podcastIndexHeaders(key: String, secret: String, now: Date) -> [String: String] {
        let time = String(Int(now.timeIntervalSince1970))
        return [
            "X-Auth-Date": time,
            "X-Auth-Key": key,
            "Authorization": sha1Hex(key + secret + time),
            "User-Agent": "ChronPod/1.0",
        ]
    }

    public static func parsePodcastIndex(_ data: Data) -> [DiscoveredPodcast] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feeds = root["feeds"] as? [[String: Any]] else { return [] }
        return feeds.compactMap { p -> DiscoveredPodcast? in
            guard let url = p["url"] as? String, !url.isEmpty else { return nil }
            let image = (p["artwork"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (p["image"] as? String)
            return DiscoveredPodcast(title: (p["title"] as? String) ?? "Unknown", author: p["author"] as? String,
                                     imageURL: image, feedURL: url, source: "Podcast Index")
        }
    }

    static func sha1Hex(_ s: String) -> String {
        #if canImport(CryptoKit)
        return Insecure.SHA1.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        return ""
        #endif
    }

    /// Searches every enabled directory at once and merges the results, like AntennaPod's CombinedSearcher:
    /// podcasts found by several directories rank higher, and duplicates are removed.
    public static func searchAll(_ term: String, useFyyd: Bool = true, podcastIndexKey: String? = nil,
                                 podcastIndexSecret: String? = nil,
                                 session: URLSession = .shared) async -> (results: [DiscoveredPodcast], errors: [String]) {
        var lists: [(Int, [DiscoveredPodcast])] = []
        var errors: [String] = []

        await withTaskGroup(of: (Int, Result<[DiscoveredPodcast], Error>).self) { group in
            group.addTask {
                do { return (0, .success(try await searchApple(term, session: session))) }
                catch { return (0, .failure(error)) }
            }
            if useFyyd {
                group.addTask {
                    do { return (1, .success(try await searchFyyd(term, session: session))) }
                    catch { return (1, .failure(error)) }
                }
            }
            if let key = podcastIndexKey, let secret = podcastIndexSecret, !key.isEmpty, !secret.isEmpty {
                group.addTask {
                    do { return (2, .success(try await searchPodcastIndex(term, key: key, secret: secret, session: session))) }
                    catch { return (2, .failure(error)) }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let list): lists.append((index, list))
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
        }
        return (merge(lists.sorted { $0.0 < $1.0 }.map { $0.1 }), errors)
    }

    /// Merges ranked lists: a podcast's score adds up across directories (higher rank = more points).
    public static func merge(_ lists: [[DiscoveredPodcast]]) -> [DiscoveredPodcast] {
        var score: [String: Double] = [:]
        var first: [String: DiscoveredPodcast] = [:]
        var order: [String] = []
        for list in lists {
            for (rank, p) in list.enumerated() {
                guard let feed = p.feedURL else { continue }
                let key = normalizedKey(feed)
                score[key, default: 0] += 1.0 / Double(rank + 1)
                if first[key] == nil {
                    first[key] = p
                    order.append(key)
                }
            }
        }
        return order.sorted { (score[$0] ?? 0) > (score[$1] ?? 0) }.compactMap { first[$0] }
    }

    static func normalizedKey(_ url: String) -> String {
        var s = url.lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
