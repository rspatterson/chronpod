import SwiftUI
import ChronPodCore

/// When the app is started with `-screenshot <screen>` (as the GitHub build does), it opens that screen
/// so the build can photograph it. Screens: home, topics, subscriptions, queue, downloads, settings.
enum ScreenshotMode {
    static var screen: String? { UserDefaults.standard.string(forKey: "screenshot") }
}

struct RootView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var tab = RootView.initialTab

    private static var initialTab: Int {
        switch ScreenshotMode.screen {
        case "subscriptions": return 1
        case "queue": return 2
        case "downloads": return 3
        case "settings": return 4
        default: return 0
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            NavigationStack { SubscriptionsView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Subscriptions", systemImage: "square.stack") }
                .tag(1)

            NavigationStack { QueueView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Queue", systemImage: "list.bullet") }
                .badge(library.queue.count)
                .tag(2)

            NavigationStack { DownloadsView().withDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(3)

            NavigationStack { SettingsView() }
                .withMiniPlayer()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
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
