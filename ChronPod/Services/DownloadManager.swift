// ChronPod — episode downloads (AntennaPod: net/download). GPL-3.0.

import Foundation
import CryptoKit
import ChronPodCore

@MainActor
final class DownloadManager: ObservableObject {
    /// episode ID -> file name inside the Downloads folder.
    @Published private(set) var files: [String: String] = [:]
    /// episode ID -> progress 0...1 for downloads in progress.
    @Published private(set) var progress: [String: Double] = [:]
    @Published var lastError: String?

    private let folder: URL
    private let manifestKey = "downloadManifest"
    private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        folder = dir

        let saved = UserDefaults.standard.dictionary(forKey: manifestKey) as? [String: String] ?? [:]
        // Forget entries whose file has disappeared.
        files = saved.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.value).path) }
    }

    func isDownloaded(_ ep: Episode) -> Bool { files[ep.id] != nil }
    func isDownloading(_ ep: Episode) -> Bool { progress[ep.id] != nil }

    func localURL(for ep: Episode) -> URL? {
        guard let name = files[ep.id] else { return nil }
        return folder.appendingPathComponent(name)
    }

    var totalBytes: Int64 {
        files.values.reduce(0) { sum, name in
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)[.size]
                        as? NSNumber)?.int64Value ?? 0
            return sum + size
        }
    }

    func download(_ ep: Episode) {
        guard let s = ep.enclosureURL, let remote = URL(string: s), files[ep.id] == nil, tasks[ep.id] == nil else { return }
        progress[ep.id] = 0
        let name = Self.fileName(for: ep, remote: remote)
        let dest = folder.appendingPathComponent(name)
        let id = ep.id

        tasks[id] = Task { [weak self] in
            do {
                let (tmp, response) = try await URLSession.shared.download(from: remote, delegate: ProgressDelegate { [weak self] p in
                    Task { @MainActor [weak self] in
                        if self?.progress[id] != nil { self?.progress[id] = p }
                    }
                })
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                self?.finish(id, name: name)
            } catch {
                self?.fail(id, error)
            }
        }
    }

    func cancel(_ ep: Episode) {
        tasks[ep.id]?.cancel()
        tasks[ep.id] = nil
        progress[ep.id] = nil
    }

    func delete(_ ep: Episode) {
        if let name = files[ep.id] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        files[ep.id] = nil
        saveManifest()
    }

    private func finish(_ id: String, name: String) {
        tasks[id] = nil
        progress[id] = nil
        files[id] = name
        saveManifest()
    }

    private func fail(_ id: String, _ error: Error) {
        tasks[id] = nil
        progress[id] = nil
        if (error as? URLError)?.code != .cancelled && !(error is CancellationError) {
            lastError = "Download failed: \(error.localizedDescription)"
        }
    }

    private func saveManifest() {
        UserDefaults.standard.set(files, forKey: manifestKey)
    }

    private static func fileName(for ep: Episode, remote: URL) -> String {
        let hash = SHA256.hash(data: Data(ep.id.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        var ext = remote.pathExtension.lowercased()
        if ext.isEmpty || ext.count > 5 {
            ext = (ep.enclosureType?.contains("video") ?? false) ? "mp4" : "mp3"
        }
        return "\(hash).\(ext)"
    }
}

/// Reports download progress from URLSession.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void

    init(_ onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the async download(from:delegate:) call.
    }
}
