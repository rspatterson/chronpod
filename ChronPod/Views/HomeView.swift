import SwiftUI
import ChronPodCore

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showTopics = ScreenshotMode.screen == "topics"
    @State private var showAdd = ScreenshotMode.screen == "add"
    @AppStorage(DiscoverPrefs.showOnHomeKey) private var showDiscover = true
    @State private var screenshotArticle: WebLink?

    var body: some View {
        List {
            Section {
                Button {
                    showTopics = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.accent)
                            Image(systemName: "building.columns.fill").foregroundStyle(Theme.gold).font(.title3)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ChronLaw Topics").font(.headline).foregroundStyle(.primary)
                            Text("Choose legal news topics to follow (\(library.subscribedDirectoryURLs.count) selected)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }

            Section {
                if library.breakingNews.isEmpty {
                    emptyRow(library.refreshing.isEmpty ? "No stories yet. Pull down to refresh."
                                                        : "Loading the latest stories…")
                } else {
                    ForEach(library.breakingNews) { ep in
                        EpisodeLink(episode: ep)
                    }
                }
            } header: {
                Label("ChronLaw Breaking News", systemImage: "bolt.fill")
            }

            if !library.topicNews.isEmpty {
                Section {
                    ForEach(library.topicNews) { ep in
                        EpisodeLink(episode: ep)
                    }
                } header: {
                    Label("Your ChronLaw Topics", systemImage: "newspaper")
                }
            }

            if showDiscover {
                DiscoverHomeSection { showAdd = true }
            }

            Section {
                if library.newEpisodes.isEmpty {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Find podcasts to subscribe to", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(library.newEpisodes) { ep in
                        EpisodeLink(episode: ep)
                    }
                }
            } header: {
                Label("New Podcast Episodes", systemImage: "mic")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("ChronPod")
        .refreshable { await library.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !library.refreshing.isEmpty { ProgressView() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add podcast")
            }
        }
        .sheet(isPresented: $showTopics) { TopicPickerView() }
        .sheet(isPresented: $showAdd) { AddPodcastView() }
        .sheet(item: $screenshotArticle) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .task {
            // Used only by the GitHub build's screenshots: open the newest headline at its source.
            guard ScreenshotMode.screen == "article" else { return }
            for _ in 0..<60 where library.breakingNews.isEmpty {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if let first = library.breakingNews.first, let url = await library.articleURL(for: first) {
                screenshotArticle = WebLink(url: url)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }
}

/// Pick ChronLaw topics with checkboxes, like AntennaPod's OPML import screen.
struct TopicPickerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var loaded = false

    private var categories: [DirectoryCategory] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return library.directory }
        return library.directory.compactMap { cat in
            if cat.title.lowercased().contains(q) { return cat }
            let feeds = cat.feeds.filter {
                $0.title.lowercased().contains(q) || ($0.detail?.lowercased().contains(q) ?? false)
            }
            return feeds.isEmpty ? nil : DirectoryCategory(title: cat.title, feeds: feeds)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Check the topics you want to follow. Breaking News is selected for you to start. Topics come from \(library.directorySource == "built-in list" ? "the list built into the app" : library.directorySource).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(categories) { cat in
                    Section {
                        ForEach(cat.feeds) { feed in
                            Button { toggle(feed.url) } label: { row(feed) }
                                .tint(.primary)
                        }
                    } header: {
                        HStack {
                            Text(cat.title)
                            Spacer()
                            let all = cat.feeds.allSatisfy { selected.contains($0.url) }
                            Button(all ? "None" : "All") {
                                for f in cat.feeds {
                                    if all { selected.remove(f.url) } else { selected.insert(f.url) }
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search topics")
            .navigationTitle("ChronLaw Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") { selected = Set(library.directory.flatMap { $0.feeds.map(\.url) }) }
                        Spacer()
                        Text("\(selected.count) selected").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Deselect All") { selected.removeAll() }
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                selected = library.subscribedDirectoryURLs
            }
        }
    }

    private func row(_ feed: DirectoryFeed) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected.contains(feed.url) ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(selected.contains(feed.url) ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title).foregroundStyle(.primary)
                if let d = feed.detail {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private func toggle(_ url: String) {
        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
    }

    private func save() {
        let choice = selected
        let store = library
        // New topics keep loading in the background after the screen closes.
        Task { await store.applyTopicSelection(choice) }
        dismiss()
    }
}
