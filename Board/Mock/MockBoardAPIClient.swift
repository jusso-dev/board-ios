import Foundation

actor MockBoardAPIClient: BoardAPIClientProtocol {
    private let serverID: UUID
    private let failMoves: Bool
    private let overviewUnavailableOwners: [String]
    private let delaysOverview: Bool
    private let revealsCardOnSecondOverview: Bool
    private var cardsByRepo: [String: [Card]]
    private var overviewRequestCount = 0
    private var remainingOverviewFailures = 0
    private var healthFails = false
    private var jobValues: [JobRecord] = []
    private var eventValues: [UUID: [JobEvent]] = [:]

    init(
        failMoves: Bool = false,
        overviewUnavailableOwners: [String] = [],
        delaysOverview: Bool = false,
        revealsCardOnSecondOverview: Bool = false
    ) {
        self.serverID = Self.uuid("9a7cb1f6-37f4-4d9b-8a40-d7ab8f53a19c")
        self.failMoves = failMoves
        self.overviewUnavailableOwners = overviewUnavailableOwners
        self.delaysOverview = delaysOverview
        self.revealsCardOnSecondOverview = revealsCardOnSecondOverview
        let now = Date()
        self.cardsByRepo = [
            "jusso-dev/board-api": [
            Card(
                number: 42,
                title: "Add deployment health evidence",
                body: "Record the live health response after each homelab deployment.",
                column: .backlog,
                labels: [BoardColumn.backlog.rawValue],
                url: Self.url("https://github.com/jusso-dev/board-api/issues/42"),
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-3_600)
            ),
            Card(
                number: 43,
                title: "Tighten runner cancellation",
                body: "Prove the process group exits and the card returns to ready.",
                column: .ready,
                labels: [BoardColumn.ready.rawValue],
                url: Self.url("https://github.com/jusso-dev/board-api/issues/43"),
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-7_200)
            )
            ],
            "other-org/operations": [
                Card(
                    number: 7,
                    title: "Repair the production deployment",
                    body: "The organisation runner is applying the approved fix.",
                    column: .running,
                    labels: [BoardColumn.running.rawValue, "agent:codex"],
                    url: Self.url("https://github.com/other-org/operations/issues/7"),
                    createdAt: now.addingTimeInterval(-259_200),
                    updatedAt: now.addingTimeInterval(-300)
                )
            ]
        ]
        let runningJobID = Self.uuid("f5bf5ed8-09b8-4bd0-bcad-7a4fbcc9b4d1")
        self.jobValues = [
            JobRecord(
                id: runningJobID,
                repo: "other-org/operations",
                issue: 7,
                harness: .codex,
                crew: [.codex],
                status: .running,
                branch: "board/7-f5bf5ed8",
                worktree: "/home/board/work/other-org/operations/f5bf5ed8",
                prURL: nil,
                createdAt: now.addingTimeInterval(-600),
                startedAt: now.addingTimeInterval(-590),
                finishedAt: nil,
                error: nil
            )
        ]
        self.eventValues[runningJobID] = [
            JobEvent(timestamp: now.addingTimeInterval(-590), kind: .status, line: JobStatus.running.rawValue)
        ]
    }

    func health(baseURL: URL) throws -> HealthResponse {
        if healthFails {
            throw BoardAPIError.transport(code: .cannotConnectToHost)
        }
        return HealthResponse(ok: true, version: "0.1.0-mock")
    }

    func pair(baseURL: URL, code: String) throws -> PairResponse {
        guard code.count == 8 else {
            throw BoardAPIError.server(statusCode: 400, code: "invalid_code", message: "Enter the 8-character pair code.")
        }
        let runtimeToken = "board_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return PairResponse(token: runtimeToken, serverID: serverID, name: "board-mock", baseURL: baseURL)
    }

    func server(baseURL: URL) -> ServerResponse {
        ServerResponse(
            name: "board-mock",
            serverID: serverID,
            version: "0.1.0-mock",
            listen: "0.0.0.0:8787",
            lanURL: baseURL,
            tailscaleURL: Self.url("http://board.example.ts.net:8787"),
            tailscaleDNS: "board.example.ts.net",
            harnesses: Harness.allCases,
            ghLogin: "jusso-dev"
        )
    }

    func repos(baseURL: URL) -> [Repo] {
        [
            Repo(
                nameWithOwner: "jusso-dev/board-api",
                description: "Rust homelab board runner API",
                url: Self.url("https://github.com/jusso-dev/board-api"),
                isPrivate: false
            ),
            Repo(
                nameWithOwner: "jusso-dev/board-ios",
                description: "Native iOS client for board-api",
                url: Self.url("https://github.com/jusso-dev/board-ios"),
                isPrivate: false
            ),
            Repo(
                nameWithOwner: "other-org/operations",
                description: "Organisation operations workspace",
                url: Self.url("https://github.com/other-org/operations"),
                isPrivate: true
            )
        ]
    }

    func cards(
        baseURL: URL,
        repo: String,
        column: BoardColumn?,
        page: Int,
        perPage: Int
    ) -> CardPage {
        let filtered = cardsByRepo[repo, default: []]
            .filter { column == nil || $0.column == column }
            .sorted { $0.number > $1.number }
        let safePage = max(page, 1)
        let safePerPage = min(max(perPage, 1), 50)
        let start = (safePage - 1) * safePerPage
        guard start < filtered.count else {
            return CardPage(items: [], page: safePage, perPage: safePerPage, hasMore: false)
        }
        let end = min(start + safePerPage, filtered.count)
        return CardPage(
            items: Array(filtered[start..<end]),
            page: safePage,
            perPage: safePerPage,
            hasMore: end < filtered.count
        )
    }

    func overview(baseURL: URL, page: Int, perPage: Int) async throws -> OverviewPage {
        overviewRequestCount += 1
        if remainingOverviewFailures > 0 {
            remainingOverviewFailures -= 1
            throw BoardAPIError.server(
                statusCode: 503,
                code: "mock_overview_unavailable",
                message: "The mock overview is temporarily unavailable."
            )
        }
        if delaysOverview {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if revealsCardOnSecondOverview,
           overviewRequestCount >= 2,
           !cardsByRepo["jusso-dev/board-api", default: []].contains(where: { $0.number == 99 }) {
            let now = Date()
            cardsByRepo["jusso-dev/board-api", default: []].append(
                Card(
                    number: 99,
                    title: "Added while Board was in the background",
                    body: "Foreground activation should fetch this card without a force quit.",
                    column: .ready,
                    labels: [BoardColumn.ready.rawValue],
                    url: Self.url("https://github.com/jusso-dev/board-api/issues/99"),
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        let values = cardsByRepo
            .flatMap { repo, cards in cards.map { RepositoryCard(repo: repo, card: $0) } }
            .sorted { $0.card.updatedAt > $1.card.updatedAt }
        let safePage = max(page, 1)
        let safePerPage = min(max(perPage, 1), 50)
        let start = (safePage - 1) * safePerPage
        guard start < values.count else {
            return OverviewPage(
                items: [],
                page: safePage,
                perPage: safePerPage,
                hasMore: false,
                partial: !overviewUnavailableOwners.isEmpty,
                unavailableOwners: overviewUnavailableOwners
            )
        }
        let end = min(start + safePerPage, values.count)
        return OverviewPage(
            items: Array(values[start..<end]),
            page: safePage,
            perPage: safePerPage,
            hasMore: end < values.count,
            partial: !overviewUnavailableOwners.isEmpty,
            unavailableOwners: overviewUnavailableOwners
        )
    }

    func resetOverviewRequestCount() {
        overviewRequestCount = 0
    }

    func overviewRequests() -> Int {
        overviewRequestCount
    }

    func failNextOverviewRequests(_ count: Int) {
        remainingOverviewFailures = max(count, 0)
    }

    func setHealthFailure(_ value: Bool) {
        healthFails = value
    }

    func insertCard(_ card: Card, repo: String) {
        cardsByRepo[repo, default: []].append(card)
    }

    func createCard(baseURL: URL, request: CreateCardRequest) -> Card {
        var values = cardsByRepo[request.repo, default: []]
        let number = (values.map(\.number).max() ?? 0) + 1
        let now = Date()
        let value = Card(
            number: number,
            title: request.title,
            body: request.body,
            column: request.column,
            labels: [request.column.rawValue],
            url: Self.url("https://github.com/\(request.repo)/issues/\(number)"),
            createdAt: now,
            updatedAt: now
        )
        values.append(value)
        cardsByRepo[request.repo] = values
        return value
    }

    func moveCard(baseURL: URL, repo: String, number: Int, column: BoardColumn) throws -> Card {
        if failMoves {
            throw BoardAPIError.server(statusCode: 503, code: "mock_move_failed", message: "The mock move failed.")
        }
        var values = cardsByRepo[repo, default: []]
        guard let index = values.firstIndex(where: { $0.number == number }) else {
            throw BoardAPIError.server(statusCode: 404, code: "not_found", message: "Card not found.")
        }
        values[index].column = column
        values[index].labels.removeAll { $0.hasPrefix("board:") }
        values[index].labels.append(column.rawValue)
        values[index].updatedAt = Date()
        cardsByRepo[repo] = values
        return values[index]
    }

    func card(baseURL: URL, repo: String, number: Int) throws -> Card {
        guard let card = cardsByRepo[repo, default: []].first(where: { $0.number == number }) else {
            throw BoardAPIError.server(statusCode: 404, code: "not_found", message: "Card not found.")
        }
        return card
    }

    func jobs(baseURL: URL) -> [JobRecord] {
        jobValues.sorted { $0.createdAt > $1.createdAt }
    }

    func createJob(baseURL: URL, request: CreateJobRequest) throws -> JobRecord {
        if let existing = jobValues.first(where: { $0.repo == request.repo && $0.status.isActive }) {
            throw BoardAPIError.server(
                statusCode: 409,
                code: "repo_busy",
                message: "That repository is already running job \(existing.id.uuidString.lowercased())."
            )
        }

        let id = UUID()
        let plan = [request.harness] + (request.crew ?? [])
        let shortID = id.uuidString.lowercased().prefix(8)
        let record = JobRecord(
            id: id,
            repo: request.repo,
            issue: request.issue,
            harness: request.harness,
            crew: plan,
            status: .queued,
            branch: "board/\(request.issue)-\(shortID)",
            worktree: "/home/board/work/mock/\(id.uuidString.lowercased())",
            prURL: nil,
            createdAt: Date(),
            startedAt: nil,
            finishedAt: nil,
            error: nil
        )
        jobValues.insert(record, at: 0)
        eventValues[id] = [JobEvent(timestamp: Date(), kind: .status, line: JobStatus.queued.rawValue)]
        Task { await advanceJob(id: id, plan: plan) }
        return record
    }

    func job(baseURL: URL, id: UUID) throws -> JobRecord {
        guard let value = jobValues.first(where: { $0.id == id }) else {
            throw BoardAPIError.server(statusCode: 404, code: "not_found", message: "Job not found.")
        }
        return value
    }

    func jobEvents(baseURL: URL, id: UUID) throws -> AsyncThrowingStream<JobEvent, any Error> {
        guard eventValues[id] != nil else {
            throw BoardAPIError.server(statusCode: 404, code: "not_found", message: "Job not found.")
        }

        return AsyncThrowingStream { continuation in
            let pollingTask = Task {
                var offset = 0
                do {
                    while !Task.isCancelled {
                        let snapshot = self.eventSnapshot(id: id)
                        if offset < snapshot.count {
                            for event in snapshot[offset...] {
                                continuation.yield(event)
                            }
                            offset = snapshot.count
                        }
                        if let current = self.jobSnapshot(id: id), current.status.isTerminal {
                            continuation.finish()
                            return
                        }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in pollingTask.cancel() }
        }
    }

    func cancelJob(baseURL: URL, id: UUID) throws -> JobRecord {
        guard let index = jobValues.firstIndex(where: { $0.id == id }) else {
            throw BoardAPIError.server(statusCode: 404, code: "not_found", message: "Job not found.")
        }
        guard jobValues[index].status.isActive else {
            throw BoardAPIError.server(statusCode: 409, code: "not_running", message: "That job is no longer running.")
        }
        jobValues[index].status = .cancelled
        jobValues[index].finishedAt = Date()
        appendEvent(id: id, kind: .status, line: JobStatus.cancelled.rawValue)
        appendEvent(id: id, kind: .log, line: "Cancellation confirmed by the board runner.")
        return jobValues[index]
    }

    private func advanceJob(id: UUID, plan: [Harness]) async {
        try? await Task.sleep(for: .milliseconds(250))
        guard let index = jobValues.firstIndex(where: { $0.id == id }), jobValues[index].status == .queued else {
            return
        }
        jobValues[index].status = .running
        jobValues[index].startedAt = Date()
        appendEvent(id: id, kind: .status, line: JobStatus.running.rawValue)

        for harness in plan {
            guard let current = jobValues.first(where: { $0.id == id }), current.status == .running else {
                return
            }
            appendEvent(id: id, kind: .log, line: "Starting \(harness.rawValue) in the server worktree.")
            try? await Task.sleep(for: .milliseconds(350))
            appendEvent(id: id, kind: .log, line: "\(harness.title) is reading the issue and repository.")
        }
        appendEvent(id: id, kind: .log, line: "Runner is active. Cancel remains available.")
    }

    private func appendEvent(id: UUID, kind: JobEvent.Kind, line: String) {
        eventValues[id, default: []].append(JobEvent(timestamp: Date(), kind: kind, line: line))
    }

    private func eventSnapshot(id: UUID) -> [JobEvent] {
        eventValues[id] ?? []
    }

    private func jobSnapshot(id: UUID) -> JobRecord? {
        jobValues.first(where: { $0.id == id })
    }

    private static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid mock URL constant")
        }
        return url
    }

    private static func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid mock UUID constant")
        }
        return uuid
    }
}
