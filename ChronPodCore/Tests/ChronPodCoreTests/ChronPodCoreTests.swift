import XCTest
@testable import ChronPodCore

final class FeedParserTests: XCTestCase {

    func testPodcastRSS() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
             xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Law Talk</title>
            <link>https://example.com</link>
            <description>A show about law.</description>
            <itunes:author>Jane Lawyer</itunes:author>
            <itunes:image href="https://example.com/cover.jpg"/>
            <item>
              <title>Episode 1: Hearsay</title>
              <guid isPermaLink="false">ep-1</guid>
              <pubDate>Mon, 02 Nov 2026 10:00:00 +0000</pubDate>
              <enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg" length="12345"/>
              <itunes:duration>01:02:03</itunes:duration>
              <content:encoded><![CDATA[<p>Show <b>notes</b></p>]]></content:encoded>
            </item>
            <item>
              <title>Text only post</title>
              <link>https://example.com/post</link>
              <description>No audio here &amp; that is fine</description>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), feedURL: "https://example.com/feed")
        XCTAssertEqual(feed.title, "Law Talk")
        XCTAssertEqual(feed.author, "Jane Lawyer")
        XCTAssertEqual(feed.imageURL, "https://example.com/cover.jpg")
        XCTAssertEqual(feed.link, "https://example.com")
        XCTAssertEqual(feed.episodes.count, 2)

        let ep = feed.episodes[0]
        XCTAssertEqual(ep.title, "Episode 1: Hearsay")
        XCTAssertEqual(ep.guid, "ep-1")
        XCTAssertEqual(ep.enclosureURL, "https://cdn.example.com/ep1.mp3")
        XCTAssertEqual(ep.enclosureLength, 12345)
        XCTAssertEqual(ep.duration, 3723)
        XCTAssertEqual(ep.summary, "<p>Show <b>notes</b></p>")
        XCTAssertNotNil(ep.pubDate)
        XCTAssertTrue(ep.hasMedia)

        XCTAssertFalse(feed.episodes[1].hasMedia)
        XCTAssertEqual(feed.episodes[1].link, "https://example.com/post")
    }

    func testGoogleNewsRSS() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
          <channel>
            <generator>NFE/5.0</generator>
            <title>"Animal Law" - Google News</title>
            <link>https://news.google.com/search?q=Animal+Law</link>
            <item>
              <title>Court rules on dog bite case - Houston Chronicle</title>
              <link>https://news.google.com/rss/articles/CBMiK0FVX3lxTE5fYWJj?oc=5</link>
              <guid isPermaLink="false">CBMiK0FVX3lxTE5fYWJj</guid>
              <pubDate>Sun, 08 Nov 2026 14:00:00 GMT</pubDate>
              <description>&lt;a href="https://news.google.com/rss/articles/CBMiK0FVX3lxTE5fYWJj?oc=5"&gt;Court rules&lt;/a&gt;</description>
              <source url="https://www.houstonchronicle.com">Houston Chronicle</source>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), feedURL: "https://news.google.com/rss/search?q=x")
        XCTAssertEqual(feed.title, "\"Animal Law\" - Google News")
        XCTAssertEqual(feed.episodes.count, 1)
        let ep = feed.episodes[0]
        XCTAssertFalse(ep.hasMedia)
        XCTAssertEqual(ep.sourceName, "Houston Chronicle")
        XCTAssertEqual(ep.guid, "CBMiK0FVX3lxTE5fYWJj")
        XCTAssertNotNil(ep.pubDate)
        XCTAssertTrue(GoogleNews.isGoogleLink(ep.link ?? ""))
    }

    func testAtom() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Appellate Blog</title>
          <link rel="alternate" href="https://blog.example.com/"/>
          <author><name>A. Writer</name></author>
          <entry>
            <id>tag:blog.example.com,2026:1</id>
            <title>Standards of review</title>
            <link rel="alternate" href="https://blog.example.com/1"/>
            <link rel="enclosure" type="audio/mpeg" length="99" href="https://blog.example.com/1.mp3"/>
            <published>2026-11-01T12:30:00.123456+02:00</published>
            <summary>Short</summary>
            <content type="html">&lt;p&gt;Long&lt;/p&gt;</content>
          </entry>
        </feed>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), feedURL: "https://blog.example.com/atom")
        XCTAssertEqual(feed.title, "Appellate Blog")
        XCTAssertEqual(feed.author, "A. Writer")
        XCTAssertEqual(feed.link, "https://blog.example.com/")
        let ep = try XCTUnwrap(feed.episodes.first)
        XCTAssertEqual(ep.link, "https://blog.example.com/1")
        XCTAssertEqual(ep.enclosureURL, "https://blog.example.com/1.mp3")
        XCTAssertEqual(ep.summary, "<p>Long</p>")
        XCTAssertNotNil(ep.pubDate)
    }

    func testNotAFeed() {
        XCTAssertThrowsError(try FeedParser.parse(data: Data("<html><body>hi</body></html>".utf8), feedURL: "x"))
    }
}

final class DateTests: XCTestCase {
    func testFormats() {
        let samples = [
            "Mon, 02 Nov 2026 10:00:00 +0000",
            "Sun, 08 Nov 2026 14:00:00 GMT",
            "2026-11-01T12:30:00Z",
            "2026-11-01T12:30:00+02:00",
            "2026-11-01T12:30:00.1234567Z",
            "2026-11-01",
            "Thu, 3 Sept 2026 08:00:00 +0100",
        ]
        for s in samples {
            XCTAssertNotNil(FeedDate.parse(s), s)
        }
        XCTAssertNil(FeedDate.parse("not a date"))
    }

    func testDuration() {
        XCTAssertEqual(FeedDate.parseDuration("1:02:03"), 3723)
        XCTAssertEqual(FeedDate.parseDuration("45:00"), 2700)
        XCTAssertEqual(FeedDate.parseDuration("600"), 600)
        XCTAssertNil(FeedDate.parseDuration("abc"))
    }
}

final class OPMLTests: XCTestCase {
    let sample = """
    <?xml version="1.0" encoding="utf-8"?>
    <opml version="1.0">
      <head><title>Tiny Tiny RSS Feed Export</title></head>
      <body>
        <outline text="Admiralty and Maritime Law" ttrssSortOrder="0">
          <outline type="rss" text="Admiralty and Maritime Law" xmlUrl="https://news.google.com/news/rss/search/section/q/admiralty+law|maritime+law|seamen"/>
        </outline>
        <outline text="Breaking News">
          <outline type="rss" text="Breaking News" xmlUrl="https://news.google.com/news/rss/search/section/q/World+News"/>
          <outline type="rss" text="Breaking News" xmlUrl="https://news.google.com/news/rss/search/section/q/Breaking+News"/>
        </outline>
        <outline type="rss" text="Loose Podcast" xmlUrl="https://example.com/podcast.xml"/>
      </body>
    </opml>
    """

    func testParseAndDirectory() throws {
        let outlines = try OPMLParser.parse(data: Data(sample.utf8))
        XCTAssertEqual(outlines.count, 3)
        XCTAssertEqual(outlines[1].children.count, 2)

        let cats = ChronLawDirectory.categories(from: outlines)
        XCTAssertEqual(cats.map(\.title), ["Admiralty and Maritime Law", "Breaking News", "General"])
        let breaking = try XCTUnwrap(cats.first { $0.title == ChronLawDirectory.starterCategory })
        XCTAssertEqual(breaking.feeds.count, 2)
        XCTAssertTrue(breaking.feeds[0].url.hasPrefix("https://news.google.com/rss/search?q=World%20News"))
        XCTAssertEqual(breaking.feeds[0].detail, "News search: World News")
        XCTAssertEqual(breaking.feeds[0].title, "Breaking News: World News")
        XCTAssertEqual(cats[0].feeds[0].title, "Admiralty and Maritime Law")
        XCTAssertEqual(cats[0].feeds[0].detail, "News search: admiralty law OR maritime law OR seamen")
    }

    func testExportRoundTrip() throws {
        let pods = [
            Podcast(feedURL: "https://a.example/feed?x=1&y=2", title: "A & B"),
            Podcast(feedURL: "https://news.google.com/rss/search?q=Tax", title: "Tax Law", directoryCategory: "Tax Law"),
        ]
        let xml = OPMLWriter.export(pods)
        let parsed = try OPMLParser.parse(data: Data(xml.utf8))
        let feeds = parsed.flatMap { $0.allFeeds }
        XCTAssertEqual(Set(feeds.compactMap(\.xmlURL)), Set(pods.map(\.feedURL)))
        XCTAssertTrue(feeds.contains { $0.title == "A & B" })
    }

    func testInvalid() {
        XCTAssertThrowsError(try OPMLParser.parse(data: Data("hello".utf8)))
    }
}

final class GoogleNewsTests: XCTestCase {
    func testModernize() {
        XCTAssertEqual(
            GoogleNews.modernizeFeedURL("https://news.google.com/news/rss/search/section/q/Animal+Law"),
            "https://news.google.com/rss/search?q=Animal%20Law&hl=en-US&gl=US&ceid=US:en")
        XCTAssertEqual(
            GoogleNews.modernizeFeedURL("https://news.google.com/news/rss/search/section/q/CLE+Continuing Legal Education"),
            "https://news.google.com/rss/search?q=CLE%20Continuing%20Legal%20Education&hl=en-US&gl=US&ceid=US:en")
        XCTAssertEqual(
            GoogleNews.modernizeFeedURL("http://news.google.com/news?pz=1&cf=all&ned=us&hl=en&topic=h&num=3&output=rss"),
            "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en")
        let untouched = "https://example.com/feed.xml"
        XCTAssertEqual(GoogleNews.modernizeFeedURL(untouched), untouched)
        let current = "https://news.google.com/rss/search?q=Tax&hl=en-US&gl=US&ceid=US:en"
        XCTAssertEqual(GoogleNews.modernizeFeedURL(current), current)
    }

    func testOfflineResolution() {
        XCTAssertEqual(GoogleNews.resolveOffline(
            "https://www.google.com/url?rct=j&sa=t&url=https://www.khou.com/article/news/x/285-abc&ct=ga&cd=CAIy&usg=AOv"),
            "https://www.khou.com/article/news/x/285-abc")
        XCTAssertEqual(GoogleNews.resolveOffline("https://www.google.com/amp/s/www.cnn.com/2026/11/01/us/story/index.html"),
                       "https://www.cnn.com/2026/11/01/us/story/index.html")

        let real = "https://www.reuters.com/world/us/some-article-2026-11-01/"
        var bytes: [UInt8] = [0x08, 0x13, 0x22, UInt8(real.utf8.count)]
        bytes += Array(real.utf8)
        bytes += [0xd2, 0x01, 0x00]
        let id = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(GoogleNews.resolveOffline("https://news.google.com/rss/articles/\(id)?oc=5"), real)

        // New-style IDs cannot be decoded offline.
        XCTAssertNil(GoogleNews.decodeArticleIDOffline("CBMiK0FVX3lxTE5fYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXowMTIzNDU2Nzg5"))
    }

    func testIsGoogleLink() {
        XCTAssertTrue(GoogleNews.isGoogleLink("https://news.google.com/rss/articles/CBMi123?oc=5"))
        XCTAssertTrue(GoogleNews.isGoogleLink("https://www.google.com/url?q=https://x.example"))
        XCTAssertFalse(GoogleNews.isGoogleLink("https://news.google.com/"))
        XCTAssertFalse(GoogleNews.isGoogleLink("https://www.nytimes.com/x.html"))
    }

    func testSignatureAndBatchExecute() throws {
        let html = #"<c-wiz><div jscontroller="aLI87" data-n-a-sg="AZ5r3eSIG_abc" data-n-a-ts="1730000000"></div></c-wiz>"#
        let sig = try XCTUnwrap(GoogleNews.parseSignature(html: html))
        XCTAssertEqual(sig.signature, "AZ5r3eSIG_abc")
        XCTAssertEqual(sig.timestamp, "1730000000")

        let body = try XCTUnwrap(GoogleNews.batchExecuteBody(id: "CBMiXYZ", signature: sig.signature, timestamp: sig.timestamp))
        XCTAssertTrue(body.hasPrefix("f.req="))
        let decoded = try XCTUnwrap(String(body.dropFirst(6)).removingPercentEncoding)
        XCTAssertTrue(decoded.contains("garturlreq"))
        XCTAssertTrue(decoded.contains("CBMiXYZ"))
        XCTAssertTrue(decoded.contains("1730000000"))

        let response = ")]}'\n\n[[\"wrb.fr\",\"Fbv4je\",\"[\\\"garturlres\\\",\\\"https://a.example/x?y=1\\\",1]\",null,null,null,\"generic\"],[\"di\",42]]"
        XCTAssertEqual(GoogleNews.parseBatchExecute(response), "https://a.example/x?y=1")
    }
}

final class MiscTests: XCTestCase {
    func testHTMLPlainText() {
        XCTAssertEqual(HTMLText.plainText("<p>Hello &amp; welcome</p><p>Line&#39;2</p>"), "Hello & welcome\n\nLine'2")
        XCTAssertEqual(HTMLText.links(in: #"<a href="https://a.example/?x=1&amp;y=2">x</a>"#), ["https://a.example/?x=1&y=2"])
    }

    func testNormalize() {
        XCTAssertEqual(FeedFetcher.normalize(" example.com/feed "), "https://example.com/feed")
        XCTAssertEqual(FeedFetcher.normalize("feed://example.com/rss"), "https://example.com/rss")
    }

    func testSearchParsing() throws {
        let json = #"{"resultCount":1,"results":[{"collectionName":"Law Pod","artistName":"Bar","feedUrl":"https://lp.example/rss","artworkUrl600":"https://lp.example/a.jpg"},{"collectionName":"No feed"}]}"#
        let results = try PodcastSearch.parseResults(Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].feedURL, "https://lp.example/rss")
    }
}
