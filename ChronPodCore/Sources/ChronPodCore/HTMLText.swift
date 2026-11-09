// ChronPod — HTML helpers for show notes and news summaries. GPL-3.0.

import Foundation

public enum HTMLText {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "hellip": "…", "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·",
        "eacute": "é", "egrave": "è", "aacute": "á", "oacute": "ó", "uacute": "ú", "iacute": "í",
        "ntilde": "ñ", "uuml": "ü", "ouml": "ö", "auml": "ä", "ccedil": "ç", "sect": "§", "para": "¶",
    ]

    /// Decodes `&amp;`, `&#39;`, `&#x2019;` and common named entities.
    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let entity = String(s[s.index(after: i)..<semi])
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    if let code = UInt32(entity.dropFirst(2), radix: 16), let u = Unicode.Scalar(code) {
                        replacement = String(Character(u))
                    }
                } else if entity.hasPrefix("#") {
                    if let code = UInt32(entity.dropFirst()), let u = Unicode.Scalar(code) {
                        replacement = String(Character(u))
                    }
                } else {
                    replacement = named[entity.lowercased()]
                }
                if let r = replacement {
                    out += r
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    /// Converts HTML show notes into readable plain text with paragraph breaks.
    public static func plainText(_ html: String?) -> String {
        guard var s = html, !s.isEmpty else { return "" }
        s = s.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|tr|blockquote)>", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<li[^>]*>", with: "• ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All `href` targets in an HTML fragment (entity-decoded).
    public static func links(in html: String?) -> [String] {
        guard let html, let re = try? NSRegularExpression(pattern: "href\\s*=\\s*[\"']([^\"']+)[\"']",
                                                          options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            decodeEntities(ns.substring(with: $0.range(at: 1)))
        }
    }
}
