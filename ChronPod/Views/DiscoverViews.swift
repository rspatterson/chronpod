// ChronPod — Discover and podcast preview (AntennaPod: DiscoveryFragment, OnlineFeedViewActivity). GPL-3.0.

import SwiftUI
import ChronPodCore

enum DiscoverPrefs {
    static let countryKey = "discoverCountry"
    static let showOnHomeKey = "showDiscoverOnHome"
    static let fyydKey = "searchFyyd"
    static let podcastIndexKeyKey = "podcastIndexKey"
    static let podcastIndexSecretKey = "podcastIndexSecret"

    static var defaultCountry: String {
        let region = Locale.current.region?.identifier.lowercased() ?? "us"
        return Discovery.countries.contains { $0.code == region } ? region : "us"
    }
}

/// Loads Apple's top podcasts once per country/category and remembers them while the app runs.
@MainActor
final class TopChartCache {
    static let shared = TopChartCache()
    private var cache: [String: [DiscoveredPodcast]] = [:]

    func load(country: String, genre: Int) async throws -> [DiscoveredPodcast] {
        let key = "\(country)-\(genre)"
        if let hit = cache[key] { return hit }
        let list = try await Discovery.topPodcasts(country: country, genre: genre)
        cache[key] = list
        return list
    }
}

/// A row of popular podcast covers for the Home screen, as on AntennaPod's Home.
struct DiscoverHomeSection: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(DiscoverPrefs.countryKey) private var country = DiscoverPrefs.defaultCountry
    @State private var items: [DiscoveredPodcast] = []
    @State private var failed = false
    @State private var preview: DiscoveredPodcast?
    let showAll: () -> Void

    var body: some View {
        Section {
            if items.isEmpty {
                Text(failed ? "Popular podcasts could not be loaded right now." : "Loading popular podcasts…")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items.prefix(12)) { item in
                            Button { preview = item } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ArtworkView(url: item.imageURL, size: 96)
                                    Text(item.title).font(.caption2).foregroundStyle(.primary)
                                        .lineLimit(2).frame(width: 96, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Button("Discover more podcasts", action: showAll)
                .font(.footnote.weight(.semibold))
        } header: {
            Label("Discover", systemImage: "sparkles")
        }
        .task(id: country) {
            do {
                let list = try await TopChartCache.shared.load(country: country, genre: 0)
                // Like AntennaPod, leave out shows the user already follows.
                let subscribedTitles = Set(library.podcasts.map { $0.title.lowercased() })
                items = list.filter { !subscribedTitles.contains($0.title.lowercased()) }
                failed = false
            } catch {
                failed = true
            }
        }
        .sheet(item: $preview) { item in
            NavigationStack { PodcastPreviewView(item: item, closeButton: true) }
        }
    }
}

/// Apple's top podcasts by category, with a category and country picker.
struct TopPodcastsSection: View {
    @AppStorage(DiscoverPrefs.countryKey) private var country = DiscoverPrefs.defaultCountry
    @State private var genre = 0
    @State private var items: [DiscoveredPodcast] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Section {
            Picker("Category", selection: $genre) {
                ForEach(PodcastGenre.all) { g in Text(g.name).tag(g.id) }
            }
            Picker("Country", selection: $country) {
                ForEach(Discovery.countries, id: \.code) { c in Text(c.name).tag(c.code) }
            }
            if loading {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else if let error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink {
                    PodcastPreviewView(item: item)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        ArtworkView(url: item.imageURL, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if let a = item.author { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
        } header: {
            Text("Top Podcasts")
        } footer: {
            Text("Charts from Apple Podcasts. Tap a show to preview it before subscribing.")
        }
        .task(id: "\(country)-\(genre)") {
            loading = true
            error = nil
            do {
                items = try await TopChartCache.shared.load(country: country, genre: genre)
                if items.isEmpty { error = "Apple has no chart for this category in this country." }
            } catch {
                items = []
                self.error = "Top podcasts could not be loaded: \(error.localizedDescription)"
            }
            loading = false
        }
    }
}

/// Shows a podcast's details and latest episodes before subscribing (AntennaPod's feed preview).
struct PodcastPreviewView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let item: DiscoveredPodcast
    var closeButton = false

    @State private var feedURL: String?
    @State private var parsed: ParsedFeed?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(url: parsed?.imageURL ?? item.imageURL, size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parsed?.title ?? item.title).font(.headline)
                        if let a = parsed?.author ?? item.author {
                            Text(a).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Found on \(item.source)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                subscribeButton
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                let about = HTMLText.plainText(parsed?.summary)
                if !about.isEmpty {
                    Text(about).font(.footnote).foregroundStyle(.secondary).lineLimit(8)
                }
            }

            if let eps = parsed?.episodes, !eps.isEmpty {
                Section("Latest Episodes") {
                    ForEach(eps.prefix(25)) { ep in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ep.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text([Format.date(ep.pubDate), Format.duration(ep.duration)].compactMap { $0 }
                                    .joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            let notes = HTMLText.plainText(ep.summary)
                            if !notes.isEmpty {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else if parsed == nil && error == nil {
                Section { HStack { ProgressView(); Text("Loading episodes…").foregroundStyle(.secondary) } }
            }
        }
        .navigationTitle(parsed?.title ?? item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if closeButton {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var subscribeButton: some View {
        if let url = feedURL, library.isSubscribed(FeedFetcher.normalize(url)) {
            Label("Subscribed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button {
                guard let url = feedURL, let parsed else { return }
                library.subscribe(url: url, parsed: parsed)
            } label: {
                Label("Subscribe", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(parsed == nil)
        }
    }

    private func load() async {
        guard parsed == nil else { return }
        do {
            var url = item.feedURL
            if url == nil, let id = item.itunesID {
                url = try await Discovery.lookupFeedURL(itunesID: id)
            }
            guard let feed = url else { throw DiscoveryError.noFeed }
            let normalized = FeedFetcher.normalize(feed)
            feedURL = normalized
            parsed = try await FeedFetcher.fetch(normalized)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
