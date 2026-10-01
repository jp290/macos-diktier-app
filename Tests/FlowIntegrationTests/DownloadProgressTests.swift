import Foundation
import FlowCore
import XCTest
@testable import DiktierApp

final class DownloadProgressTests: XCTestCase {
    func testDownloadReportsIntermediateByteCounts() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        let samples = ByteSamples()
        let (file, response) = try await DownloadProgress.download(from: server.url) { samples.append($0) }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: file), Data(repeating: 0x61, count: 2_097_152))
        XCTAssertTrue(samples.values.contains { $0 > 0 && $0 < 2_097_152 },
                      "Progress must update before completion; received \(samples.values)")
    }

    func testCanceledDownloadStopsWithoutReturningFile() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        let task = Task { try await DownloadProgress.download(from: server.url) { _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            let (file, _) = try await task.value
            try? FileManager.default.removeItem(at: file)
            XCTFail("Canceled download must fail")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    func testFailedHTTPResponseDoesNotReturnModelFile() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        do {
            let (file, _) = try await DownloadProgress.download(from: server.url.appendingPathComponent("error")) { _ in }
            try? FileManager.default.removeItem(at: file)
            XCTFail("HTTP failure must not become a downloaded model")
        } catch { XCTAssertEqual(error as? FlowError, .invalidDownload) }
    }

    func testAlreadyCanceledTaskDoesNotStartOrHangDownload() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DownloadProgress.download(from: server.url) { _ in }
        }
        do {
            let (file, _) = try await task.value
            try? FileManager.default.removeItem(at: file)
            XCTFail("Already canceled task must fail")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private final class ByteSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int64] = []
    func append(_ bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(bytes)
    }
    var values: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

private final class LocalDownloadServer {
    private let process = Process()
    let url: URL

    init() throws {
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", "-c", """
        import http.server, time
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_GET(self):
                if self.path.endswith('/error'):
                    self.send_response(403)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header('Content-Length', '2097152')
                self.end_headers()
                try:
                    for _ in range(64):
                        self.wfile.write(b'a' * 32768)
                        self.wfile.flush()
                        time.sleep(0.03)
                except (BrokenPipeError, ConnectionResetError): pass
        server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        print(server.server_address[1], flush=True)
        server.serve_forever()
        """]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        var port = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte.first == 10 { break }
            port.append(byte)
        }
        guard let number = String(data: port, encoding: .utf8).flatMap(Int.init),
              let address = URL(string: "http://127.0.0.1:\(number)/fixture") else {
            if process.isRunning { process.terminate() }
            throw NSError(domain: "DownloadFixture", code: 1)
        }
        url = address
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
}
