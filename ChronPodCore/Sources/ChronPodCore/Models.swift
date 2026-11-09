// ChronPod — an iOS podcast and news-feed player derived from AntennaPod.
// Copyright (C) 2026 Richard S. Patterson and contributors.
// Licensed under the GNU General Public License v3.0 or later (see LICENSE).

import Foundation

/// A subscribed podcast or news feed (AntennaPod: `Feed`).
public struct Podcast: Codable, Hashable, Identifiable, Sendable {
    /// The feed URL is the identity of a subscription.
    public var id: String { feedURL }
    public var feedURL: String
    public var title: String
    public var author: String?
    public var summary: String?
    public var imageURL: String?
    public var link: String?
    /// Category name when the feed came from the ChronLaw directory.
    public var directoryCategory: String?
    public var lastRefreshed: Date?
    public var lastError: String?
    public var dateAdded: Date

    public init(feedURL: String, title: String, author: String? = nil, summary: String? = nil,
                imageURL: String? = nil, link: String? = nil, directoryCategory: String? = nil,
                lastRefreshed: Date? = nil, lastError: String? = nil, dateAdded: Date = Date()) {
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.summary = summary
        self.imageURL = imageURL
        self.link = link
        self.directoryCategory = directoryCategory
        self.lastRefreshed = lastRefreshed
        self.lastError = lastError
        self.dateAdded = dateAdded
    }
}

/// One item of a feed: a podcast episode (with audio/video) or a news story (text only).
/// AntennaPod: `FeedItem` + `FeedMedia`.
public struct Episode: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var podcastID: String
    public var guid: String
    public var title: String
    /// HTML description / show notes.
    public var summary: String?
    public var pubDate: Date?
    /// Web page for the item (for Google News items, a Google redirect link).
    public var link: String?
    /// Direct publisher link, once resolved from a Google redirect.
    public var resolvedLink: String?
    public var enclosureURL: String?
    public var enclosureType: String?
    public var enclosureLength: Int64?
    /// Duration in seconds, when the feed provides it.
    public var duration: Double?
    public var imageURL: String?
    /// Publisher name (Google News `<source>` element).
    public var sourceName: String?

    public init(podcastID: String, guid: String, title: String, summary: String? = nil, pubDate: Date? = nil,
                link: String? = nil, resolvedLink: String? = nil, enclosureURL: String? = nil,
                enclosureType: String? = nil, enclosureLength: Int64? = nil, duration: Double? = nil,
                imageURL: String? = nil, sourceName: String? = nil) {
        self.id = Episode.makeID(podcastID: podcastID, guid: guid)
        self.podcastID = podcastID
        self.guid = guid
        self.title = title
        self.summary = summary
        self.pubDate = pubDate
        self.link = link
        self.resolvedLink = resolvedLink
        self.enclosureURL = enclosureURL
        self.enclosureType = enclosureType
        self.enclosureLength = enclosureLength
        self.duration = duration
        self.imageURL = imageURL
        self.sourceName = sourceName
    }

    public static func makeID(podcastID: String, guid: String) -> String {
        "\(podcastID)\u{1F}\(guid)"
    }

    /// True for podcast episodes; false for text-only news items.
    public var hasMedia: Bool { enclosureURL != nil }

    public var isVideo: Bool { enclosureType?.lowercased().hasPrefix("video") ?? false }

    /// The link to open when the reader wants the full story.
    public var articleLink: String? { resolvedLink ?? link }
}

/// Feed contents as parsed from RSS/Atom, before being stored.
public struct ParsedFeed: Sendable {
    public var title: String
    public var author: String?
    public var summary: String?
    public var imageURL: String?
    public var link: String?
    public var episodes: [Episode]
}
