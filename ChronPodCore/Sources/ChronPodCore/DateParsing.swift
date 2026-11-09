// ChronPod — derived from AntennaPod's parser/feed/util/DateUtils.java (GPL-3.0).

import Foundation

/// Lenient feed date parser. Feeds often ignore the RFC 822 / ISO 8601 specs,
/// so this tries the same long list of patterns AntennaPod does.
public enum FeedDate {
    private static let patterns: [String] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "dd MMM yy HH:mm:ss Z",
        "dd MMM yy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm:ss",
        "EEE, dd MMMM yyyy HH:mm:ss Z",
        "EEE, dd MMMM yyyy HH:mm:ss",
        "EEEE, dd MMM yyyy HH:mm:ss Z",
        "EEEE, dd MMM yy HH:mm:ss Z",
        "EEEE, dd MMM yyyy HH:mm:ss",
        "EEEE, dd MMM yy HH:mm:ss",
        "EEE MMM d HH:mm:ss yyyy",
        "EEE, dd MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm",
        "EEE, dd MMMM yyyy HH:mm Z",
        "EEE, dd MMMM yyyy HH:mm",
        "EEEE, dd MMM yyyy HH:mm Z",
        "EEEE, dd MMM yy HH:mm Z",
        "EEEE, dd MMM yyyy HH:mm",
        "EEEE, dd MMM yy HH:mm",
        "EEE MMM d HH:mm yyyy",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-ddZ",
        "yyyy-MM-dd",
    ]

    private static let formatters: [DateFormatter] = patterns.map { pattern in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = pattern
        f.isLenient = false
        return f
    }

    private static let lock = NSLock()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func parse(_ input: String?) -> Date? {
        guard var date = input?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        // Well-formed ISO 8601 / RFC 3339 (Atom feeds) first.
        if let d = iso.date(from: date) ?? isoFractional.date(from: date) {
            return d
        }

        date = date.replacingOccurrences(of: "/", with: "-")
        date = date.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        // "+02:00" -> "+0200"
        date = date.replacingOccurrences(of: "([+-]\\d\\d):(\\d\\d)$", with: "$1$2", options: .regularExpression)
        date = date.replacingOccurrences(of: "CEST$", with: "+0200", options: .regularExpression)
        date = date.replacingOccurrences(of: "CET$", with: "+0100", options: .regularExpression)
        date = date.replacingOccurrences(of: "\\bSept\\b", with: "Sep", options: .regularExpression)
        // Normalize fractional seconds to at most three digits.
        date = date.replacingOccurrences(of: "\\.(\\d{3})\\d+", with: ".$1", options: .regularExpression)

        for f in formatters {
            if let d = f.date(from: date) {
                return d
            }
        }
        return nil
    }

    /// Parses "HH:MM:SS", "MM:SS" or plain seconds (itunes:duration).
    public static func parseDuration(_ input: String?) -> Double? {
        guard let s = input?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let nums = parts.compactMap { $0 }
        var total = 0.0
        for n in nums { total = total * 60 + n }
        return total > 0 ? total : nil
    }
}
