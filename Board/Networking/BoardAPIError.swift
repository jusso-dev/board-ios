import Foundation

enum BoardAPIError: LocalizedError, Sendable {
    case invalidResponse
    case missingCredentials
    case unauthorised(message: String)
    case server(statusCode: Int, code: String?, message: String)
    case decoding(message: String)
    case transport(code: URLError.Code)

    var statusCode: Int? {
        switch self {
        case .unauthorised: 401
        case .server(let statusCode, _, _): statusCode
        default: nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .missingCredentials:
            "Pair this phone with the server first."
        case .unauthorised(let message):
            message
        case .server(_, _, let message):
            message
        case .decoding:
            "The server response does not match this app."
        case .transport(let code):
            Self.transportMessage(for: code)
        }
    }

    private static func transportMessage(for code: URLError.Code) -> String {
        switch code {
        case .timedOut:
            "Connection timed out."
        case .cannotConnectToHost:
            "Nothing answered on that host and port."
        case .cannotFindHost, .dnsLookupFailed:
            "The server name could not be found."
        case .notConnectedToInternet, .networkConnectionLost:
            "The network connection is offline."
        case .appTransportSecurityRequiresSecureConnection:
            "iOS blocked that HTTP address."
        default:
            "The server could not be reached."
        }
    }
}
