import Foundation

struct CachedBoard: Codable, Equatable, Sendable {
    let repo: String
    let cards: [Card]
    let savedAt: Date
}

protocol CardCacheProtocol: Sendable {
    func load(repo: String) async throws -> CachedBoard?
    func save(repo: String, cards: [Card]) async throws
    func clear() async throws
}

actor CardCache: CardCacheProtocol {
    private let directory: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.directory = rootURL
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.directory = caches.appending(path: "Board/CardCache", directoryHint: .isDirectory)
        }
    }

    func load(repo: String) throws -> CachedBoard? {
        let fileURL = fileURL(for: repo)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try BoardJSON.decoder().decode(CachedBoard.self, from: data)
    }

    func save(repo: String, cards: [Card]) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let entry = CachedBoard(repo: repo, cards: cards, savedAt: Date())
        let data = try BoardJSON.encoder().encode(entry)
        var destination = fileURL(for: repo)
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try destination.setResourceValues(values)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func fileURL(for repo: String) -> URL {
        let safeName = repo.replacingOccurrences(of: "/", with: "__")
        return directory.appending(path: "\(safeName).json")
    }
}

actor MemoryCardCache: CardCacheProtocol {
    private var entries: [String: CachedBoard] = [:]

    func load(repo: String) -> CachedBoard? { entries[repo] }

    func save(repo: String, cards: [Card]) {
        entries[repo] = CachedBoard(repo: repo, cards: cards, savedAt: Date())
    }

    func clear() { entries.removeAll() }
}
