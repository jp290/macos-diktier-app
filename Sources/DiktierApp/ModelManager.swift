import Combine
import FlowCore
import Foundation

final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Int64) -> Void
    private let destination: URL
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var result: Result<(URL, URLResponse), Error>?
    private var cancelled = false

    init(destination: URL, update: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.update = update
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) { update(totalBytesWritten) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let completed: Result<(URL, URLResponse), Error>
        do {
            guard let response = downloadTask.response,
                  (response as? HTTPURLResponse)?.statusCode == 200 else { throw FlowError.invalidDownload }
            try FileManager.default.moveItem(at: location, to: destination)
            completed = .success((destination, response))
        } catch { completed = .failure(error) }
        lock.lock()
        result = completed
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let completion = continuation
        let completed = error.map { Result<(URL, URLResponse), Error>.failure($0) }
            ?? result ?? .failure(FlowError.invalidDownload)
        continuation = nil
        self.task = nil
        lock.unlock()
        completion?.resume(with: completed)
    }

    private func start(_ task: URLSessionDownloadTask,
                       continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            task.cancel()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.task = task
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let active = task
        lock.unlock()
        active?.cancel()
    }

    static func download(from url: URL, update: @escaping @Sendable (Int64) -> Void) async throws
        -> (URL, URLResponse) {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("flow-model-\(UUID())")
        let delegate = DownloadProgress(destination: destination, update: update)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let value = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.start(session.downloadTask(with: url), continuation: continuation)
                }
            } onCancel: { delegate.cancel() }
            try Task.checkCancellation()
            return value
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var verifying = false
    @Published var downloading = false
    @Published var status = ""
    @Published var revision = 0
    var task: Task<Void, Never>?
    private var downloadID: UUID?
    let root: URL

    init(root: URL) { self.root = root }
    var progress: Double { totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0 }
    var transferLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let received = formatter.string(fromByteCount: receivedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(received) von \(total)"
    }
    func modelURL(_ preset: ModelPreset) -> URL { root.appendingPathComponent(preset.filename) }
    func available(_ preset: ModelPreset) -> Bool {
        let folder = preset == .qwen ? modelURL(preset) : root
        return preset.files.allSatisfy {
            let path = folder.appendingPathComponent($0.name)
            let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return Int64(size ?? -1) == $0.bytes
        } && FileManager.default.fileExists(atPath: root.appendingPathComponent("\(preset.rawValue).verified").path)
    }

    func download(_ preset: ModelPreset) {
        guard !downloading else { return }
        let id = UUID()
        downloadID = id
        downloading = true
        receivedBytes = 0
        totalBytes = preset.bytes
        verifying = false
        status = "Sprachmodell wird geladen …"
        task = Task {
            let staging = root.appendingPathComponent("download-\(UUID())")
            defer {
                try? FileManager.default.removeItem(at: staging)
                downloading = false
                verifying = false
                downloadID = nil
                task = nil
            }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                var completed: Int64 = 0
                for file in preset.files {
                    try Task.checkCancellation()
                    let previous = completed
                    let (temporary, response) = try await DownloadProgress.download(from: file.url) { [weak self] received in
                        Task { @MainActor in
                            guard let self, self.downloadID == id, self.downloading,
                                  !self.verifying, self.task?.isCancelled != true else { return }
                            self.receivedBytes = min(self.totalBytes,
                                max(self.receivedBytes, previous + max(0, received)))
                        }
                    }
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FlowError.invalidDownload }
                    let destination = staging.appendingPathComponent(file.name)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    receivedBytes = min(totalBytes, max(receivedBytes, previous + Int64(size)))
                    verifying = true
                    status = "Download wird geprüft …"
                    try await Task.detached(priority: .utility) {
                        try ModelFile.verify(destination, expected: file)
                    }.value
                    completed += file.bytes
                    verifying = false
                    status = "Sprachmodell wird geladen …"
                }
                try Task.checkCancellation()
                if preset == .qwen {
                    let destination = modelURL(preset)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: staging, to: destination)
                } else {
                    let destination = modelURL(preset)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: staging.appendingPathComponent(preset.filename), to: destination)
                }
                try Data(preset.sha256.utf8).write(to: root.appendingPathComponent("\(preset.rawValue).verified"), options: .atomic)
                receivedBytes = totalBytes
                status = "Modell bereit. Ab jetzt funktioniert die Erkennung offline."
                revision += 1
            } catch is CancellationError { status = "Download abgebrochen." }
            catch let error as URLError where error.code == .cancelled { status = "Download abgebrochen." }
            catch { status = error.localizedDescription }
        }
    }

    func cancel() {
        task?.cancel()
        if downloading { status = "Download wird abgebrochen …" }
    }
}
