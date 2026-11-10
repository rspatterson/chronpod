// ChronPod — playback (AntennaPod: playback/service PlaybackService). GPL-3.0.

import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import ChronPodCore

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var current: Episode?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isBuffering = false
    @Published var showNowPlaying = false
    @Published private(set) var sleepTimerEnds: Date?
    @Published private(set) var sleepAtEndOfEpisode = false
    @Published var rate: Float = UserDefaults.standard.object(forKey: "playbackRate") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(rate, forKey: "playbackRate")
            if isPlaying { player.rate = rate }
            updateNowPlaying()
        }
    }

    static let rates: [Float] = [0.75, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    /// "1x", "1.5x", "1.25x"
    nonisolated static func rateLabel(_ r: Float) -> String {
        if r == r.rounded() { return String(format: "%.0fx", r) }
        if r * 10 == (r * 10).rounded() { return String(format: "%.1fx", r) }
        return String(format: "%.2fx", r)
    }
    /// Skip intervals offered in Settings (each has a matching SF Symbol, e.g. "gobackward.15").
    static let skipChoices: [Double] = [5, 10, 15, 30, 45, 60]

    @Published var skipBack: Double = PlayerController.storedSkip("skipBack", default: 10) {
        didSet {
            UserDefaults.standard.set(skipBack, forKey: "skipBack")
            MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBack)]
        }
    }
    @Published var skipForward: Double = PlayerController.storedSkip("skipForward", default: 30) {
        didSet {
            UserDefaults.standard.set(skipForward, forKey: "skipForward")
            MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [NSNumber(value: skipForward)]
        }
    }

    nonisolated private static func storedSkip(_ key: String, default value: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : value
    }

    /// "gobackward.10" / "goforward.30" for the current settings.
    var skipBackSymbol: String { "gobackward.\(Int(skipBack))" }
    var skipForwardSymbol: String { "goforward.\(Int(skipForward))" }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var lastSaved = Date.distantPast
    private var sleepTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?

    private weak var library: LibraryStore?
    private weak var downloads: DownloadManager?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
                    self?.isPlaying = status != .paused
                }
            }
        }
    }

    func attach(library: LibraryStore, downloads: DownloadManager) {
        self.library = library
        self.downloads = downloads
    }

    // MARK: - Controls

    /// Plays an episode from its saved position, from the downloaded file if there is one.
    func play(_ ep: Episode) {
        guard ep.hasMedia else { return }
        if current?.id == ep.id {
            resume()
            return
        }
        saveProgress(force: true)

        let url: URL?
        if let local = downloads?.localURL(for: ep) { url = local }
        else { url = ep.enclosureURL.flatMap(URL.init(string:)) }
        guard let url else { return }

        activateSession()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        current = ep
        duration = ep.duration ?? 0
        position = library?.position(of: ep) ?? 0
        artwork = nil
        loadArtwork(for: ep)

        if let old = endObserver { NotificationCenter.default.removeObserver(old) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.episodeEnded() }
        }

        if position > 5 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        activateSession()
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        saveProgress(force: true)
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        saveProgress(force: true)
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    func stop() {
        saveProgress(force: true)
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepAtEndOfEpisode = false
        guard let minutes else {
            sleepTimerEnds = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEnds = end
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepTimerEnds = nil
        }
    }

    func sleepAtEnd() {
        sleepTask?.cancel()
        sleepTimerEnds = nil
        sleepAtEndOfEpisode = true
    }

    // MARK: - Internals

    private func tick(_ time: CMTime) {
        guard current != nil else { return }
        let t = time.seconds
        if t.isFinite { position = t }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        saveProgress(force: false)
    }

    private func saveProgress(force: Bool) {
        guard let ep = current, let library else { return }
        guard force || Date().timeIntervalSince(lastSaved) > 5 else { return }
        lastSaved = Date()
        library.savePosition(position, for: ep.id)
        updateNowPlaying()
    }

    private func episodeEnded() {
        guard let ep = current else { return }
        let next = library?.finished(ep.id)
        if UserDefaults.standard.bool(forKey: "deleteAfterPlaying") {
            downloads?.delete(ep)
        }
        if sleepAtEndOfEpisode {
            sleepAtEndOfEpisode = false
            stop()
            return
        }
        if let next {
            current = nil
            play(next)
        } else {
            stop()
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
    }

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForward)]
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: self?.skipForward ?? 30) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBack)]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -(self?.skipBack ?? 10)) }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard let ep = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: ep.title,
            MPMediaItemPropertyArtist: library?.podcast(ep.podcastID)?.title ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for ep: Episode) {
        let urlString = ep.imageURL ?? library?.podcast(ep.podcastID)?.imageURL
        guard let s = urlString, let url = URL(string: s) else { return }
        let id = ep.id
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            guard let self, self.current?.id == id else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    /// Built outside the main actor: iOS calls the artwork closure on a background thread.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
