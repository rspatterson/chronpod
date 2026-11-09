import SwiftUI
import ChronPodCore

struct RootView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        TabView {
            NavigationStack { HomeView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Home", systemImage: "house") }

            NavigationStack { SubscriptionsView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Subscriptions", systemImage: "square.stack") }

            NavigationStack { QueueView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Queue", systemImage: "list.bullet") }
                .badge(library.queue.count)

            NavigationStack { DownloadsView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            NavigationStack { SettingsView() }
                .withMiniPlayer()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $player.showNowPlaying) {
            NowPlayingView()
        }
        .alert("ChronPod", isPresented: Binding(
            get: { library.message != nil || downloads.lastError != nil },
            set: { if !$0 { library.message = nil; downloads.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.message ?? downloads.lastError ?? "")
        }
    }
}

extension View {
    /// Shows the mini player above the tab bar while something is loaded.
    func withMiniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar()
        }
    }

    /// Navigation targets shared by every tab.
    func withDestinations() -> some View {
        self
            .navigationDestination(for: Episode.self) { ep in
                EpisodeDetailView(episodeID: ep.id)
            }
            .navigationDestination(for: Podcast.self) { p in
                PodcastDetailView(podcastID: p.id)
            }
    }
}
