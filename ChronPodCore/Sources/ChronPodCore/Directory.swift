// ChronPod — ChronLaw directory, podcast search and feed downloading. GPL-3.0.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - ChronLaw directory

/// A topic folder of the ChronLaw OPML (e.g. "Bankruptcy") and its feeds.
public struct DirectoryCategory: Hashable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var feeds: [DirectoryFeed]
    public init(title: String, feeds: [DirectoryFeed]) {
           self.title = title
           self.feeds = feeds
       }
}

public struct DirectoryFeed: Hashable, Sendable, Identifiable {
    public var id: String { url }
    /// Feed address (Google News addresses already converted to the current format).
    public var url: String
    public var title: String
    /// Short description shown under the title, e.g. the Google News search words.
    public var detail: String?
    public var category: String
}

public enum ChronLawDirectory {
    /// Where ChronPod looks for the current topic list. Replace the file on the website to update every user.
    public static let remoteURL = URL(string: "https://chronlaw.com/rss/chronlaw.opml")!
    /// Feeds in this category are subscribed automatically the first time the app opens.
    public static let starterCategory = "Breaking News"

    /// Turns OPML outlines into categories. Top-level feeds without a folder go into "General".
    public static func categories(from outlines: [OPMLOutline]) -> [DirectoryCategory] {
        var result: [DirectoryCategory] = []
        var loose: [DirectoryFeed] = []

        for outline in outlines {
            if outline.isFeed && outline.children.isEmpty {
                loose.append(makeFeed(outline, category: "General"))
                continue
            }
            let feeds = outline.allFeeds.map { makeFeed($0, category: outline.title) }
            guard !feeds.isEmpty else { continue }
            if let i = result.firstIndex(where: { $0.title == outline.title }) {
                result[i].feeds += feeds
            } else {
                result.append(DirectoryCategory(title: outline.title, feeds: feeds))
            }
        }
        if !loose.isEmpty { result.append(DirectoryCategory(title: "General", feeds: loose)) }

        // De-duplicate feeds within each category (keeping the OPML order), and give feeds that merely
        // repeat their folder's name a distinguishing title, e.g. "Breaking News: World News".
        return result.map { cat in
            var seen = Set<String>()
            var feeds = cat.feeds.filter { seen.insert($0.url).inserted }
            let titleCounts = Dictionary(grouping: feeds, by: \.title).mapValues(\.count)
            for i in feeds.indices where (titleCounts[feeds[i].title] ?? 0) > 1 {
                if let label = GoogleNews.searchLabel(for: feeds[i].url), label != feeds[i].title {
                    feeds[i].title = "\(feeds[i].title): \(label)"
                }
            }
            return DirectoryCategory(title: cat.title, feeds: feeds)
        }
    }

    private static func makeFeed(_ o: OPMLOutline, category: String) -> DirectoryFeed {
        let url = GoogleNews.modernizeFeedURL(o.xmlURL ?? "")
        let label = GoogleNews.searchLabel(for: url)
        let title = o.title.isEmpty ? (label ?? url) : o.title
        // Several feeds in one folder often share the folder's name; the search words tell them apart.
        let detail = label.map { "News search: \($0)" }
        return DirectoryFeed(url: url, title: title, detail: detail, category: category)
    }
}

// MARK: - Podcast search (Apple's public iTunes Search API, as AntennaPod's "iTunes" provider)

public struct PodcastSearchResult: Hashable, Sendable, Identifiable {
    public var id: String { feedURL }
    public var title: String
    public var author: String?
    public var feedURL: String
    public var imageURL: String?
}

public enum PodcastSearch {
    public static func search(_ term: String, session: URLSession = .shared) async throws -> [PodcastSearchResult] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "term", value: term),
        ]
        let (data, _) = try await session.data(from: comps.url!)
        return try parseResults(data)
    }

    public static func parseResults(_ data: Data) throws -> [PodcastSearchResult] {
        struct Response: Decodable {
            struct Item: Decodable {
                let collectionName: String?
                let artistName: String?
                let feedUrl: String?
                let artworkUrl600: String?
                let artworkUrl100: String?
            }
            let results: [Item]
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return r.results.compactMap { item in
            guard let feed = item.feedUrl, let title = item.collectionName else { return nil }
            return PodcastSearchResult(title: title, author: item.artistName, feedURL: feed,
                                       imageURL: item.artworkUrl600 ?? item.artworkUrl100)
        }
    }
}

// MARK: - Feed download

public enum FeedFetchError: Error, LocalizedError {
    case badURL
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "That is not a valid web address."
        case .http(let code): return "The server answered with error \(code)."
        }
    }
}

public enum FeedFetcher {
    /// Normalizes what a user types: adds https://, turns feed:// and itpc:// into https://,
    /// and converts retired Google News addresses.
    public static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["feed://", "itpc://", "pcast://", "podcast://"] where s.lowercased().hasPrefix(scheme) {
            s = "https://" + s.dropFirst(scheme.count)
        }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return GoogleNews.modernizeFeedURL(s)
    }

    public static func fetch(_ feedURL: String, session: URLSession = .shared) async throws -> ParsedFeed {
        guard let url = URL(string: feedURL) else { throw FeedFetchError.badURL }
        var req = URLRequest(url: url)
        req.setValue("ChronPod/1.0 (iOS; podcast and news reader)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedFetchError.http(http.statusCode)
        }
        return try FeedParser.parse(data: data, feedURL: feedURL)
    }
}
