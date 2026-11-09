// ChronPod — OPML import/export, modeled on AntennaPod's OpmlReader / OpmlWriter. GPL-3.0.

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One `<outline>` element. Folders have children; feeds have an `xmlUrl`.
public struct OPMLOutline: Hashable, Sendable, Identifiable {
    public var id: String { (xmlURL ?? "folder:") + title + "#\(children.count)" }
    public var title: String
    public var xmlURL: String?
    public var htmlURL: String?
    public var children: [OPMLOutline]

    public init(title: String, xmlURL: String? = nil, htmlURL: String? = nil, children: [OPMLOutline] = []) {
        self.title = title
        self.xmlURL = xmlURL
        self.htmlURL = htmlURL
        self.children = children
    }

    public var isFeed: Bool { xmlURL != nil }

    /// Every feed at or below this outline.
    public var allFeeds: [OPMLOutline] {
        (isFeed ? [self] : []) + children.flatMap { $0.allFeeds }
    }
}

public enum OPMLError: Error, LocalizedError {
    case invalid
    public var errorDescription: String? { "The file is not a valid OPML subscription list." }
}

public final class OPMLParser: NSObject, XMLParserDelegate {
    private var stack: [OPMLOutline] = [OPMLOutline(title: "root")]
    private var sawOPML = false

    public static func parse(data: Data) throws -> [OPMLOutline] {
        let delegate = OPMLParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        _ = parser.parse()
        guard delegate.sawOPML, let root = delegate.stack.first else { throw OPMLError.invalid }
        return root.children
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName.lowercased() {
        case "opml":
            sawOPML = true
        case "outline":
            let title = attributes["text"] ?? attributes["title"] ?? ""
            let xml = attributes["xmlUrl"] ?? attributes["xmlurl"] ?? attributes["url"]
            stack.append(OPMLOutline(title: HTMLText.decodeEntities(title),
                                     xmlURL: (xml?.isEmpty ?? true) ? nil : xml,
                                     htmlURL: attributes["htmlUrl"] ?? attributes["htmlurl"]))
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?) {
        guard elementName.lowercased() == "outline", stack.count > 1 else { return }
        let done = stack.removeLast()
        stack[stack.count - 1].children.append(done)
    }
}

public enum OPMLWriter {
    /// Exports subscriptions; feeds from the ChronLaw directory are grouped under their category.
    public static func export(_ podcasts: [Podcast], title: String = "ChronPod Subscriptions") -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        func line(_ p: Podcast, indent: String) -> String {
            var s = "\(indent)<outline type=\"rss\" text=\"\(esc(p.title))\" title=\"\(esc(p.title))\" xmlUrl=\"\(esc(p.feedURL))\""
            if let link = p.link { s += " htmlUrl=\"\(esc(link))\"" }
            return s + "/>"
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var out = """
        <?xml version="1.0" encoding="utf-8"?>
        <opml version="2.0">
          <head>
            <title>\(esc(title))</title>
            <dateCreated>\(fmt.string(from: Date()))</dateCreated>
          </head>
          <body>

        """
        let grouped = Dictionary(grouping: podcasts.filter { $0.directoryCategory != nil }, by: { $0.directoryCategory! })
        for category in grouped.keys.sorted() {
            out += "    <outline text=\"\(esc(category))\">\n"
            for p in grouped[category]!.sorted(by: { $0.title < $1.title }) {
                out += line(p, indent: "      ") + "\n"
            }
            out += "    </outline>\n"
        }
        for p in podcasts.filter({ $0.directoryCategory == nil }).sorted(by: { $0.title < $1.title }) {
            out += line(p, indent: "    ") + "\n"
        }
        out += "  </body>\n</opml>\n"
        return out
    }
}
