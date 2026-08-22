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
    private(set) var jobs: [JobRecord] = []
    private(set) var eventsByJob: [UUID: [JobEvent]] = [:]
    private(set) var isLoadingBoard = false
    private(set) var isOffline = false
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
            server = try await api.server(baseURL: url)
            phase = .linked
            await loadLinkedData()
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else {
                phase = .needsLink
                notice = Notice(title: "Server unavailable", message: message(for: error))
            }
        }
    }

    func testConnection(baseURLString: String) async throws -> HealthResponse {
        let url = try ServerURLValidator.validatedURL(from: baseURLString)
        let health = try await api.health(baseURL: url)
        guard health.ok else {
            throw BoardAPIError.server(statusCode: 503, code: "unhealthy", message: "The server reported that it is not healthy.")
        }
        return health
    }

    @discardableResult
    func link(baseURLString: String, code: String) async throws -> URL {
        let url = try ServerURLValidator.validatedURL(from: baseURLString)
        _ = try await api.health(baseURL: url)
        let response = try await api.pair(baseURL: url, code: code)
        try await credentials.save(StoredCredentials(token: response.token, serverID: response.serverID))

        currentBaseURL = url
        phase = .linked
        do {
            server = try await api.server(baseURL: url)
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
        await refreshServer()
        await refreshJobs(showError: false)
        await loadRepos()
    }

    func loadRepos() async {
        guard let baseURL = currentBaseURL else { return }
        do {
            let values = try await api.repos(baseURL: baseURL)
            repos = values.sorted { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending }
            if let selectedRepo, repos.contains(where: { $0.nameWithOwner == selectedRepo }) {
                await loadBoard(repo: selectedRepo)
            } else if let first = repos.first {
                selectedRepo = first.nameWithOwner
                await loadBoard(repo: first.nameWithOwner)
            } else {
                selectedRepo = nil
                cards = []
            }
        } catch {
            handle(error, title: "Repositories unavailable")
        }
    }

    func selectRepo(_ repo: String) async {
        guard repo != selectedRepo else { return }
        selectedRepo = repo
        cards = []
        await loadBoard(repo: repo)
    }

    func reloadBoard() async {
        guard let selectedRepo else { return }
        await refreshJobs(showError: false)
        await loadBoard(repo: selectedRepo)
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
                let response = try await api.cards(
                    baseURL: baseURL,
                    repo: repo,
                    column: nil,
                    page: page,
                    perPage: 50
                )
                values.append(contentsOf: response.items)
                hasMore = response.hasMore
                page += 1
            } while hasMore

            guard selectedRepo == repo else { return }
            cards = values.sorted { $0.updatedAt > $1.updatedAt }
            isOffline = false
            try? await cache.save(repo: repo, cards: cards)
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
                return
            }
            if let cached = try? await cache.load(repo: repo), selectedRepo == repo {
                cards = cached.cards
                isOffline = true
                notice = Notice(title: "Offline", message: "Showing cards saved on this phone. Changes need the server.")
            } else {
                handle(error, title: "Cards unavailable")
            }
        }
    }

    func refreshJobs(showError: Bool = true) async {
        guard let baseURL = currentBaseURL else { return }
        do {
            jobs = try await api.jobs(baseURL: baseURL)
        } catch {
            if isAuthenticationError(error) {
                await forgetLink(clearCache: false)
            } else if showError {
                handle(error, title: "Jobs unavailable")
            }
        }
    }

    func refreshServer() async {
        guard let baseURL = currentBaseURL else { return }
        do {
            server = try await api.server(baseURL: baseURL)
        } catch {
            handle(error, title: "Server details unavailable")
        }
    }

    func card(number: Int) -> Card? {
        cards.first(where: { $0.number == number })
    }

    func loadCard(number: Int) async {
        guard let baseURL = currentBaseURL, let selectedRepo else { return }
        do {
            let value = try await api.card(baseURL: baseURL, repo: selectedRepo, number: number)
            upsert(value)
        } catch {
            handle(error, title: "Card unavailable")
        }
    }

    func latestJob(for card: Card) -> JobRecord? {
        guard let selectedRepo else { return nil }
        return jobs
            .filter { $0.repo == selectedRepo && $0.issue == card.number }
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
            try? await cache.save(repo: selectedRepo, cards: cards)
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
                pendingMoves[number] = nil
                try? await cache.save(repo: selectedRepo, cards: cards)
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
        _ = try await api.health(baseURL: url)
        let details = try await api.server(baseURL: url)
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
            let value = try await api.job(baseURL: baseURL, id: id)
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
        jobs = []
        eventsByJob = [:]
        currentBaseURL = nil
        isOffline = false
        phase = .needsLink
    }

    private func handle(_ error: any Error, title: String) {
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

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }
}
