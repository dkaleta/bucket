import CryptoKit
import Foundation

@MainActor final class VerbCache: VerbCaching {
    private struct Entry: Codable {
        let version: Int
        let query: String
        let result: VerbLookupResult
    }
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "KonjuGo/VerbCache", directoryHint: .isDirectory)
    }
    private func file(for query: String) -> URL {
        let hash = SHA256.hash(data: Data(query.normalizedVerbQuery.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
    func read(_ query: String) -> VerbLookupResult? {
        guard let data = try? Data(contentsOf: file(for: query)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              [7, 8].contains(entry.version), entry.query == query.normalizedVerbQuery,
              entry.result.status == .found else { return nil }
        return try? entry.result.validated()
    }
    func write(_ result: VerbLookupResult, for query: String) throws {
        guard result.status == .found else { return }
        let entry = Entry(version: 8, query: query.normalizedVerbQuery, result: try result.validated())
        let data = try JSONEncoder().encode(entry)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: query), options: .atomic)
    }
}
