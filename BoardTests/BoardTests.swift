import Foundation
import Testing
@testable import Board

@Suite("Server URL validation")
struct ServerURLValidationTests {
    @Test(
        "Accepted server addresses",
        arguments: [
            "http://10.0.0.5:8787",
            "http://172.31.4.9:8787",
            "http://192.168.50.20:8787",
            "http://100.100.20.30:8787",
            "http://board.example.ts.net:8787",
            "https://board.example.com"
        ]
    )
    func acceptsAllowedAddress(_ value: String) throws {
        let url = try ServerURLValidator.validatedURL(from: value)
        #expect(url.host() != nil)
    }

    @Test(
        "Rejected cleartext public addresses",
        arguments: [
            "http://8.8.8.8:8787",
            "http://example.com:8787",
            "http://localhost:8787",
            "http://board.example.ts.net:8787/v1"
        ]
    )
    func rejectsUnsafeAddress(_ value: String) {
        #expect(throws: ServerURLValidationError.self) {
            try ServerURLValidator.validatedURL(from: value)
        }
    }
}

@Suite("OpenAPI decoding")
struct APIDecodingTests {
    @Test("Card page keeps camelCase and ISO-8601 fields")
    func decodesCardPage() throws {
        let data = try #require(
            """
            {
              "items": [{
                "number": 42,
                "title": "Ship the client",
                "body": "Match the server contract.",
                "column": "board:review",
                "labels": ["board:review"],
                "url": "https://github.com/example-user/board-api/issues/42",
                "createdAt": "2026-08-22T01:02:03Z",
                "updatedAt": "2026-08-22T02:03:04.123Z"
              }],
              "page": 1,
              "perPage": 50,
              "hasMore": false
            }
            """.data(using: .utf8)
        )
        let page = try BoardJSON.decoder().decode(CardPage.self, from: data)
        #expect(page.items.first?.column == .review)
        #expect(page.items.first?.number == 42)
        #expect(page.perPage == 50)
    }

    @Test("Overview keeps repository identity and completeness")
    func decodesOverviewPage() throws {
        let data = try #require(
            """
            {
              "items": [{
                "repo": "other-org/operations",
                "card": {
                  "number": 7,
                  "title": "Repair the production deployment",
                  "body": "Restore the service.",
                  "column": "board:running",
                  "labels": ["board:running", "agent:codex"],
                  "url": "https://github.com/other-org/operations/issues/7",
                  "createdAt": "2026-08-22T01:02:03Z",
                  "updatedAt": "2026-08-22T02:03:04Z"
                }
              }],
              "page": 1,
              "perPage": 50,
              "hasMore": false,
              "partial": true,
              "unavailableOwners": ["offline-org"]
            }
            """.data(using: .utf8)
        )

        let page = try BoardJSON.decoder().decode(OverviewPage.self, from: data)
        #expect(page.items.first?.repo == "other-org/operations")
        #expect(page.items.first?.card.column == .running)
        #expect(page.items.first?.id == "other-org/operations#7")
        #expect(page.partial)
        #expect(page.unavailableOwners == ["offline-org"])
    }

    @Test("Issue comments keep author, body, URL, and pagination")
    func decodesCommentPage() throws {
        let data = try #require(
            """
            {
              "items": [{
                "id": 123456789,
                "author": "example-user",
                "body": "Please fix the reconnect path.",
                "url": "https://github.com/example-user/board-api/issues/42#issuecomment-123456789",
                "createdAt": "2026-08-23T01:02:03Z",
                "updatedAt": "2026-08-23T01:03:04Z"
              }],
              "page": 1,
              "perPage": 50,
              "hasMore": false
            }
            """.data(using: .utf8)
        )

        let page = try BoardJSON.decoder().decode(CommentPage.self, from: data)
        #expect(page.items.first?.author == "example-user")
        #expect(page.items.first?.body == "Please fix the reconnect path.")
        #expect(page.items.first?.url.fragment == "issuecomment-123456789")
        #expect(!page.hasMore)
    }

    @Test("Job record decodes exact server status and prUrl")
    func decodesJobRecord() throws {
        let data = try #require(
            """
            {
              "id": "0f66c874-326b-4d23-81f8-34895e8e8ff2",
              "repo": "example-user/board-api",
              "issue": 42,
              "harness": "codex",
              "crew": ["codex", "cursor"],
              "status": "succeeded",
              "branch": "board/42-0f66c874",
              "worktree": "/home/board/work/example-user/board-api/0f66c874",
              "prUrl": "https://github.com/example-user/board-api/pull/7",
              "createdAt": "2026-08-22T01:02:03Z",
              "startedAt": "2026-08-22T01:02:04Z",
              "finishedAt": "2026-08-22T01:03:04Z",
              "error": null
            }
            """.data(using: .utf8)
        )
        var job = try BoardJSON.decoder().decode(JobRecord.self, from: data)
        #expect(job.status == .succeeded)
        #expect(job.crew == [.codex, .cursor])
        #expect(job.prURL?.path == "/example-user/board-api/pull/7")
        #expect(!job.hasUnverifiedSuccess)
        #expect(job.outcomeSummary.contains("opened a pull request"))
        job.status = .failed
        #expect(job.outcomeSummary.contains("pull request exists"))
    }

    @Test("Completed job without prUrl is explicitly unverified")
    func identifiesUnverifiedJob() {
        let job = JobRecord(
            id: UUID(),
            repo: "example-user/board-api",
            issue: 42,
            harness: .grok,
            crew: [],
            status: .succeeded,
            branch: "board/42-example",
            worktree: "/home/board/work/example",
            prURL: nil,
            createdAt: Date(),
            startedAt: Date(),
            finishedAt: Date(),
            error: nil
        )
        #expect(job.hasUnverifiedSuccess)
        #expect(job.outcomeSummary.contains("not verified"))
    }

    @Test("SSE parser ignores framing and decodes data events")
    func decodesSSEDataLine() throws {
        #expect(try SSEParser.event(from: ": keep-alive") == nil)
        let event = try #require(
            try SSEParser.event(
                from: "data: {\"timestamp\":\"2026-08-22T01:02:03Z\",\"kind\":\"status\",\"line\":\"running\"}"
            )
        )
        #expect(event.kind == .status)
        #expect(event.line == "running")
    }

    @Test("Repeated SSE chunks receive distinct local identities")
    func repeatedSSEChunksHaveDistinctIDs() throws {
        let line = "data: {\"timestamp\":\"2026-08-22T01:02:03Z\",\"kind\":\"log\",\"line\":\" the\"}"
        let first = try #require(try SSEParser.event(from: line))
        let second = try #require(try SSEParser.event(from: line))

        #expect(first.id != second.id)
        #expect(first.timestamp == second.timestamp)
        #expect(first.kind == second.kind)
        #expect(first.line == second.line)
    }
}

@Suite("Repository search")
struct RepositorySearchTests {
    @Test("Matches owner, repository, and description without case sensitivity")
    func matchesVisibleRepositoryFields() throws {
        let repo = Repo(
            nameWithOwner: "Example-Org/Operations",
            description: "Deployment control plane",
            url: try #require(URL(string: "https://github.com/Example-Org/Operations")),
            isPrivate: true
        )

        #expect(repo.matchesRepositorySearch("example-org"))
        #expect(repo.matchesRepositorySearch("OPERATIONS"))
        #expect(repo.matchesRepositorySearch("control plane"))
        #expect(repo.matchesRepositorySearch(""))
        #expect(!repo.matchesRepositorySearch("unrelated"))
    }
}

@Suite("Credential storage", .serialized)
struct CredentialStorageTests {
    @Test("Keychain round-trip stores token and server ID together")
    func keychainRoundTrip() async throws {
        let service = "com.example.board.tests.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: service)
        try await store.clear()
        defer { Task { try? await store.clear() } }

        let expected = StoredCredentials(
            token: "board_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            serverID: UUID()
        )
        try await store.save(expected)
        let loaded = try #require(try await store.load())
        #expect(loaded == expected)

        try await store.clear()
        #expect(try await store.load() == nil)
    }
}

@Suite("Offline card cache")
struct CardCacheTests {
    @Test("Card list survives a disk round-trip")
    func diskRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "board-cache-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cache = CardCache(rootURL: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let card = try sampleCard(number: 8, column: .ready)
        try await cache.save(repo: "example-user/board-api", cards: [card])
        let loaded = try #require(try await cache.load(repo: "example-user/board-api"))
        #expect(loaded.cards == [card])
        #expect(loaded.repo == "example-user/board-api")
    }

    @Test("All-repository overview survives a disk round-trip")
    func overviewDiskRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "board-overview-cache-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cache = CardCache(rootURL: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let value = RepositoryCard(repo: "other-org/operations", card: try sampleCard(number: 7, column: .running))
        try await cache.saveOverview(cards: [value])
        let loaded = try #require(try await cache.loadOverview())
        #expect(loaded.cards == [value])
    }
}

@Suite("App model")
@MainActor
struct AppModelTests {
    @Test("Pairing opens the all-repository work overview")
    func pairingLoadsOverview() async throws {
        let model = makeModel(api: MockBoardAPIClient())
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        #expect(model.phase == .linked)
        #expect(model.server?.name == "board-mock")
        #expect(model.selectedRepo == nil)
        #expect(model.overviewCards.contains { $0.repo == "example-user/board-api" && $0.card.number == 42 })
        #expect(model.overviewCards.contains { $0.repo == "other-org/operations" && $0.card.number == 7 })
    }

    @Test("Overview exposes active work from another organisation")
    func overviewShowsCrossOrganisationJob() async throws {
        let model = makeModel(api: MockBoardAPIClient())
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )

        let card = try #require(
            model.overviewCards.first { $0.repo == "other-org/operations" && $0.card.number == 7 }
        )
        let job = try #require(model.latestJob(for: card))
        #expect(job.status == .running)
        #expect(job.harness == .codex)
    }

    @Test("Partial overview keeps cards visible without a blocking notice")
    func partialOverviewKeepsCardsVisible() async throws {
        let model = makeModel(api: MockBoardAPIClient(overviewUnavailableOwners: ["offline-org"]))
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )

        #expect(!model.overviewCards.isEmpty)
        #expect(model.isOverviewPartial)
        #expect(model.overviewUnavailableOwners == ["offline-org"])
        #expect(model.notice == nil)
    }

    @Test("Concurrent overview loads make one API request")
    func concurrentOverviewLoadsCoalesce() async throws {
        let api = MockBoardAPIClient(delaysOverview: true)
        let model = makeModel(api: api)
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await api.resetOverviewRequestCount()

        let first = Task { @MainActor in await model.loadOverview() }
        try? await Task.sleep(for: .milliseconds(10))
        let second = Task { @MainActor in await model.loadOverview() }
        await first.value
        await second.value

        #expect(await api.overviewRequests() == 1)
    }

    @Test("Foreground refresh picks up cards added while the app was away")
    func foregroundRefreshLoadsNewCards() async throws {
        let api = MockBoardAPIClient()
        let model = makeModel(api: api)
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )

        let newCard = try sampleCard(number: 99, column: .ready)
        await api.insertCard(newCard, repo: "example-user/board-api")
        await model.refreshWhenActive()

        #expect(model.overviewCards.contains { $0.repo == "example-user/board-api" && $0.card.number == 99 })
    }

    @Test("Transient overview failure is retried once")
    func transientOverviewFailureRetries() async throws {
        let api = MockBoardAPIClient()
        let model = makeModel(api: api)
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await api.resetOverviewRequestCount()
        await api.failNextOverviewRequests(1)

        await model.loadOverview()

        #expect(await api.overviewRequests() == 2)
        #expect(!model.isOffline)
        #expect(model.refreshWarning == nil)
    }

    @Test("Healthy server is not labelled offline when GitHub data is delayed")
    func healthyServerDoesNotBecomeOffline() async throws {
        let api = MockBoardAPIClient()
        let model = makeModel(api: api)
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await api.failNextOverviewRequests(2)

        await model.loadOverview()

        #expect(!model.isOffline)
        #expect(model.refreshWarning?.contains("Server is online") == true)
        #expect(!model.overviewCards.isEmpty)
    }

    @Test("Failed health check marks cached cards offline")
    func failedHealthCheckUsesOfflineCache() async throws {
        let api = MockBoardAPIClient()
        let model = makeModel(api: api)
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await api.failNextOverviewRequests(2)
        await api.setHealthFailure(true)

        await model.loadOverview()

        #expect(model.isOffline)
        #expect(model.refreshWarning == nil)
        #expect(!model.overviewCards.isEmpty)
    }

    @Test("Failed optimistic move rolls the card back")
    func failedMoveRollsBack() async throws {
        let model = makeModel(api: MockBoardAPIClient(failMoves: true))
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await model.selectRepo("example-user/board-api")
        #expect(model.card(number: 42)?.column == .backlog)
        let moved = await model.moveCard(number: 42, to: .ready)
        #expect(!moved)
        #expect(model.card(number: 42)?.column == .backlog)
    }

    @Test("Posts and reloads a follow-up comment")
    func postsFollowUpComment() async throws {
        let model = makeModel(api: MockBoardAPIClient())
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await model.selectRepo("example-user/board-api")

        let posted = await model.addComment(
            number: 42,
            body: "  Please fix the reconnect path before review.  "
        )

        #expect(posted)
        #expect(model.comments(number: 42).count == 1)
        #expect(model.comments(number: 42).first?.author == "example-user")
        #expect(model.comments(number: 42).first?.body == "Please fix the reconnect path before review.")
    }

    @Test("A repository conflict returns the existing running job")
    func conflictShowsExistingJob() async throws {
        let model = makeModel(api: MockBoardAPIClient())
        _ = try await model.link(
            baseURLString: "http://192.168.50.10:8787",
            code: runtimePairCode()
        )
        await model.selectRepo("example-user/board-api")
        let first = try #require(await model.startJob(issue: 42, harness: .codex, prompt: "", crew: []))
        let second = try #require(await model.startJob(issue: 43, harness: .cursor, prompt: "", crew: []))
        #expect(first.id == second.id)
        #expect(model.notice?.title == "Repository busy")
    }

    private func makeModel(api: any BoardAPIClientProtocol) -> AppModel {
        AppModel(api: api, credentials: MemoryCredentialStore(), cache: MemoryCardCache())
    }

    private func runtimePairCode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }
}

private func sampleCard(number: Int, column: BoardColumn) throws -> Card {
    let url = try #require(URL(string: "https://github.com/example-user/board-api/issues/\(number)"))
    return Card(
        number: number,
        title: "Cached card",
        body: "Available without the server.",
        column: column,
        labels: [column.rawValue],
        url: url,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
}
