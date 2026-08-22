import Foundation

enum BoardColumn: String, Codable, CaseIterable, Identifiable, Sendable {
    case backlog = "board:backlog"
    case ready = "board:ready"
    case running = "board:running"
    case review = "board:review"
    case done = "board:done"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .ready: "Ready"
        case .running: "Running"
        case .review: "Review"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .backlog: "tray"
        case .ready: "checklist"
        case .running: "gearshape.2"
        case .review: "eye"
        case .done: "checkmark.circle"
        }
    }
}

enum Harness: String, Codable, CaseIterable, Identifiable, Sendable {
    case grok
    case codex
    case cursor

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .grok: "bolt"
        case .codex: "terminal"
        case .cursor: "cursorarrow.rays"
        }
    }
}

enum JobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case cancelling
    case cancelled
    case succeeded
    case failed

    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .cancelling: "Cancelling"
        case .cancelled: "Cancelled"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .running, .cancelling: true
        case .cancelled, .succeeded, .failed: false
        }
    }

    var isTerminal: Bool { !isActive }
}

struct HealthResponse: Codable, Equatable, Sendable {
    let ok: Bool
    let version: String
}

struct PairRequest: Codable, Equatable, Sendable {
    let code: String
}

struct PairResponse: Codable, Equatable, Sendable {
    let token: String
    let serverID: UUID
    let name: String
    let baseURL: URL

    enum CodingKeys: String, CodingKey {
        case token
        case serverID = "serverId"
        case name
        case baseURL = "baseUrl"
    }
}

struct ServerResponse: Codable, Equatable, Sendable {
    let name: String
    let serverID: UUID
    let version: String
    let listen: String
    let lanURL: URL
    let tailscaleURL: URL?
    let tailscaleDNS: String?
    let harnesses: [Harness]
    let ghLogin: String?

    enum CodingKeys: String, CodingKey {
        case name
        case serverID = "serverId"
        case version
        case listen
        case lanURL = "lanUrl"
        case tailscaleURL = "tailscaleUrl"
        case tailscaleDNS = "tailscaleDns"
        case harnesses
        case ghLogin
    }
}

struct Repo: Codable, Identifiable, Equatable, Hashable, Sendable {
    let nameWithOwner: String
    let description: String?
    let url: URL
    let isPrivate: Bool

    var id: String { nameWithOwner }
    var shortName: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
}

struct Card: Codable, Identifiable, Equatable, Hashable, Sendable {
    let number: Int
    var title: String
    var body: String
    var column: BoardColumn?
    var labels: [String]
    let url: URL
    let createdAt: Date
    var updatedAt: Date

    var id: Int { number }
}

struct CardPage: Codable, Equatable, Sendable {
    let items: [Card]
    let page: Int
    let perPage: Int
    let hasMore: Bool
}

struct CreateCardRequest: Codable, Equatable, Sendable {
    let repo: String
    let title: String
    let body: String
    let column: BoardColumn
}

struct MoveCardRequest: Codable, Equatable, Sendable {
    let column: BoardColumn
}

struct CreateJobRequest: Codable, Equatable, Sendable {
    let repo: String
    let issue: Int
    let harness: Harness
    let prompt: String?
    let crew: [Harness]?
}

struct JobRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let repo: String
    let issue: Int
    let harness: Harness
    let crew: [Harness]
    var status: JobStatus
    let branch: String
    let worktree: String
    var prURL: URL?
    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case id
        case repo
        case issue
        case harness
        case crew
        case status
        case branch
        case worktree
        case prURL = "prUrl"
        case createdAt
        case startedAt
        case finishedAt
        case error
    }
}

struct JobEvent: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case status
        case log
    }

    let timestamp: Date
    let kind: Kind
    let line: String

    var id: String { "\(timestamp.timeIntervalSince1970)-\(kind.rawValue)-\(line)" }
}

struct ErrorResponse: Codable, Equatable, Sendable {
    struct Body: Codable, Equatable, Sendable {
        let code: String
        let message: String
    }

    let error: Body
}
