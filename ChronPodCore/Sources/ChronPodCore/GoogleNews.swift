// ChronPod — Google News helpers (ported from the af_google_unredirect tt-rss plugin). GPL-3.0.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GoogleNews {

    /// Converts retired Google News RSS addresses such as
    /// `https://news.google.com/news/rss/search/section/q/Animal+Law`
    /// to the current form `https://news.google.com/rss/search?q=Animal%20Law&hl=en-US&gl=US&ceid=US:en`.
    /// Other addresses are returned unchanged.
    public static func modernizeFeedURL(_ urlString: String, hl: String = "en-US", gl: String = "US",
                                        ceid: String = "US:en") -> String {
        // Parsed by hand: the old addresses contain spaces and "|", which URLComponents rejects.
        let lower = urlString.lowercased()
        guard lower.hasPrefix("https://news.google.com/") || lower.hasPrefix("http://news.google.com/") else {
            return urlString
        }
        // Retired "Top Stories" feed: news.google.com/news?...&output=rss
        if let comps = URLComponents(string: urlString), comps.path == "/news" || comps.path == "/news/",
           comps.queryItems?.contains(where: { $0.name == "output" && $0.value == "rss" }) == true {
            return "https://news.google.com/rss?hl=\(hl)&gl=\(gl)&ceid=\(ceid)"
        }
        let markers = ["/news/rss/search/section/q/", "/rss/search/section/q/", "/news/rss/search/q/"]
        guard let marker = markers.first(where: { urlString.contains($0) }),
              let range = urlString.range(of: marker) else { return urlString }

        var raw = String(urlString[range.upperBound...])
        if let cut = raw.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { raw = String(raw[..<cut]) }
        var query = (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "+", with: " ")
        query = query.replacingOccurrences(of: "|", with: " OR ")
        query = query.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return urlString }

        var out = URLComponents()
        out.scheme = "https"
        out.host = "news.google.com"
        out.path = "/rss/search"
        out.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: hl),
            URLQueryItem(name: "gl", value: gl),
            URLQueryItem(name: "ceid", value: ceid),
        ]
        return out.url?.absoluteString ?? urlString
    }

    /// The search words of a Google News feed address, for display ("World News", "admiralty law OR maritime law").
    public static func searchLabel(for urlString: String) -> String? {
        let modern = modernizeFeedURL(urlString)
        guard let comps = URLComponents(string: modern), comps.host == "news.google.com" else { return nil }
        return comps.queryItems?.first(where: { $0.name == "q" })?.value
    }

    // MARK: - Link resolution

    /// True when the link is a Google redirect/wrapper that hides the publisher's address.
    public static func isGoogleLink(_ url: String) -> Bool {
        guard let comps = URLComponents(string: url), let host = comps.host?.lowercased() else { return false }
        let path = comps.path
        if host == "news.google.com" {
            return path.range(of: "/(articles|read)/[^/]+$", options: .regularExpression) != nil
        }
        if host == "feedproxy.google.com" { return true }
        if host.range(of: "(^|\\.)google\\.[a-z]{2,3}(\\.[a-z]{2})?$", options: .regularExpression) != nil {
            return path == "/url" || path.hasPrefix("/amp/")
        }
        return false
    }

    /// Resolves without any network request when possible (Google Alerts/Search `/url?` links,
    /// AMP wrappers and older Google News article IDs).
    public static func resolveOffline(_ url: String) -> String? {
        guard let comps = URLComponents(string: url), let host = comps.host?.lowercased() else { return nil }
        let path = comps.path

        if path == "/url", host.contains("google.") {
            for key in ["url", "q", "u"] {
                if let v = comps.queryItems?.first(where: { $0.name == key })?.value,
                   v.lowercased().hasPrefix("http") {
                    return v
                }
            }
            return nil
        }

        if path.hasPrefix("/amp/"), host.contains("google.") {
            var target = String(path.dropFirst("/amp/".count))
            var secure = false
            if target.hasPrefix("s/") { target = String(target.dropFirst(2)); secure = true }
            if !target.lowercased().hasPrefix("http") { target = (secure ? "https://" : "http://") + target }
            if let q = comps.percentEncodedQuery { target += "?" + q }
            return target
        }

        if host == "news.google.com", let id = articleID(from: url) {
            return decodeArticleIDOffline(id)
        }
        return nil
    }

    static func articleID(from url: String) -> String? {
        guard let comps = URLComponents(string: url) else { return nil }
        let parts = comps.path.split(separator: "/")
        guard parts.count >= 2, ["articles", "read"].contains(String(parts[parts.count - 2])) else { return nil }
        return String(parts[parts.count - 1])
    }

    /// Older Google News IDs are base64url-encoded protobuf containing the URL in clear text.
    /// Current IDs (payload "AU_yqL…") need the online lookup.
    public static func decodeArticleIDOffline(_ id: String) -> String? {
        var b64 = id.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), !data.isEmpty else { return nil }
        let bytes = [UInt8](data)

        if bytes.count > 3, bytes[0] == 0x08, bytes[1] == 0x13, bytes[2] == 0x22 {
            var pos = 3
            var length = 0
            var shift = 0
            while pos < bytes.count {
                let b = Int(bytes[pos]); pos += 1
                length |= (b & 0x7f) << shift
                shift += 7
                if b & 0x80 == 0 { break }
            }
            if pos + length <= bytes.count,
               let s = String(bytes: bytes[pos..<(pos + length)], encoding: .utf8) {
                if s.hasPrefix("AU_yqL") { return nil }
                if s.hasPrefix("http://") || s.hasPrefix("https://") { return s }
            }
        }

        // Fallback: any clear-text URL inside the blob.
        let latin = String(decoding: bytes.map { ($0 >= 0x21 && $0 <= 0x7e) ? $0 : 0x20 }, as: UTF8.self)
        if latin.contains("AU_yqL") { return nil }
        if let r = latin.range(of: "https?://[^ ]+", options: .regularExpression) {
            return String(latin[r])
        }
        return nil
    }

    /// Extracts `data-n-a-sg` / `data-n-a-ts` from a Google News article page.
    public static func parseSignature(html: String) -> (signature: String, timestamp: String)? {
        func attr(_ name: String) -> String? {
            guard let r = html.range(of: "\(name)=\"([^\"]+)\"", options: .regularExpression) else { return nil }
            let full = String(html[r])
            guard let q1 = full.firstIndex(of: "\"") else { return nil }
            return HTMLText.decodeEntities(String(full[full.index(after: q1)..<full.index(before: full.endIndex)]))
        }
        guard let sg = attr("data-n-a-sg"), let ts = attr("data-n-a-ts") else { return nil }
        return (sg, ts)
    }

    /// Pulls the URL out of a batchexecute `garturlres` response.
    public static func parseBatchExecute(_ text: String) -> String? {
        var body = text
        if let r = body.range(of: "^\\s*\\)\\]\\}'\\s*", options: .regularExpression) { body.removeSubrange(r) }

        var candidates = [body.trimmingCharacters(in: .whitespacesAndNewlines)]
        for line in body.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { candidates.append(t) }
        }
        for chunk in candidates {
            guard let data = chunk.data(using: .utf8),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { continue }
            for case let row as [Any] in rows where row.count >= 3 {
                let tag0 = row[0] as? String
                let tag1 = row[1] as? String
                guard tag0 == "wrb.fr" || tag1 == "Fbv4je" else { continue }
                var payload: Any? = row[2]
                if let s = payload as? String, let d = s.data(using: .utf8) {
                    payload = try? JSONSerialization.jsonObject(with: d)
                }
                if let arr = payload as? [Any], arr.count >= 2, arr[0] as? String == "garturlres",
                   let url = arr[1] as? String, url.hasPrefix("http") {
                    return url
                }
            }
        }
        return nil
    }

    /// Builds the batchexecute form body for one article ID.
    public static func batchExecuteBody(id: String, signature: String, timestamp: String) -> String? {
        let ctx: [Any] = [
            ["X", "X", ["X", "X"], NSNull(), NSNull(), 1, 1, "US:en", NSNull(), 1, NSNull(), NSNull(), NSNull(),
             NSNull(), NSNull(), 0, 1],
            "X", "X", 1, [1, 1, 1], 1, 1, NSNull(), 0, 0, NSNull(), 0,
        ]
        let ts: Any = Int(timestamp) ?? timestamp
        let inner: [Any] = ["garturlreq", ctx, id, ts, signature]
        guard let innerData = try? JSONSerialization.data(withJSONObject: inner, options: [.withoutEscapingSlashes]),
              let innerJSON = String(data: innerData, encoding: .utf8)
        else { return nil }
        let outer: [Any] = [[["Fbv4je", innerJSON, NSNull(), "generic"]]]
        guard let outerData = try? JSONSerialization.data(withJSONObject: outer, options: [.withoutEscapingSlashes]),
              let outerJSON = String(data: outerData, encoding: .utf8) else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let enc = outerJSON.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "f.req=" + enc
    }
}

/// Resolves Google redirect links to the publisher's address, with an in-memory cache.
public actor GoogleLinkResolver {
    public static let shared = GoogleLinkResolver()

    private var cache: [String: String] = [:]
    private var lastRequest = Date.distantPast
    private let session: URLSession
    /// Pause between requests to Google, to avoid rate limiting.
    public var minimumInterval: TimeInterval = 0.75

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns the direct link, or nil if it could not be determined.
    public func resolve(_ url: String) async -> String? {
        if let hit = cache[url] { return hit }
        guard GoogleNews.isGoogleLink(url) else { return url }

        var result = GoogleNews.resolveOffline(url)
        if result == nil, let id = GoogleNews.articleID(from: url) {
            result = await resolveOnline(id: id, original: url)
        } else if result == nil, URL(string: url)?.host == "feedproxy.google.com" {
            result = await followRedirects(url)
        }
        // Unwrap nested wrappers once (e.g. a Google News item pointing to an AMP page).
        if let r = result, GoogleNews.isGoogleLink(r), let inner = GoogleNews.resolveOffline(r) {
            result = inner
        }
        if let r = result { cache[url] = r }
        return result
    }

    private func throttle() async {
        let wait = minimumInterval - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequest = Date()
    }

    private func resolveOnline(id: String, original: String) async -> String? {
        let comps = URLComponents(string: original)
        func q(_ n: String, _ d: String) -> String { comps?.queryItems?.first(where: { $0.name == n })?.value ?? d }
        var page = URLComponents()
        page.scheme = "https"
        page.host = "news.google.com"
        page.path = "/rss/articles/\(id)"
        page.queryItems = [URLQueryItem(name: "hl", value: q("hl", "en-US")),
                           URLQueryItem(name: "gl", value: q("gl", "US")),
                           URLQueryItem(name: "ceid", value: q("ceid", "US:en"))]
        guard let pageURL = page.url else { return nil }

        await throttle()
        guard let (data, response) = try? await session.data(from: pageURL),
              response.url?.host == "news.google.com",
              let html = String(data: data, encoding: .utf8),
              let sig = GoogleNews.parseSignature(html: html),
              let body = GoogleNews.batchExecuteBody(id: id, signature: sig.signature, timestamp: sig.timestamp),
              let endpoint = URL(string: "https://news.google.com/_/DotsSplashUi/data/batchexecute")
        else { return nil }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)

        await throttle()
        guard let (respData, _) = try? await session.data(for: req),
              let text = String(data: respData, encoding: .utf8) else { return nil }
        return GoogleNews.parseBatchExecute(text)
    }

    private func followRedirects(_ url: String) async -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: req), let final = response.url?.absoluteString,
              final != url else { return nil }
        return final
    }
}
