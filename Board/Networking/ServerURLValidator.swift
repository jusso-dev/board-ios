import Foundation

enum ServerURLValidationError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case unsupportedScheme
    case missingHost
    case credentialsNotAllowed
    case pathNotAllowed
    case insecurePublicHost

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a complete server URL."
        case .unsupportedScheme: "Use http or https."
        case .missingHost: "The server URL needs a host."
        case .credentialsNotAllowed: "Do not put credentials in the server URL."
        case .pathNotAllowed: "Use the server root, without a path."
        case .insecurePublicHost: "HTTP is limited to private LAN, Tailscale IP, and ts.net addresses."
        }
    }
}
enum ServerURLValidator {
    static func validatedURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.url != nil else {
            throw ServerURLValidationError.invalidURL
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ServerURLValidationError.unsupportedScheme
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else {
            throw ServerURLValidationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw ServerURLValidationError.credentialsNotAllowed
        }
        guard components.path.isEmpty || components.path == "/" else {
            throw ServerURLValidationError.pathNotAllowed
        }
        guard components.query == nil, components.fragment == nil else {
            throw ServerURLValidationError.pathNotAllowed
        }

        if scheme == "http", !isAllowedCleartextHost(host) {
            throw ServerURLValidationError.insecurePublicHost
        }

        components.scheme = scheme
        components.host = host
        components.path = ""
        guard let url = components.url else {
            throw ServerURLValidationError.invalidURL
        }
        return url
    }

    static func isAllowedCleartextHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value.hasSuffix(".ts.net"), value != "ts.net" {
            return true
        }
        guard let octets = ipv4Octets(value) else {
            return false
        }

        if octets[0] == 10 { return true }
        if octets[0] == 172, (16...31).contains(octets[1]) { return true }
        if octets[0] == 192, octets[1] == 168 { return true }
        if octets[0] == 100, (64...127).contains(octets[1]) { return true }
        return false
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return values
    }
}
