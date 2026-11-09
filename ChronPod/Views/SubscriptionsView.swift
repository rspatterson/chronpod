import SwiftUI
import ChronPodCore

struct SubscriptionsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showAdd = false
    @State private var showTopics = false
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", podcasts = "Podcasts", news = "ChronLaw News"
        var id: String { rawValue }
    }

    private var shown: [Podcast] {
        switch filter {
        case .all: return library.podcasts
        case .podcasts: return library.podcasts.filter { $0.directoryCategory == nil }
        case .news: return library.podcasts.filter { $0.directoryCategory != nil }
        }
    }

    var body: some View {
        List {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if shown.isEmpty {
                Text("No subscriptions here yet. Tap + to search for podcasts or add a feed address.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(shown) { p in
                NavigationLink(value: p) {
                    HStack(spacing: 12) {
                        ArtworkView(url: p.imageURL, isNews: p.directoryCategory != nil, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(caption(p)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let err = p.lastError {
                                Label(err, systemImage: "exclamationmark.triangle")
                                    .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                            }
                        }
                        Spacer()
                        if library.refreshing.contains(p.id) { ProgressView().controlSize(.small) }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { library.unsubscribe(p.feedURL) } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
        .refreshable { await library.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showTopics = true } label: { Label("ChronLaw Topics", systemImage: "building.columns") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add podcast")
            }
        }
        .sheet(isPresented: $showAdd) { AddPodcastView() }
        .sheet(isPresented: $showTopics) { TopicPickerView() }
    }

    private func caption(_ p: Podcast) -> String {
        let count = library.episodes(for: p.id).count
        var parts = [p.directoryCategory.map { "ChronLaw · \($0)" } ?? (p.author ?? "Podcast")]
        parts.append("\(count) item\(count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}

struct PodcastDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let podcastID: String
    @State private var confirmUnsubscribe = false

    var body: some View {
        if let p = library.podcast(podcastID) {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        ArtworkView(url: p.imageURL, isNews: p.directoryCategory != nil, size: 96)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title).font(.headline)
                            if let a = p.author { Text(a).font(.subheadline).foregroundStyle(.secondary) }
                            if let c = p.directoryCategory {
                                Text("ChronLaw topic: \(c)").font(.caption).foregroundStyle(Theme.accent)
                            }
                            if let r = p.lastRefreshed {
                                Text("Updated \(Format.date(r) ?? "")").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    let about = HTMLText.plainText(p.summary)
                    if !about.isEmpty {
                        Text(about).font(.footnote).foregroundStyle(.secondary).lineLimit(6)
                    }
                    if let err = p.lastError {
                        Label(err, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section("Episodes & Stories") {
                    let eps = library.episodes(for: p.id)
                    if eps.isEmpty {
                        Text(library.refreshing.contains(p.id) ? "Loading…" : "Nothing here yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(eps) { ep in
                        EpisodeLink(episode: ep, showPodcastTitle: false)
                    }
                }
            }
            .navigationTitle(p.title)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await library.refresh(p) }
            .toolbar {
                Menu {
                    Button { Task { await library.refresh(p) } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    if let link = p.link, let url = URL(string: link) {
                        Link(destination: url) { Label("Open Website", systemImage: "safari") }
                    }
                    ShareLink(item: p.feedURL) { Label("Share Feed Address", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmUnsubscribe = true } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .confirmationDialog("Unsubscribe from \(p.title)?", isPresented: $confirmUnsubscribe,
                                titleVisibility: .visible) {
                Button("Unsubscribe", role: .destructive) {
                    library.unsubscribe(p.feedURL)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Not subscribed", systemImage: "square.stack")
        }
    }
}

/// Search the podcast directory, or add any RSS/Atom feed by its address.
struct AddPodcastView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PodcastSearchResult] = []
    @State private var searching = false
    @State private var feedAddress = ""
    @State private var adding: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Search podcasts", text: $query)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if searching { ProgressView() }
                    }
                } header: {
                    Text("Search")
                } footer: {
                    Text("Searches Apple's public podcast directory.")
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { r in
                            HStack(spacing: 12) {
                                ArtworkView(url: r.imageURL, size: 48)
                                VStack(alignment: .leading) {
                                    Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    if let a = r.author { Text(a).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                addButton(url: r.feedURL, title: r.title)
                            }
                        }
                    }
                }

                Section {
                    TextField("https://example.com/feed.xml", text: $feedAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add Feed") { add(url: feedAddress, title: nil) }
                        .disabled(feedAddress.trimmingCharacters(in: .whitespaces).isEmpty || adding != nil)
                } header: {
                    Text("Add by address")
                } footer: {
                    Text("Any podcast or news RSS/Atom feed works, including Google News searches.")
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Add Podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func addButton(url: String, title: String) -> some View {
        if library.isSubscribed(FeedFetcher.normalize(url)) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if adding == url {
            ProgressView()
        } else {
            Button { add(url: url, title: title) } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        defer { searching = false }
        do {
            results = try await PodcastSearch.search(q)
            if results.isEmpty { error = "No podcasts found for \"\(q)\"." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add(url: String, title: String?) {
        adding = url
        error = nil
        Task {
            do {
                try await library.subscribe(url: url, title: title)
                if title == nil { feedAddress = "" }
            } catch {
                self.error = error.localizedDescription
            }
            adding = nil
        }
    }
}
