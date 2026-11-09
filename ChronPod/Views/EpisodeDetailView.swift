import SwiftUI
import ChronPodCore

struct EpisodeDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    let episodeID: String
    @State private var web: WebLink?
    @State private var opening = false

    var body: some View {
        if let ep = library.episode(episodeID) {
            let podcast = library.podcast(ep.podcastID)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ArtworkView(url: ep.imageURL ?? podcast?.imageURL, isNews: !ep.hasMedia, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ep.title).font(.title3.weight(.semibold))
                            Text(meta(ep, podcast)).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    actions(ep)

                    if ep.hasMedia {
                        let text = HTMLText.plainText(ep.summary)
                        if !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    } else {
                        // News: headline only. The story itself is read on the publisher's website.
                        Text("ChronPod lists headlines only. Tap Read Full Article to read the story on \(ep.sourceName ?? "the publisher")'s own website.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(podcast?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu {
                    if ep.hasMedia {
                        Button { library.setPlayed(ep, !library.isPlayed(ep)) } label: {
                            Label(library.isPlayed(ep) ? "Mark as Unplayed" : "Mark as Played",
                                  systemImage: library.isPlayed(ep) ? "circle" : "checkmark.circle")
                        }
                    }
                    if let s = ep.articleLink, let url = URL(string: s) {
                        ShareLink(item: url) { Label("Share Link", systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .sheet(item: $web) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
        } else {
            ContentUnavailableView("Item no longer available", systemImage: "questionmark.square.dashed")
        }
    }

    @ViewBuilder
    private func actions(_ ep: Episode) -> some View {
        VStack(spacing: 10) {
            if ep.hasMedia {
                HStack(spacing: 10) {
                    Button {
                        if player.current?.id == ep.id { player.togglePlayPause() } else { player.play(ep) }
                        if player.current?.id == ep.id { player.showNowPlaying = true }
                    } label: {
                        Label(player.current?.id == ep.id && player.isPlaying ? "Pause" :
                                (downloads.isDownloaded(ep) ? "Play" : "Stream"),
                              systemImage: player.current?.id == ep.id && player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    downloadButton(ep)
                }
                Button {
                    if library.isQueued(ep) { library.dequeue(ep.id) } else { library.enqueue(ep) }
                } label: {
                    Label(library.isQueued(ep) ? "Remove from Queue" : "Add to Queue",
                          systemImage: library.isQueued(ep) ? "minus.circle" : "text.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if ep.link != nil || !ep.hasMedia {
                if ep.hasMedia {
                    Button { open(ep) } label: { webLabel(ep) }
                        .buttonStyle(.bordered)
                        .disabled(opening)
                } else {
                    Button { open(ep) } label: { webLabel(ep) }
                        .buttonStyle(.borderedProminent)
                        .disabled(opening)
                }
            }
        }
        .controlSize(.large)
    }

    private func webLabel(_ ep: Episode) -> some View {
        HStack {
            if opening { ProgressView().controlSize(.small) }
            Label(ep.hasMedia ? "Episode Website" : "Read Full Article", systemImage: "safari")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func downloadButton(_ ep: Episode) -> some View {
        if downloads.isDownloaded(ep) {
            Button(role: .destructive) { downloads.delete(ep) } label: {
                Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else if let p = downloads.progress[ep.id] {
            Button { downloads.cancel(ep) } label: {
                HStack {
                    ProgressView(value: p).frame(width: 40)
                    Text("Cancel")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button { downloads.download(ep) } label: {
                Label("Download", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func open(_ ep: Episode) {
        opening = true
        Task {
            if let url = await library.articleURL(for: ep) {
                web = WebLink(url: url)
            } else {
                library.message = "This item has no web link."
            }
            opening = false
        }
    }

    private func meta(_ ep: Episode, _ podcast: Podcast?) -> String {
        var parts: [String] = []
        if let s = ep.sourceName { parts.append(s) } else if let t = podcast?.title { parts.append(t) }
        if let d = ep.pubDate { parts.append(d.formatted(date: .long, time: .shortened)) }
        if let dur = Format.duration(ep.duration) { parts.append(dur) }
        if library.isPlayed(ep) { parts.append("Played") }
        return parts.joined(separator: " · ")
    }
}
