import Foundation

protocol BoardAPIClientProtocol: Sendable {
    func health(baseURL: URL) async throws -> HealthResponse
    func pair(baseURL: URL, code: String) async throws -> PairResponse
    func server(baseURL: URL) async throws -> ServerResponse
    func repos(baseURL: URL) async throws -> [Repo]
    func cards(baseURL: URL, repo: String, column: BoardColumn?, page: Int, perPage: Int) async throws -> CardPage
    func createCard(baseURL: URL, request: CreateCardRequest) async throws -> Card
    func moveCard(baseURL: URL, repo: String, number: Int, column: BoardColumn) async throws -> Card
    func card(baseURL: URL, repo: String, number: Int) async throws -> Card
    func jobs(baseURL: URL) async throws -> [JobRecord]
    func createJob(baseURL: URL, request: CreateJobRequest) async throws -> JobRecord
    func job(baseURL: URL, id: UUID) async throws -> JobRecord
    func jobEvents(baseURL: URL, id: UUID) async throws -> AsyncThrowingStream<JobEvent, any Error>
    func cancelJob(baseURL: URL, id: UUID) async throws -> JobRecord
}

enum SSEParser {
    static func event(from line: String) throws -> JobEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        do {
            return try BoardJSON.decoder().decode(JobEvent.self, from: data)
        } catch {
            throw BoardAPIError.decoding(message: error.localizedDescription)
        }
    }
}

enum BoardJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date"
            )
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

actor BoardAPIClient: BoardAPIClientProtocol {
    private let session: URLSession
    private let credentials: any CredentialStore

    init(credentials: any CredentialStore, session: URLSession? = nil) {
        self.credentials = credentials
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 120
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func health(baseURL: URL) async throws -> HealthResponse {
        try await perform(baseURL: baseURL, path: "/v1/health", authenticated: false)
    }

    func pair(baseURL: URL, code: String) async throws -> PairResponse {
        try await perform(
            baseURL: baseURL,
            path: "/v1/pair",
            method: "POST",
            body: try encode(PairRequest(code: code)),
            authenticated: false
        )
    }

    func server(baseURL: URL) async throws -> ServerResponse {
        try await perform(baseURL: baseURL, path: "/v1/server")
    }

    func repos(baseURL: URL) async throws -> [Repo] {
        try await perform(baseURL: baseURL, path: "/v1/repos")
    }

    func cards(
        baseURL: URL,
        repo: String,
        column: BoardColumn?,
        page: Int,
        perPage: Int
    ) async throws -> CardPage {
        var query = [
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "perPage", value: String(min(max(perPage, 1), 50)))
        ]
        if let column {
            query.append(URLQueryItem(name: "column", value: column.rawValue))
        }
        return try await perform(baseURL: baseURL, path: "/v1/cards", query: query)
    }

    func createCard(baseURL: URL, request: CreateCardRequest) async throws -> Card {
        try await perform(
            baseURL: baseURL,
            path: "/v1/cards",
            method: "POST",
            body: try encode(request)
        )
    }

    func moveCard(baseURL: URL, repo: String, number: Int, column: BoardColumn) async throws -> Card {
        try await perform(
            baseURL: baseURL,
            path: "/v1/cards/\(number)",
            method: "PATCH",
            query: [URLQueryItem(name: "repo", value: repo)],
            body: try encode(MoveCardRequest(column: column))
        )
    }

    func card(baseURL: URL, repo: String, number: Int) async throws -> Card {
        try await perform(
            baseURL: baseURL,
            path: "/v1/cards/\(number)",
            query: [URLQueryItem(name: "repo", value: repo)]
        )
    }

    func jobs(baseURL: URL) async throws -> [JobRecord] {
        try await perform(baseURL: baseURL, path: "/v1/jobs")
    }

    func createJob(baseURL: URL, request: CreateJobRequest) async throws -> JobRecord {
        try await perform(
            baseURL: baseURL,
            path: "/v1/jobs",
            method: "POST",
            body: try encode(request)
        )
    }

    func job(baseURL: URL, id: UUID) async throws -> JobRecord {
        try await perform(baseURL: baseURL, path: "/v1/jobs/\(id.uuidString.lowercased())")
    }

    func jobEvents(baseURL: URL, id: UUID) async throws -> AsyncThrowingStream<JobEvent, any Error> {
        let request = try await makeRequest(
            baseURL: baseURL,
            path: "/v1/jobs/\(id.uuidString.lowercased())/events",
            authenticated: true
        )

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BoardAPIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= 65_536 { break }
                }
                try await throwHTTPError(statusCode: http.statusCode, data: data)
                throw BoardAPIError.invalidResponse
            }

            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            if let event = try SSEParser.event(from: line) {
                                continuation.yield(event)
                            }
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch let error as BoardAPIError {
            throw error
        } catch let error as URLError {
            throw BoardAPIError.transport(code: error.code)
        }
    }

    func cancelJob(baseURL: URL, id: UUID) async throws -> JobRecord {
        try await perform(
            baseURL: baseURL,
            path: "/v1/jobs/\(id.uuidString.lowercased())/cancel",
            method: "POST"
        )
    }

    private func perform<Response: Decodable>(
        baseURL: URL,
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        let request = try await makeRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            query: query,
            body: body,
            authenticated: authenticated
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BoardAPIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                try await throwHTTPError(statusCode: http.statusCode, data: data)
                throw BoardAPIError.invalidResponse
            }
            do {
                return try BoardJSON.decoder().decode(Response.self, from: data)
            } catch {
                throw BoardAPIError.decoding(message: error.localizedDescription)
            }
        } catch let error as BoardAPIError {
            throw error
        } catch let error as URLError {
            throw BoardAPIError.transport(code: error.code)
        }
    }

    private func makeRequest(
        baseURL: URL,
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BoardAPIError.invalidResponse
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw BoardAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let stored = try await credentials.load() else {
                throw BoardAPIError.missingCredentials
            }
            request.setValue("Bearer \(stored.token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try BoardJSON.encoder().encode(value)
        } catch {
            throw BoardAPIError.decoding(message: error.localizedDescription)
        }
    }

    private func throwHTTPError(statusCode: Int, data: Data) async throws {
        let envelope = try? BoardJSON.decoder().decode(ErrorResponse.self, from: data)
        let message = envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        if statusCode == 401 {
            try? await credentials.clear()
            throw BoardAPIError.unauthorised(message: message)
        }
        throw BoardAPIError.server(
            statusCode: statusCode,
            code: envelope?.error.code,
            message: message
        )
    }
}
