import SwiftUI
import UniformTypeIdentifiers
import ChronPodCore

struct QueueView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        List {
            if library.queuedEpisodes.isEmpty {
                Text("Your queue is empty. Use \"Add to Queue\" on any episode to line it up here; ChronPod plays the queue in order.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(library.queuedEpisodes) { ep in
                EpisodeLink(episode: ep)
            }
            .onMove { library.moveQueue(from: $0, to: $1) }
            .onDelete { offsets in
                let ids = offsets.map { library.queuedEpisodes[$0].id }
                ids.forEach { library.dequeue($0) }
            }
        }
        .navigationTitle("Queue")
        .toolbar {
            if !library.queue.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let first = library.queuedEpisodes.first { player.play(first) }
                    } label: {
                        Label("Play Queue", systemImage: "play.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager

    private var downloaded: [Episode] {
        downloads.files.keys.compactMap { library.episode($0) }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    private var inProgress: [Episode] {
        downloads.progress.keys.compactMap { library.episode($0) }
    }

    var body: some View {
        List {
            if !inProgress.isEmpty {
                Section("Downloading") {
                    ForEach(inProgress) { ep in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ep.title).font(.subheadline).lineLimit(2)
                            ProgressView(value: downloads.progress[ep.id] ?? 0).tint(Theme.accent)
                        }
                        .swipeActions {
                            Button("Cancel", role: .destructive) { downloads.cancel(ep) }
                        }
                    }
                }
            }
            Section {
                if downloaded.isEmpty {
                    Text("Downloaded episodes play without an internet connection. Tap Download on any episode.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(downloaded) { ep in
                    EpisodeLink(episode: ep)
                        .swipeActions {
                            Button(role: .destructive) { downloads.delete(ep) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("Downloaded")
            } footer: {
                if !downloaded.isEmpty { Text("Using \(Format.bytes(downloads.totalBytes))") }
            }
        }
        .navigationTitle("Downloads")
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?

    var body: some View {
        NavigationStack {
            if let ep = player.current {
                let podcast = library.podcast(ep.podcastID)
                VStack(spacing: 22) {
                    Spacer(minLength: 8)
                    ArtworkView(url: ep.imageURL ?? podcast?.imageURL, size: 260)
                        .shadow(radius: 10, y: 4)
                    VStack(spacing: 4) {
                        Text(ep.title).font(.headline).multilineTextAlignment(.center).lineLimit(3)
                        Text(podcast?.title ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 2) {
                        Slider(value: Binding(
                            get: { scrubbing ?? player.position },
                            set: { scrubbing = $0 }
                        ), in: 0...max(player.duration, max(player.position, 1)), onEditingChanged: { editing in
                            if !editing, let s = scrubbing {
                                player.seek(to: s)
                                scrubbing = nil
                            }
                        })
                        .tint(Theme.accent)
                        HStack {
                            Text(Format.duration(scrubbing ?? player.position) ?? "0:00")
                            Spacer()
                            if player.isBuffering { ProgressView().controlSize(.mini) }
                            Spacer()
                            Text("-" + (Format.duration(max(0, player.duration - (scrubbing ?? player.position))) ?? "0:00"))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 44) {
                        Button { player.skip(by: -player.skipBack) } label: {
                            Image(systemName: player.skipBackSymbol).font(.system(size: 34))
                        }
                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(Theme.accent)
                        }
                        Button { player.skip(by: player.skipForward) } label: {
                            Image(systemName: player.skipForwardSymbol).font(.system(size: 34))
                        }
                    }
                    .foregroundStyle(.primary)

                    HStack(spacing: 30) {
                        Menu {
                            ForEach(PlayerController.rates, id: \.self) { r in
                                Button { player.rate = r } label: {
                                    if r == player.rate { Label(rateText(r), systemImage: "checkmark") }
                                    else { Text(rateText(r)) }
                                }
                            }
                        } label: {
                            Label(rateText(player.rate), systemImage: "speedometer")
                        }

                        Menu {
                            Button("Off") { player.setSleepTimer(minutes: nil) }
                            ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { m in
                                Button("\(m) minutes") { player.setSleepTimer(minutes: m) }
                            }
                            Button("End of episode") { player.sleepAtEnd() }
                        } label: {
                            Label(sleepText, systemImage: "moon.zzz")
                        }

                        Button { player.stop(); dismiss() } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    }
                    .font(.subheadline)
                    Spacer()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }
                    }
                }
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "play.slash")
                    .toolbar { Button("Close") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func rateText(_ r: Float) -> String { PlayerController.rateLabel(r) }

    private var sleepText: String {
        if player.sleepAtEndOfEpisode { return "End of ep." }
        if let end = player.sleepTimerEnds {
            let mins = max(1, Int(end.timeIntervalSinceNow / 60))
            return "\(mins) min"
        }
        return "Sleep"
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var importing = false
    @State private var showTopics = false
    @State private var exportURL: URL?
    @State private var working = false
    @AppStorage("deleteAfterPlaying") private var deleteAfterPlaying = false
    @AppStorage(DiscoverPrefs.countryKey) private var country = DiscoverPrefs.defaultCountry
    @AppStorage(DiscoverPrefs.showOnHomeKey) private var showDiscover = true
    @AppStorage(DiscoverPrefs.fyydKey) private var useFyyd = true
    @AppStorage(DiscoverPrefs.podcastIndexKeyKey) private var piKey = ""
    @AppStorage(DiscoverPrefs.podcastIndexSecretKey) private var piSecret = ""

    private static let opmlType = UTType(filenameExtension: "opml") ?? .xml

    var body: some View {
        Form {
            Section {
                Button { showTopics = true } label: { Label("Choose ChronLaw Topics", systemImage: "building.columns") }
                LabeledContent("Topic list", value: library.directorySource)
                Button {
                    Task {
                        working = true
                        await library.updateDirectoryFromWeb()
                        working = false
                    }
                } label: {
                    HStack {
                        Label("Check chronlaw.com for new topics", systemImage: "arrow.clockwise")
                        if working { Spacer(); ProgressView() }
                    }
                }
            } header: {
                Text("ChronLaw")
            } footer: {
                Text("ChronPod reads its topic list from \(ChronLawDirectory.remoteURL.absoluteString) and falls back to the list built into the app.")
            }

            Section("Subscriptions") {
                Button { importing = true } label: { Label("Import OPML File", systemImage: "square.and.arrow.down") }
                if let url = exportURL {
                    ShareLink(item: url) { Label("Share Exported OPML", systemImage: "square.and.arrow.up") }
                } else {
                    Button { exportURL = library.exportOPML() } label: {
                        Label("Export Subscriptions (OPML)", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    Task { await library.refreshAll() }
                } label: { Label("Refresh All Now", systemImage: "arrow.triangle.2.circlepath") }
            }

            Section("Playback") {
                Picker("Default speed", selection: $player.rate) {
                    ForEach(PlayerController.rates, id: \.self) { r in
                        Text(PlayerController.rateLabel(r)).tag(r)
                    }
                }
                Picker("Skip back", selection: $player.skipBack) {
                    ForEach(PlayerController.skipChoices, id: \.self) { s in Text("\(Int(s)) seconds").tag(s) }
                }
                Picker("Skip forward", selection: $player.skipForward) {
                    ForEach(PlayerController.skipChoices, id: \.self) { s in Text("\(Int(s)) seconds").tag(s) }
                }
            }

            Section {
                NavigationLink { DownloadsView() } label: { Label("Downloads", systemImage: "arrow.down.circle") }
                Toggle("Delete downloads after playing", isOn: $deleteAfterPlaying)
            } header: {
                Text("Downloads")
            } footer: {
                Text("To download new episodes automatically, open a podcast and choose Auto-Download from its ••• menu.")
            }

            Section {
                Toggle("Show Discover on Home", isOn: $showDiscover)
                Picker("Top podcasts country", selection: $country) {
                    ForEach(Discovery.countries, id: \.code) { c in Text(c.name).tag(c.code) }
                }
                Toggle("Also search fyyd", isOn: $useFyyd)
            } header: {
                Text("Discover & Search")
            } footer: {
                Text("Search always includes Apple Podcasts. fyyd is a free, independent podcast directory.")
            }

            Section {
                TextField("API key", text: $piKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API secret", text: $piSecret)
                Link("Get a free key at podcastindex.org", destination: URL(string: "https://api.podcastindex.org/signup")!)
            } header: {
                Text("Podcast Index (optional)")
            } footer: {
                Text("Podcast Index is an open podcast directory. Search uses it too once you enter your own free key and secret.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                Text("ChronPod is free software under the GNU General Public License v3. It is an iPhone adaptation of AntennaPod, the open-source Android podcast app, and gratefully builds on its design and code.")
                    .font(.footnote)
                Link("ChronPod source code", destination: URL(string: "https://github.com/chronlaw/chronpod")!)
                Link("AntennaPod project", destination: URL(string: "https://github.com/AntennaPod/AntennaPod")!)
                Link("ChronLaw", destination: URL(string: "https://chronlaw.com")!)
                Text("News headlines and articles belong to their publishers. Nothing in ChronPod is legal advice; anyone with a current legal issue should consult a licensed attorney.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showTopics) { TopicPickerView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [Self.opmlType, .xml]) { result in
            guard case .success(let url) = result else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let n = try await library.importOPML(data)
                    library.message = "Imported \(n) new subscription\(n == 1 ? "" : "s")."
                } catch {
                    library.message = error.localizedDescription
                }
            }
        }
    }
}

/// Every episode across all podcasts, with filters (AntennaPod: AllEpisodesFragment).
struct EpisodesView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var filter = Filter.unplayed
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unplayed = "Unplayed", inProgress = "In Progress", downloaded = "Downloaded",
             favorites = "Favorites"
        var id: String { rawValue }
    }

    private var shown: [Episode] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return library.allEpisodes
            .filter { ep in
                guard ep.hasMedia else { return false }
                switch filter {
                case .all: break
                case .unplayed: if library.isPlayed(ep) { return false }
                case .inProgress: if library.position(of: ep) <= 0 { return false }
                case .downloaded: if !downloads.isDownloaded(ep) { return false }
                case .favorites: if !library.isFavorite(ep) { return false }
                }
                if q.isEmpty { return true }
                return ep.title.lowercased().contains(q)
                    || (library.podcast(ep.podcastID)?.title.lowercased().contains(q) ?? false)
            }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .prefix(300).map { $0 }
    }

    var body: some View {
        List {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            let list = shown
            if list.isEmpty {
                Text(emptyText).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(list) { ep in
                EpisodeLink(episode: ep)
                    .swipeActions(edge: .leading) {
                        Button {
                            if library.isQueued(ep) { library.dequeue(ep.id) } else { library.enqueue(ep) }
                        } label: {
                            Label(library.isQueued(ep) ? "Unqueue" : "Queue", systemImage: "text.badge.plus")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            library.setPlayed(ep, !library.isPlayed(ep))
                        } label: {
                            Label(library.isPlayed(ep) ? "Unplayed" : "Played", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                        Button {
                            library.toggleFavorite(ep)
                        } label: {
                            Label("Favorite", systemImage: library.isFavorite(ep) ? "star.slash" : "star")
                        }
                        .tint(.orange)
                    }
            }
        }
        .navigationTitle("Episodes")
        .searchable(text: $search, prompt: "Search episodes")
        .refreshable { await library.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    private var emptyText: String {
        switch filter {
        case .all: return "No podcast episodes yet. Subscribe to podcasts with the + button on Home."
        case .unplayed: return "You're all caught up."
        case .inProgress: return "Episodes you have started appear here."
        case .downloaded: return "Downloaded episodes appear here."
        case .favorites: return "Swipe left on an episode and tap Favorite to keep it here."
        }
    }
}
