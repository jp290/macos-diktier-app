import Foundation

public struct HistoryStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> [Transcript] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return Array(try JSONDecoder().decode([Transcript].self, from: Data(contentsOf: url)).prefix(50))
    }

    public func save(_ entries: [Transcript]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(Array(entries.prefix(50)))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw FlowError.storage(error.localizedDescription) }
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
