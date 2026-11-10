import SwiftUI
import SafariServices
import ChronPodCore

/// Square cover art with a placeholder (newspaper for news feeds, microphone for podcasts).
struct ArtworkView: View {
    let url: String?
    var isNews = false
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16).fill(isNews ? Theme.accent : Theme.navy)
            Image(systemName: isNews ? "newspaper" : "mic.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(Theme.gold)
        }
    }
}

enum Format {
    static func duration(_ seconds: Double?) -> String? {
        guard let s = seconds, s > 0, s.isFinite else { return nil }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func date(_ d: Date?) -> String? {
        guard let d else { return nil }
        if abs(d.timeIntervalSinceNow) < 7 * 24 * 3600 {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: d, relativeTo: Date())
        }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// One row in an episode or news list.
struct EpisodeRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    let episode: Episode
    var showPodcastTitle = true

    var body: some View {
        let podcast = library.podcast(episode.podcastID)
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(url: episode.imageURL ?? podcast?.imageURL, isNews: !episode.hasMedia, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.subheadline.weight(library.isPlayed(episode) ? .regular : .semibold))
                    .foregroundStyle(library.isPlayed(episode) ? .secondary : .primary)
                    .lineLimit(3)
                Text(subtitle(podcast))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if episode.hasMedia, let p = progressFraction {
                    ProgressView(value: p).tint(Theme.accent).frame(maxWidth: 140)
                }
            }
            Spacer(minLength: 4)
            if episode.hasMedia {
                VStack(spacing: 6) {
                    Button {
                        if player.current?.id == episode.id { player.togglePlayPause() } else { player.play(episode) }
                    } label: {
                        Image(systemName: isCurrentAndPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    statusIcon
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var isCurrentAndPlaying: Bool { player.current?.id == episode.id && player.isPlaying }

    private var progressFraction: Double? {
        let pos = library.position(of: episode)
        guard pos > 0, let d = episode.duration, d > 0 else { return nil }
        return min(1, pos / d)
    }

    @ViewBuilder private var statusIcon: some View {
        if downloads.isDownloading(episode) {
            ProgressView().controlSize(.mini)
        } else if downloads.isDownloaded(episode) {
            Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(.secondary)
        } else if library.isQueued(episode) {
            Image(systemName: "list.bullet").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ podcast: Podcast?) -> String {
        var parts: [String] = []
        if let source = episode.sourceName { parts.append(source) }
        else if showPodcastTitle, let t = podcast?.title { parts.append(t) }
        if let d = Format.date(episode.pubDate) { parts.append(d) }
        if let dur = Format.duration(episode.duration) { parts.append(dur) }
        return parts.joined(separator: " · ")
    }
}

/// A list row that opens podcast episodes in the app, but sends news headlines straight to the
/// publisher's own website. ChronPod never shows the text of news articles itself: like the ChronLaw
/// web pages, it lists headlines by topic and the reader goes to the original source to read the story.
struct EpisodeLink: View {
    @EnvironmentObject private var library: LibraryStore
    let episode: Episode
    var showPodcastTitle = true
    @State private var web: WebLink?
    @State private var opening = false

    var body: some View {
        if episode.hasMedia {
            NavigationLink(value: episode) { EpisodeRow(episode: episode, showPodcastTitle: showPodcastTitle) }
        } else {
            Button {
                guard !opening else { return }
                opening = true
                Task {
                    if let url = await library.articleURL(for: episode) {
                        web = WebLink(url: url)
                    } else {
                        library.message = "This headline has no link to its source."
                    }
                    opening = false
                }
            } label: {
                HStack {
                    EpisodeRow(episode: episode, showPodcastTitle: showPodcastTitle)
                    if opening {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.primary)
            .sheet(item: $web) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
        }
    }
}

/// Compact player shown above the tab bar.
struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        if let ep = player.current {
            VStack(spacing: 0) {
                if player.duration > 0 {
                    ProgressView(value: min(1, player.position / player.duration)).tint(Theme.accent)
                }
                HStack(spacing: 12) {
                    ArtworkView(url: ep.imageURL ?? library.podcast(ep.podcastID)?.imageURL, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ep.title).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(library.podcast(ep.podcastID)?.title ?? "")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { player.skip(by: -player.skipBack) } label: {
                        Image(systemName: player.skipBackSymbol).font(.title3)
                    }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                    Button { player.skip(by: player.skipForward) } label: {
                        Image(systemName: player.skipForwardSymbol).font(.title3)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture { player.showNowPlaying = true }
        }
    }
}

/// In-app browser for full news stories.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// A URL that can drive `.sheet(item:)`.
struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
