import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case needsLink
        case linked
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    private(set) var phase: Phase = .loading
    private(set) var server: ServerResponse?
    private(set) var repos: [Repo] = []
    private(set) var selectedRepo: String?
    private(set) var cards: [Card] = []
    private(set) var overviewCards: [RepositoryCard] = []
    private(set) var commentsByCard: [String: [IssueComment]] = [:]
    private(set) var loadingCommentKeys: Set<String> = []
    private(set) var jobs: [JobRecord] = []
    private(set) var eventsByJob: [UUID: [JobEvent]] = [:]
    private(set) var isLoadingBoard = false
    private(set) var isLoadingOverview = false
    private(set) var isOverviewPartial = false
    private(set) var overviewUnavailableOwners: [String] = []
    private(set) var isOffline = false
    private(set) var refreshWarning: String?
    private(set) var currentBaseURL: URL?
    var notice: Notice?

    @ObservationIgnored private let api: any BoardAPIClientProtocol
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let cache: any CardCacheProtocol
    @ObservationIgnored private var pendingMoves: [Int: UUID] = [:]

    init(
        api: any BoardAPIClientProtocol,
        credentials: any CredentialStore,
        cache: any CardCacheProtocol
    ) {
        self.api = api
        self.credentials = credentials
        self.cache = cache
    }

    func bootstrap(baseURLString: String, resetForUITesting: Bool = false) async {
        phase = .loading
        if resetForUITesting {
            try? await credentials.clear()
            try? await cache.clear()
            UserDefaults.standard.set(true, forKey: "board.hasLaunched")
        } else if !UserDefaults.standard.bool(forKey: "board.hasLaunched") {
            try? await credentials.clear()
            UserDefaults.standard.set(true, forKey: "board.hasLaunched")
        }

        do {
            guard try await credentials.load() != nil else {
                phase = .needsLink
                return
            }
            let url = try ServerURLValidator.validatedURL(from: baseURLString)
            currentBaseURL = url
            server = try await read { try await api.server(baseURL: url) }
            phase = .linked
            await loadLinkedData()
        } catch {
            if isCancellation(error) {
                return
            } else if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else {
                phase = .needsLink
                notice = Notice(title: "Server unavailable", message: message(for: error))
            }
        }
    }

    func testConnection(baseURLString: String) async throws -> HealthResponse {
        let url = try ServerURLValidator.validatedURL(from: baseURLString)
        let health = try await read { try await api.health(baseURL: url) }
        guard health.ok else {
            throw BoardAPIError.server(statusCode: 503, code: "unhealthy", message: "The server reported that it is not healthy.")
        }
        return health
    }

    @discardableResult
    func link(baseURLString: String, code: String) async throws -> URL {
        let url = try ServerURLValidator.validatedURL(from: baseURLString)
        _ = try await read { try await api.health(baseURL: url) }
        let response = try await api.pair(baseURL: url, code: code)
        try await credentials.save(StoredCredentials(token: response.token, serverID: response.serverID))

        currentBaseURL = url
        phase = .linked
        do {
            server = try await read { try await api.server(baseURL: url) }
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
                throw error
            }
            notice = Notice(title: "Linked, but not ready", message: message(for: error))
        }
        await loadLinkedData()
        return url
    }

    func loadLinkedData() async {
        guard phase == .linked, currentBaseURL != nil else { return }
        await refreshServer(showError: false)
        await reloadBoard()
        await refreshRepositories(showError: false)
    }

    func loadRepos() async {
        let refreshed = await refreshRepositories(showError: true)
        guard phase == .linked else { return }
        if refreshed,
           let selectedRepo,
           !repos.contains(where: { $0.nameWithOwner == selectedRepo }) {
            self.selectedRepo = nil
            cards = []
        }
        await reloadBoard()
    }

    func selectRepo(_ repo: String) async {
        guard repo != selectedRepo else { return }
        selectedRepo = repo
        cards = []
        await loadBoard(repo: repo)
    }

    func selectAllRepositories() async {
        selectedRepo = nil
        cards = []
        await loadOverview()
    }

    func reloadBoard() async {
        await refreshJobs(showError: false)
        if let selectedRepo {
            await loadBoard(repo: selectedRepo)
        } else {
            await loadOverview()
        }
    }

    func refreshFromUserGesture() async {
        let refresh = Task { @MainActor [weak self] in
            await self?.reloadBoard()
        }
        await refresh.value
    }

    func refreshWhenActive() async {
        guard phase == .linked, currentBaseURL != nil else { return }
        await reloadBoard()
        guard phase == .linked, !Task.isCancelled else { return }
        await refreshRepositories(showError: false)
    }

    func loadOverview() async {
        guard let baseURL = currentBaseURL, !isLoadingOverview else { return }
        isLoadingOverview = true
        defer { isLoadingOverview = false }

        do {
            var values: [RepositoryCard] = []
            var page = 1
            var hasMore: Bool
            var partial = false
            var unavailableOwners = Set<String>()
            repeat {
                let response = try await read {
                    try await api.overview(baseURL: baseURL, page: page, perPage: 50)
                }
                values.append(contentsOf: response.items)
                hasMore = response.hasMore
                partial = partial || response.partial
                unavailableOwners.formUnion(response.unavailableOwners)
                page += 1
            } while hasMore

            guard selectedRepo == nil else { return }
            overviewCards = values.sorted { $0.card.updatedAt > $1.card.updatedAt }
            isOverviewPartial = partial
            overviewUnavailableOwners = unavailableOwners.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            isOffline = false
            refreshWarning = nil
            try? await cache.saveOverview(cards: overviewCards)
        } catch {
            if isCancellation(error) {
                return
            }
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
                return
            }
            guard let serverIsOnline = await serverIsReachable(baseURL: baseURL) else { return }
            if let cached = try? await cache.loadOverview(), selectedRepo == nil {
                overviewCards = cached.cards
                isOverviewPartial = false
                overviewUnavailableOwners = []
                isOffline = !serverIsOnline
                refreshWarning = serverIsOnline
                    ? "Update delayed. Server is online; showing the last saved cards."
                    : nil
            } else if !serverIsOnline {
                isOffline = true
                refreshWarning = nil
                notice = Notice(title: "Offline", message: "No saved cards are available yet. Try again when the server is reachable.")
            } else {
                isOffline = false
                refreshWarning = nil
                handle(error, title: "Work overview unavailable")
            }
        }
    }

    func loadBoard(repo: String) async {
        guard let baseURL = currentBaseURL else { return }
        isLoadingBoard = true
        defer { isLoadingBoard = false }

        do {
            var values: [Card] = []
            var page = 1
            var hasMore: Bool
            repeat {
                let response = try await read {
                    try await api.cards(
                        baseURL: baseURL,
                        repo: repo,
                        column: nil,
                        page: page,
                        perPage: 50
                    )
                }
                values.append(contentsOf: response.items)
                hasMore = response.hasMore
                page += 1
            } while hasMore

            guard selectedRepo == repo else { return }
            cards = values.sorted { $0.updatedAt > $1.updatedAt }
            isOffline = false
            refreshWarning = nil
            try? await cache.save(repo: repo, cards: cards)
        } catch {
            if isCancellation(error) {
                return
            }
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
                return
            }
            guard let serverIsOnline = await serverIsReachable(baseURL: baseURL) else { return }
            if let cached = try? await cache.load(repo: repo), selectedRepo == repo {
                cards = cached.cards
                isOffline = !serverIsOnline
                refreshWarning = serverIsOnline
                    ? "Update delayed. Server is online; showing the last saved cards."
                    : nil
            } else if !serverIsOnline {
                isOffline = true
                refreshWarning = nil
                notice = Notice(title: "Offline", message: "No saved cards are available yet. Try again when the server is reachable.")
            } else {
                isOffline = false
                refreshWarning = nil
                handle(error, title: "Cards unavailable")
            }
        }
    }

    func refreshJobs(showError: Bool = true) async {
        guard let baseURL = currentBaseURL else { return }
        do {
            jobs = try await read { try await api.jobs(baseURL: baseURL) }
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else if showError {
                handle(error, title: "Jobs unavailable")
            }
        }
    }

    func refreshServer(showError: Bool = true) async {
        guard let baseURL = currentBaseURL else { return }
        do {
            server = try await read { try await api.server(baseURL: baseURL) }
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else if showError {
                handle(error, title: "Server details unavailable")
            }
        }
    }

    func card(number: Int) -> Card? {
        cards.first(where: { $0.number == number })
    }

    func loadCard(number: Int) async {
        guard let baseURL = currentBaseURL, let selectedRepo else { return }
        do {
            let value = try await read {
                try await api.card(baseURL: baseURL, repo: selectedRepo, number: number)
            }
            upsert(value)
            upsertOverview(value, repo: selectedRepo)
        } catch {
            handle(error, title: "Card unavailable")
        }
    }

    func comments(number: Int) -> [IssueComment] {
        guard let selectedRepo else { return [] }
        return commentsByCard[commentKey(repo: selectedRepo, number: number), default: []]
    }

    func isLoadingComments(number: Int) -> Bool {
        guard let selectedRepo else { return false }
        return loadingCommentKeys.contains(commentKey(repo: selectedRepo, number: number))
    }

    func loadComments(number: Int) async {
        guard !isOffline, let baseURL = currentBaseURL, let repo = selectedRepo else { return }
        let key = commentKey(repo: repo, number: number)
        guard loadingCommentKeys.insert(key).inserted else { return }
        defer { loadingCommentKeys.remove(key) }

        do {
            var values: [IssueComment] = []
            var page = 1
            var hasMore: Bool
            repeat {
                let response = try await read {
                    try await api.comments(
                        baseURL: baseURL,
                        repo: repo,
                        number: number,
                        page: page,
                        perPage: 50
                    )
                }
                values.append(contentsOf: response.items)
                hasMore = response.hasMore
                page += 1
            } while hasMore

            guard selectedRepo == repo else { return }
            commentsByCard[key] = values.sorted { $0.id < $1.id }
        } catch {
            if isCancellation(error) {
                return
            }
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else {
                handle(error, title: "Comments unavailable")
            }
        }
    }

    @discardableResult
    func addComment(number: Int, body: String) async -> Bool {
        guard !isOffline else {
            notice = Notice(title: "Server required", message: "Reconnect before posting a comment.")
            return false
        }
        guard let baseURL = currentBaseURL, let repo = selectedRepo else { return false }
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty else {
            notice = Notice(title: "Comment required", message: "Describe the follow-up work or fix.")
            return false
        }
        guard cleanBody.utf8.count <= 65_536 else {
            notice = Notice(title: "Comment too long", message: "Keep the comment under 65,536 bytes.")
            return false
        }

        do {
            let value = try await api.createComment(
                baseURL: baseURL,
                repo: repo,
                number: number,
                request: CreateCommentRequest(body: cleanBody)
            )
            guard selectedRepo == repo else { return true }
            let key = commentKey(repo: repo, number: number)
            if !commentsByCard[key, default: []].contains(where: { $0.id == value.id }) {
                commentsByCard[key, default: []].append(value)
                commentsByCard[key]?.sort { $0.id < $1.id }
            }
            await loadCard(number: number)
            return true
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else {
                handle(error, title: "Comment not posted")
            }
            return false
        }
    }

    func latestJob(for card: Card) -> JobRecord? {
        guard let selectedRepo else { return nil }
        return latestJob(repo: selectedRepo, issue: card.number)
    }

    func latestJob(for card: RepositoryCard) -> JobRecord? {
        latestJob(repo: card.repo, issue: card.card.number)
    }

    func latestJob(repo: String, issue: Int) -> JobRecord? {
        return jobs
            .filter { $0.repo == repo && $0.issue == issue }
            .max { $0.createdAt < $1.createdAt }
    }

    func job(id: UUID) -> JobRecord? {
        jobs.first(where: { $0.id == id })
    }

    func activeJob(in repo: String) -> JobRecord? {
        jobs.first(where: { $0.repo == repo && $0.status.isActive })
    }

    @discardableResult
    func createCard(title: String, body: String, column: BoardColumn) async -> Bool {
        guard !isOffline else {
            notice = Notice(title: "Server required", message: "Reconnect before creating a card.")
            return false
        }
        guard let baseURL = currentBaseURL, let selectedRepo else { return false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            notice = Notice(title: "Title required", message: "Give the card a short title.")
            return false
        }

        do {
            let value = try await api.createCard(
                baseURL: baseURL,
                request: CreateCardRequest(repo: selectedRepo, title: cleanTitle, body: body, column: column)
            )
            cards.insert(value, at: 0)
            upsertOverview(value, repo: selectedRepo)
            try? await cache.save(repo: selectedRepo, cards: cards)
            if column == .ready {
                await refreshJobs(showError: false)
                await loadCard(number: value.number)
            }
            return true
        } catch {
            handle(error, title: "Card not created")
            return false
        }
    }

    @discardableResult
    func moveCard(number: Int, to column: BoardColumn) async -> Bool {
        guard !isOffline else {
            notice = Notice(title: "Server required", message: "Reconnect before moving a card.")
            return false
        }
        guard let baseURL = currentBaseURL,
              let selectedRepo,
              let index = cards.firstIndex(where: { $0.number == number }),
              cards[index].column != column else {
            return false
        }

        let previous = cards[index]
        let moveID = UUID()
        pendingMoves[number] = moveID
        cards[index].column = column
        cards[index].labels.removeAll { $0.hasPrefix("board:") }
        cards[index].labels.append(column.rawValue)

        do {
            let updated = try await api.moveCard(
                baseURL: baseURL,
                repo: selectedRepo,
                number: number,
                column: column
            )
            if pendingMoves[number] == moveID {
                upsert(updated)
                upsertOverview(updated, repo: selectedRepo)
                pendingMoves[number] = nil
                try? await cache.save(repo: selectedRepo, cards: cards)
            }
            if column == .ready {
                await refreshJobs(showError: false)
                await loadCard(number: number)
            }
            return true
        } catch {
            if pendingMoves[number] == moveID,
               let rollbackIndex = cards.firstIndex(where: { $0.number == number }) {
                cards[rollbackIndex] = previous
                pendingMoves[number] = nil
            }
            handle(error, title: "Card not moved")
            return false
        }
    }

    func startJob(
        issue: Int,
        harness: Harness,
        prompt: String,
        crew: [Harness]
    ) async -> JobRecord? {
        guard !isOffline else {
            notice = Notice(title: "Server required", message: "Reconnect before starting a job.")
            return nil
        }
        guard let baseURL = currentBaseURL, let selectedRepo else { return nil }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CreateJobRequest(
            repo: selectedRepo,
            issue: issue,
            harness: harness,
            prompt: cleanPrompt.isEmpty ? nil : cleanPrompt,
            crew: crew.isEmpty ? nil : crew
        )

        do {
            let value = try await api.createJob(baseURL: baseURL, request: request)
            upsert(value)
            return value
        } catch let error as BoardAPIError where error.statusCode == 409 {
            await refreshJobs(showError: false)
            if let existing = activeJob(in: selectedRepo) {
                notice = Notice(title: "Repository busy", message: "Showing the job already running for this repository.")
                return existing
            }
            handle(error, title: "Repository busy")
            return nil
        } catch {
            handle(error, title: "Job not started")
            return nil
        }
    }

    func watchJob(id: UUID) async {
        guard let baseURL = currentBaseURL else { return }
        do {
            let stream = try await api.jobEvents(baseURL: baseURL, id: id)
            for try await event in stream {
                var values = eventsByJob[id, default: []]
                values.append(event)
                if values.count > 500 {
                    values.removeFirst(values.count - 500)
                }
                eventsByJob[id] = values

                if event.kind == .status, let status = JobStatus(rawValue: event.line) {
                    updateJobStatus(id: id, status: status)
                    if status.isTerminal {
                        await refreshJob(id: id)
                    }
                }
            }
            await refreshJob(id: id)
        } catch is CancellationError {
            return
        } catch {
            handle(error, title: "Job stream stopped")
        }
    }

    func cancelJob(id: UUID) async {
        guard let baseURL = currentBaseURL else { return }
        do {
            let value = try await api.cancelJob(baseURL: baseURL, id: id)
            upsert(value)
        } catch {
            handle(error, title: "Job not cancelled")
        }
    }

    func changeServerURL(_ input: String) async throws -> URL {
        let url = try ServerURLValidator.validatedURL(from: input)
        _ = try await read { try await api.health(baseURL: url) }
        let details = try await read { try await api.server(baseURL: url) }
        if let stored = try await credentials.load(), stored.serverID != details.serverID {
            throw BoardAPIError.server(
                statusCode: 409,
                code: "server_mismatch",
                message: "That URL belongs to a different board server. Forget this server and pair again."
            )
        }
        currentBaseURL = url
        server = details
        isOffline = false
        refreshWarning = nil
        await loadLinkedData()
        return url
    }

    func unlink() async {
        await forgetLink(clearCache: true)
    }

    func dismissNotice() {
        notice = nil
    }

    private func refreshJob(id: UUID) async {
        guard let baseURL = currentBaseURL else { return }
        do {
            let value = try await read { try await api.job(baseURL: baseURL, id: id) }
            upsert(value)
        } catch {
            if !Task.isCancelled {
                handle(error, title: "Job unavailable")
            }
        }
    }

    private func upsert(_ card: Card) {
        if let index = cards.firstIndex(where: { $0.number == card.number }) {
            cards[index] = card
        } else {
            cards.insert(card, at: 0)
        }
    }

    private func upsertOverview(_ card: Card, repo: String) {
        let value = RepositoryCard(repo: repo, card: card)
        if let index = overviewCards.firstIndex(where: { $0.id == value.id }) {
            overviewCards[index] = value
        } else {
            overviewCards.insert(value, at: 0)
        }
        overviewCards.sort { $0.card.updatedAt > $1.card.updatedAt }
    }

    private func upsert(_ job: JobRecord) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        jobs.sort { $0.createdAt > $1.createdAt }
    }

    private func updateJobStatus(id: UUID, status: JobStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
    }

    private func forgetLink(clearCache: Bool) async {
        try? await credentials.clear()
        if clearCache {
            try? await cache.clear()
        }
        server = nil
        repos = []
        selectedRepo = nil
        cards = []
        overviewCards = []
        commentsByCard = [:]
        loadingCommentKeys = []
        jobs = []
        eventsByJob = [:]
        currentBaseURL = nil
        isOffline = false
        refreshWarning = nil
        isOverviewPartial = false
        overviewUnavailableOwners = []
        phase = .needsLink
    }

    private func handle(_ error: any Error, title: String) {
        if isCancellation(error) {
            return
        }
        if isAuthenticationError(error) {
            Task { await forgetLink(clearCache: false) }
        } else {
            notice = Notice(title: title, message: message(for: error))
        }
    }

    private func isAuthenticationError(_ error: any Error) -> Bool {
        guard let apiError = error as? BoardAPIError else { return false }
        return apiError.statusCode == 401 || {
            if case .missingCredentials = apiError { return true }
            return false
        }()
    }

    private func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        guard let apiError = error as? BoardAPIError else { return false }
        if case .transport(code: .cancelled) = apiError { return true }
        return false
    }

    private func isRetryableReadError(_ error: any Error) -> Bool {
        guard !isCancellation(error), let apiError = error as? BoardAPIError else { return false }
        switch apiError {
        case .transport(let code):
            return [
                .timedOut,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed,
                .networkConnectionLost,
                .notConnectedToInternet
            ].contains(code)
        case .server(let statusCode, _, _):
            return [408, 429, 500, 502, 503, 504].contains(statusCode)
        default:
            return false
        }
    }

    private func read<Value>(_ operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch {
            guard isRetryableReadError(error) else { throw error }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
            return try await operation()
        }
    }

    private func serverIsReachable(baseURL: URL) async -> Bool? {
        do {
            return try await read { try await api.health(baseURL: baseURL) }.ok
        } catch {
            return isCancellation(error) ? nil : false
        }
    }

    private func commentKey(repo: String, number: Int) -> String {
        "\(repo)#\(number)"
    }

    @discardableResult
    private func refreshRepositories(showError: Bool) async -> Bool {
        guard let baseURL = currentBaseURL else { return false }
        do {
            let values = try await read { try await api.repos(baseURL: baseURL) }
            repos = values.sorted {
                $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending
            }
            return true
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else if showError {
                handle(error, title: "Repositories unavailable")
            }
            return false
        }
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }
}
