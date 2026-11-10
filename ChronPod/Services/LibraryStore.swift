// ChronPod — subscription library (AntennaPod: DBReader/DBWriter + FeedUpdateManager). GPL-3.0.

import Foundation
import ChronPodCore

@MainActor
final class LibraryStore: ObservableObject {

    /// Everything that is saved between launches.
    private struct State: Codable {
        var podcasts: [Podcast] = []
        var episodes: [String: [Episode]] = [:]
        var queue: [String] = []
        var positions: [String: Double] = [:]
        var played: Set<String> = []
        var starterSubscribed = false
        var favorites: Set<String> = []
        var autoDownload: Set<String> = []

        init() {}

        // Every field is optional when reading, so files saved by older versions still load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            podcasts = try c.decodeIfPresent([Podcast].self, forKey: .podcasts) ?? []
            episodes = try c.decodeIfPresent([String: [Episode]].self, forKey: .episodes) ?? [:]
            queue = try c.decodeIfPresent([String].self, forKey: .queue) ?? []
            positions = try c.decodeIfPresent([String: Double].self, forKey: .positions) ?? [:]
            played = try c.decodeIfPresent(Set<String>.self, forKey: .played) ?? []
            starterSubscribed = try c.decodeIfPresent(Bool.self, forKey: .starterSubscribed) ?? false
            favorites = try c.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
            autoDownload = try c.decodeIfPresent(Set<String>.self, forKey: .autoDownload) ?? []
        }
    }

    @Published private(set) var podcasts: [Podcast] = []
    @Published private(set) var episodesByPodcast: [String: [Episode]] = [:] { didSet { rebuildIndex() } }
    @Published private(set) var queue: [String] = []
    @Published private(set) var positions: [String: Double] = [:]
    @Published private(set) var played: Set<String> = []
    @Published private(set) var favorites: Set<String> = []
    /// Podcasts whose new episodes download automatically.
    @Published private(set) var autoDownload: Set<String> = []

    /// Called with newly found episodes of auto-download podcasts (the app passes them to the downloader).
    var onNewEpisodes: (@MainActor ([Episode]) -> Void)?

    @Published private(set) var directory: [DirectoryCategory] = []
    @Published private(set) var directorySource = "built-in list"
    @Published private(set) var refreshing: Set<String> = []
    @Published var message: String?

    private(set) var episodeIndex: [String: Episode] = [:]
    private var starterSubscribed = false
    private var saveTask: Task<Void, Never>?
    private var bootstrapped = false

    /// Most items kept per news feed / per podcast.
    private let newsLimit = 100
    private let podcastLimit = 1000

    private let stateURL: URL
    private let directoryCacheURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChronPod", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appendingPathComponent("library.json")
        directoryCacheURL = support.appendingPathComponent("chronlaw-directory.opml")
        load()
        loadDirectoryFromDisk()
    }

    // MARK: - Startup

    /// Loads the newest ChronLaw topic list, subscribes the starter feeds on first launch, refreshes everything.
    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await updateDirectoryFromWeb()
        if !starterSubscribed {
            if let starter = directory.first(where: { $0.title == ChronLawDirectory.starterCategory }) {
                await subscribe(directoryFeeds: starter.feeds)
            }
            starterSubscribed = true
            scheduleSave()
        }
        await refreshAll()
    }

    // MARK: - Lookups

    var allEpisodes: [Episode] { Array(episodeIndex.values) }

    func podcast(_ id: String) -> Podcast? { podcasts.first { $0.id == id } }
    func episode(_ id: String) -> Episode? { episodeIndex[id] }
    func episodes(for podcastID: String) -> [Episode] { episodesByPodcast[podcastID] ?? [] }
    func isSubscribed(_ feedURL: String) -> Bool { podcasts.contains { $0.feedURL == feedURL } }
    func isPlayed(_ ep: Episode) -> Bool { played.contains(ep.id) }
    func position(of ep: Episode) -> Double { positions[ep.id] ?? 0 }
    var queuedEpisodes: [Episode] { queue.compactMap { episodeIndex[$0] } }

    /// Latest stories from the ChronLaw "Breaking News" feeds, without duplicate headlines.
    var breakingNews: [Episode] {
        let ids = Set(podcasts.filter { $0.directoryCategory == ChronLawDirectory.starterCategory }.map(\.id))
        var seen = Set<String>()
        return ids.flatMap { episodes(for: $0) }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .filter { seen.insert($0.title.lowercased()).inserted }
            .prefix(40).map { $0 }
    }

    /// Newest unplayed podcast episodes (items with audio or video) across all subscriptions.
    var newEpisodes: [Episode] {
        allEpisodes.filter { $0.hasMedia && !played.contains($0.id) }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .prefix(30).map { $0 }
    }

    /// Newest stories from the other ChronLaw topics the user picked.
    var topicNews: [Episode] {
        let ids = Set(podcasts.filter {
            $0.directoryCategory != nil && $0.directoryCategory != ChronLawDirectory.starterCategory
        }.map(\.id))
        return ids.flatMap { episodes(for: $0) }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .prefix(40).map { $0 }
    }

    // MARK: - ChronLaw directory

    private func loadDirectoryFromDisk() {
        if let data = try? Data(contentsOf: directoryCacheURL), let outlines = try? OPMLParser.parse(data: data),
           !outlines.isEmpty {
            directory = ChronLawDirectory.categories(from: outlines)
            directorySource = "chronlaw.com (saved copy)"
            return
        }
        if let url = Bundle.main.url(forResource: "chronlaw", withExtension: "opml"),
           let data = try? Data(contentsOf: url), let outlines = try? OPMLParser.parse(data: data) {
            directory = ChronLawDirectory.categories(from: outlines)
            directorySource = "built-in list"
        }
    }

    /// Checks chronlaw.com for a newer topic list. Keeps the current one if the site has none.
    func updateDirectoryFromWeb() async {
        var req = URLRequest(url: ChronLawDirectory.remoteURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let outlines = try? OPMLParser.parse(data: data), !outlines.isEmpty else { return }
        directory = ChronLawDirectory.categories(from: outlines)
        directorySource = "chronlaw.com"
        try? data.write(to: directoryCacheURL, options: .atomic)
    }

    /// Feed URLs from the directory the user is currently subscribed to.
    var subscribedDirectoryURLs: Set<String> {
        Set(podcasts.map(\.feedURL)).intersection(directory.flatMap { $0.feeds.map(\.url) })
    }

    /// Applies the choices from the ChronLaw Topics screen.
    func applyTopicSelection(_ selected: Set<String>) async {
        let all = directory.flatMap(\.feeds)
        let current = subscribedDirectoryURLs
        let toRemove = current.subtracting(selected)
        let toAdd = all.filter { selected.contains($0.url) && !current.contains($0.url) }
        for url in toRemove { unsubscribe(url) }
        await subscribe(directoryFeeds: toAdd)
    }

    private func subscribe(directoryFeeds feeds: [DirectoryFeed]) async {
        var added: [Podcast] = []
        for f in feeds where !isSubscribed(f.url) {
            let p = Podcast(feedURL: f.url, title: f.title, summary: f.detail, directoryCategory: f.category)
            podcasts.append(p)
            added.append(p)
        }
        sortPodcasts()
        scheduleSave()
        await refresh(added)
    }

    // MARK: - Subscribing

    /// Subscribes to a feed address typed by the user or chosen from search results.
    @discardableResult
    func subscribe(url input: String, title: String? = nil) async throws -> Podcast {
        let url = FeedFetcher.normalize(input)
        if let existing = podcast(url) { return existing }
        let parsed = try await FeedFetcher.fetch(url)
        var p = Podcast(feedURL: url, title: title ?? parsed.title)
        apply(parsed, to: &p, keepTitle: title != nil)
        podcasts.append(p)
        sortPodcasts()
        merge(parsed.episodes, into: p)
        scheduleSave()
        return p
    }

    /// Subscribes using a feed that was already downloaded for the preview screen.
    @discardableResult
    func subscribe(url input: String, parsed: ParsedFeed) -> Podcast {
        let url = FeedFetcher.normalize(input)
        if let existing = podcast(url) { return existing }
        var p = Podcast(feedURL: url, title: parsed.title)
        apply(parsed, to: &p, keepTitle: false)
        p.lastRefreshed = Date()
        podcasts.append(p)
        sortPodcasts()
        merge(parsed.episodes, into: p)
        scheduleSave()
        return p
    }

    func unsubscribe(_ feedURL: String) {
        podcasts.removeAll { $0.feedURL == feedURL }
        let removed = Set((episodesByPodcast[feedURL] ?? []).map(\.id))
        episodesByPodcast[feedURL] = nil
        queue.removeAll { removed.contains($0) }
        autoDownload.remove(feedURL)
        scheduleSave()
    }

    /// Imports an OPML file. Returns how many new subscriptions were added.
    func importOPML(_ data: Data) async throws -> Int {
        let outlines = try OPMLParser.parse(data: data)
        var newOnes: [Podcast] = []
        func walk(_ items: [OPMLOutline], folder: String?) {
            for o in items {
                if let xml = o.xmlURL {
                    let url = FeedFetcher.normalize(xml)
                    if !isSubscribed(url) && !newOnes.contains(where: { $0.feedURL == url }) {
                        let category = directory.contains { $0.feeds.contains { $0.url == url } } ? folder : nil
                        newOnes.append(Podcast(feedURL: url, title: o.title.isEmpty ? url : o.title,
                                               directoryCategory: category))
                    }
                }
                walk(o.children, folder: o.isFeed ? folder : o.title)
            }
        }
        walk(outlines, folder: nil)
        podcasts += newOnes
        sortPodcasts()
        scheduleSave()
        await refresh(newOnes)
        return newOnes.count
    }

    func exportOPML() -> URL? {
        let xml = OPMLWriter.export(podcasts)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChronPod-subscriptions.opml")
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    // MARK: - Refreshing

    func refreshAll() async {
        await refresh(podcasts)
    }

    /// Refreshes feeds, six at a time.
    func refresh(_ list: [Podcast]) async {
        let urls = list.map(\.feedURL).filter { !refreshing.contains($0) }
        guard !urls.isEmpty else { return }
        refreshing.formUnion(urls)
        var fresh: [Episode] = []
        var index = 0
        while index < urls.count {
            let batch = Array(urls[index..<min(index + 6, urls.count)])
            index += batch.count
            let results = await withTaskGroup(of: (String, Result<ParsedFeed, Error>).self) { group in
                for url in batch {
                    group.addTask {
                        do { return (url, .success(try await FeedFetcher.fetch(url))) }
                        catch { return (url, .failure(error)) }
                    }
                }
                var out: [(String, Result<ParsedFeed, Error>)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (url, result) in results {
                refreshing.remove(url)
                guard let i = podcasts.firstIndex(where: { $0.feedURL == url }) else { continue }
                switch result {
                case .success(let parsed):
                    var p = podcasts[i]
                    apply(parsed, to: &p, keepTitle: p.directoryCategory != nil)
                    p.lastRefreshed = Date()
                    p.lastError = nil
                    podcasts[i] = p
                    let hadEpisodes = !(episodesByPodcast[p.id] ?? []).isEmpty
                    let new = merge(parsed.episodes, into: p)
                    // Only episodes that appeared since the last refresh, never a whole back catalog.
                    if hadEpisodes && autoDownload.contains(p.id) {
                        fresh += new.filter { $0.hasMedia && !played.contains($0.id) }
                    }
                case .failure(let error):
                    podcasts[i].lastError = error.localizedDescription
                }
            }
        }
        refreshing.subtract(urls)
        scheduleSave()
        if !fresh.isEmpty { onNewEpisodes?(fresh) }
    }

    func refresh(_ podcast: Podcast) async {
        await refresh([podcast])
    }

    private func apply(_ parsed: ParsedFeed, to p: inout Podcast, keepTitle: Bool) {
        if !keepTitle { p.title = parsed.title }
        p.author = parsed.author ?? p.author
        if p.directoryCategory == nil { p.summary = parsed.summary ?? p.summary }
        // ChronLaw topics show the ChronPod newspaper symbol rather than Google News' logo.
        p.imageURL = p.directoryCategory == nil ? (parsed.imageURL ?? p.imageURL) : nil
        p.link = parsed.link ?? p.link
    }

    /// Stores the feed's episodes; returns the ones that were not known before.
    @discardableResult
    private func merge(_ fresh: [Episode], into p: Podcast) -> [Episode] {
        let old = episodesByPodcast[p.id] ?? []
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var merged: [Episode] = []
        var seen = Set<String>()
        for var e in fresh where seen.insert(e.id).inserted {
            if let prev = oldByID[e.id] { e.resolvedLink = prev.resolvedLink }
            merged.append(e)
        }
        merged += old.filter { !seen.contains($0.id) }
        merged.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        let limit = p.directoryCategory != nil ? newsLimit : podcastLimit
        if merged.count > limit {
            // Never drop episodes that are queued.
            let keep = Set(queue)
            merged = Array(merged.prefix(limit)) + merged.dropFirst(limit).filter { keep.contains($0.id) }
        }
        episodesByPodcast[p.id] = merged
        return fresh.filter { oldByID[$0.id] == nil }
    }

    private func sortPodcasts() {
        podcasts.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Articles

    /// The address to open for "Read full story", resolving Google News redirects first.
    func articleURL(for ep: Episode) async -> URL? {
        if let r = ep.resolvedLink { return URL(string: r) }
        guard let link = ep.link ?? HTMLText.links(in: ep.summary).first else { return nil }
        if GoogleNews.isGoogleLink(link), let direct = await GoogleLinkResolver.shared.resolve(link) {
            updateEpisode(ep.id) { $0.resolvedLink = direct }
            return URL(string: direct)
        }
        return URL(string: link)
    }

    private func updateEpisode(_ id: String, _ change: (inout Episode) -> Void) {
        guard let ep = episodeIndex[id], var list = episodesByPodcast[ep.podcastID],
              let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        episodesByPodcast[ep.podcastID] = list
        scheduleSave()
    }

    // MARK: - Queue and playback state

    func enqueue(_ ep: Episode, next: Bool = false) {
        queue.removeAll { $0 == ep.id }
        if next { queue.insert(ep.id, at: 0) } else { queue.append(ep.id) }
        scheduleSave()
    }

    func dequeue(_ id: String) {
        queue.removeAll { $0 == id }
        scheduleSave()
    }

    func moveQueue(from: IndexSet, to: Int) {
        queue.move(fromOffsets: from, toOffset: to)
        scheduleSave()
    }

    func isQueued(_ ep: Episode) -> Bool { queue.contains(ep.id) }

    func savePosition(_ seconds: Double, for id: String) {
        positions[id] = seconds
        scheduleSave()
    }

    func setPlayed(_ ep: Episode, _ value: Bool) {
        if value {
            played.insert(ep.id)
            positions[ep.id] = nil
        } else {
            played.remove(ep.id)
        }
        scheduleSave()
    }

    func isFavorite(_ ep: Episode) -> Bool { favorites.contains(ep.id) }

    func toggleFavorite(_ ep: Episode) {
        if favorites.contains(ep.id) { favorites.remove(ep.id) } else { favorites.insert(ep.id) }
        scheduleSave()
    }

    func isAutoDownload(_ podcastID: String) -> Bool { autoDownload.contains(podcastID) }

    func setAutoDownload(_ podcastID: String, _ on: Bool) {
        if on { autoDownload.insert(podcastID) } else { autoDownload.remove(podcastID) }
        scheduleSave()
    }

    func markAllPlayed(_ podcastID: String) {
        for e in episodes(for: podcastID) {
            played.insert(e.id)
            positions[e.id] = nil
        }
        scheduleSave()
    }

    /// Called when an episode finishes: mark it played, take it off the queue, return what plays next.
    func finished(_ id: String) -> Episode? {
        played.insert(id)
        positions[id] = nil
        queue.removeAll { $0 == id }
        scheduleSave()
        return queuedEpisodes.first
    }

    // MARK: - Persistence

    private func rebuildIndex() {
        var idx: [String: Episode] = [:]
        for list in episodesByPodcast.values {
            for e in list { idx[e.id] = e }
        }
        episodeIndex = idx
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(State.self, from: data) else { return }
        podcasts = s.podcasts
        episodesByPodcast = s.episodes
        queue = s.queue
        positions = s.positions
        played = s.played
        starterSubscribed = s.starterSubscribed
        favorites = s.favorites
        autoDownload = s.autoDownload
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        var s = State()
        s.podcasts = podcasts
        s.episodes = episodesByPodcast
        s.queue = queue
        s.positions = positions
        s.played = played
        s.starterSubscribed = starterSubscribed
        s.favorites = favorites
        s.autoDownload = autoDownload
        let url = stateURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(s) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
