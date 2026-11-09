// ChronPod — feed parsing modeled on AntennaPod's parser/feed module
// (namespace handlers Rss20, Atom, Itunes, Media, Content, DublinCore). GPL-3.0.

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum FeedParserError: Error, LocalizedError {
    case notAFeed
    case invalidXML(String)

    public var errorDescription: String? {
        switch self {
        case .notAFeed: return "This address does not contain an RSS or Atom feed."
        case .invalidXML(let msg): return "The feed could not be read (\(msg))."
        }
    }
}

/// Parses RSS 2.0 and Atom feeds, including iTunes, Media RSS, content and Dublin Core extensions.
public final class FeedParser: NSObject, XMLParserDelegate {

    private enum NS {
        static let itunes = "http://www.itunes.com/dtds/podcast-1.0.dtd"
        static let media = "http://search.yahoo.com/mrss/"
        static let content = "http://purl.org/rss/1.0/modules/content/"
        static let dc = "http://purl.org/dc/elements/1.1/"
        static let atom = "http://www.w3.org/2005/Atom"
    }

    private enum Kind { case unknown, rss, atom }

    private let podcastID: String
    private var kind: Kind = .unknown
    private var stack: [(ns: String, name: String)] = []
    private var text = ""

    // Feed-level
    private var feedTitle = ""
    private var feedAuthor: String?
    private var feedSummary: String?
    private var feedImage: String?
    private var feedLink: String?

    // Item-level
    private var inItem = false
    private var item = ItemBuilder()
    private var items: [Episode] = []

    private struct ItemBuilder {
        var title = ""
        var guid: String?
        var link: String?
        var summary: String?
        var content: String?
        var pubDate: Date?
        var enclosureURL: String?
        var enclosureType: String?
        var enclosureLength: Int64?
        var duration: Double?
        var image: String?
        var source: String?
    }

    private init(podcastID: String) {
        self.podcastID = podcastID
    }

    /// Parse feed data. `feedURL` becomes the podcast ID of the returned episodes.
    public static func parse(data: Data, feedURL: String) throws -> ParsedFeed {
        let delegate = FeedParser(podcastID: feedURL)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let ok = parser.parse()
        if delegate.kind == .unknown {
            if !ok, let err = parser.parserError {
                throw FeedParserError.invalidXML(err.localizedDescription)
            }
            throw FeedParserError.notAFeed
        }
        // Tolerate errors near the end of a feed if we already have items (AntennaPod does too).
        if !ok && delegate.items.isEmpty && delegate.feedTitle.isEmpty {
            throw FeedParserError.invalidXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        let title = delegate.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedFeed(
            title: title.isEmpty ? (URL(string: feedURL)?.host ?? feedURL) : title,
            author: delegate.feedAuthor,
            summary: delegate.feedSummary,
            imageURL: delegate.feedImage,
            link: delegate.feedLink,
            episodes: delegate.items
        )
    }

    // MARK: XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let ns = namespaceURI ?? ""
        let name = elementName.lowercased()
        stack.append((ns, name))
        text = ""

        if kind == .unknown {
            if name == "rss" || name == "rdf" { kind = .rss }
            else if name == "feed" { kind = .atom }
        }

        switch (ns, name) {
        case (_, "item") where kind == .rss, (_, "entry") where kind == .atom:
            inItem = true
            item = ItemBuilder()

        case (_, "enclosure") where inItem:
            if let url = attributes["url"], isMediaType(attributes["type"], url: url), item.enclosureURL == nil {
                item.enclosureURL = url
                item.enclosureType = attributes["type"]
                item.enclosureLength = attributes["length"].flatMap { Int64($0) }
            }

        case (NS.media, "content") where inItem:
            if let url = attributes["url"], item.enclosureURL == nil,
               isMediaType(attributes["type"], url: url, medium: attributes["medium"]) {
                item.enclosureURL = url
                item.enclosureType = attributes["type"]
                item.enclosureLength = attributes["filesize"].flatMap { Int64($0) }
                if item.duration == nil, let d = attributes["duration"] { item.duration = Double(d) }
            }

        case (NS.media, "thumbnail") where inItem:
            if item.image == nil { item.image = attributes["url"] }

        case (NS.itunes, "image"):
            if let href = attributes["href"] {
                if inItem { item.image = href } else { feedImage = href }
            }

        case (_, "link") where kind == .atom:
            let rel = attributes["rel"] ?? "alternate"
            guard let href = attributes["href"] else { break }
            if inItem {
                if rel == "enclosure", item.enclosureURL == nil {
                    item.enclosureURL = href
                    item.enclosureType = attributes["type"]
                    item.enclosureLength = attributes["length"].flatMap { Int64($0) }
                } else if rel == "alternate", item.link == nil {
                    item.link = href
                }
            } else if rel == "alternate", feedLink == nil {
                feedLink = href
            }

        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { text += s }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?) {
        let ns = namespaceURI ?? ""
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2].name : ""
        defer {
            if !stack.isEmpty { stack.removeLast() }
            text = ""
        }

        if inItem {
            switch (ns, name) {
            case (_, "item") where kind == .rss, (_, "entry") where kind == .atom:
                finishItem()
            case (NS.itunes, "title"):
                break // prefer the plain title
            case (NS.media, "title"):
                break
            case (_, "title"):
                if item.title.isEmpty { item.title = value }
            case (_, "guid"), (_, "id") where kind == .atom:
                if !value.isEmpty { item.guid = value }
            case (_, "link") where kind == .rss:
                if !value.isEmpty, ns != NS.atom { item.link = value }
            case (NS.content, "encoded"):
                if !value.isEmpty { item.content = value }
            case (NS.itunes, "summary"):
                if item.summary == nil, !value.isEmpty { item.summary = value }
            case (_, "description") where ns != NS.media, (_, "summary") where kind == .atom:
                if !value.isEmpty { item.summary = value }
            case (_, "content") where kind == .atom && ns == NS.atom:
                if !value.isEmpty { item.content = value }
            case (_, "pubdate"), (_, "published"):
                item.pubDate = FeedDate.parse(value) ?? item.pubDate
            case (NS.dc, "date"), (_, "updated"):
                if item.pubDate == nil { item.pubDate = FeedDate.parse(value) }
            case (NS.itunes, "duration"):
                item.duration = FeedDate.parseDuration(value)
            case (_, "source") where kind == .rss:
                if !value.isEmpty { item.source = value }
            default:
                break
            }
            return
        }

        // Feed-level elements (only direct children of channel / feed, or channel image).
        switch (ns, name) {
        case (_, "title") where (parent == "channel" || parent == "feed") && ns != NS.itunes:
            if feedTitle.isEmpty { feedTitle = value }
        case (_, "link") where parent == "channel" && kind == .rss && ns != NS.atom:
            if feedLink == nil, !value.isEmpty { feedLink = value }
        case (_, "description") where parent == "channel", (_, "subtitle") where parent == "feed":
            if feedSummary == nil, !value.isEmpty { feedSummary = value }
        case (NS.itunes, "summary") where parent == "channel":
            if feedSummary == nil, !value.isEmpty { feedSummary = value }
        case (NS.itunes, "author") where parent == "channel":
            if !value.isEmpty { feedAuthor = value }
        case (_, "name") where parent == "author" && kind == .atom:
            if feedAuthor == nil, !value.isEmpty { feedAuthor = value }
        case (_, "url") where parent == "image":
            if feedImage == nil, !value.isEmpty { feedImage = value }
        case (_, "logo"), (_, "icon"):
            if feedImage == nil, !value.isEmpty, kind == .atom { feedImage = value }
        default:
            break
        }
    }

    // MARK: Helpers

    private func finishItem() {
        inItem = false
        var title = item.title.isEmpty ? (item.source ?? "Untitled") : item.title
        // Google News appends the publisher ("Headline - Houston Chronicle"); it is shown separately.
        if let source = item.source, !source.isEmpty, title.hasSuffix(" - " + source),
           title.count > source.count + 3 {
            title = String(title.dropLast(source.count + 3))
        }
        let guid = item.guid ?? item.enclosureURL ?? item.link ?? title
        let ep = Episode(
            podcastID: podcastID,
            guid: guid,
            title: HTMLText.decodeEntities(title),
            summary: item.content ?? item.summary,
            pubDate: item.pubDate,
            link: item.link,
            enclosureURL: item.enclosureURL,
            enclosureType: item.enclosureType,
            enclosureLength: item.enclosureLength,
            duration: item.duration,
            imageURL: item.image,
            sourceName: item.source
        )
        items.append(ep)
    }

    /// Mirrors AntennaPod's MimeTypeUtils: accept audio/video types, or guess from the file extension.
    private func isMediaType(_ type: String?, url: String, medium: String? = nil) -> Bool {
        if let medium = medium?.lowercased(), medium == "audio" || medium == "video" { return true }
        if let t = type?.lowercased(), !t.isEmpty {
            if t.hasPrefix("audio/") || t.hasPrefix("video/") { return true }
            if t == "application/ogg" || t == "application/octet-stream" || t == "application/x-mpegurl" {
                return Self.hasMediaExtension(url)
            }
            return false
        }
        return Self.hasMediaExtension(url)
    }

    static func hasMediaExtension(_ url: String) -> Bool {
        let path = URL(string: url)?.path.lowercased() ?? url.lowercased()
        let exts = ["mp3", "m4a", "m4b", "aac", "ogg", "oga", "opus", "wav", "flac", "mp4", "m4v", "mov", "webm"]
        return exts.contains { path.hasSuffix("." + $0) }
    }
}
