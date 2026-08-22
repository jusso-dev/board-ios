import SwiftUI

struct ServerLinkView: View {
    @Environment(AppModel.self) private var model
    @Binding var baseURLString: String

    @State private var pairCode = ""
    @State private var isTesting = false
    @State private var isPairing = false
    @State private var connectionMessage: String?
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .body) private var controlHeight: CGFloat = 48

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    serverSection
                    pairSection
                    privacyNote
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Link Board")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 15))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Board")
                    .font(.largeTitle.bold())
                Text("Run GitHub cards on your Ubuntu board guest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var serverSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                TextField("http://board.example.ts.net:8787", text: $baseURLString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .padding(.horizontal, 12)
                    .frame(minHeight: controlHeight)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                    .accessibilityLabel("Server URL")
                    .accessibilityIdentifier("server-url-field")

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing" : "Test connection")
                    }
                    .frame(maxWidth: .infinity, minHeight: controlHeight)
                }
                .buttonStyle(.bordered)
                .disabled(baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting || isPairing)
                .accessibilityIdentifier("test-connection-button")

                if let connectionMessage {
                    Label(connectionMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("connection-success")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("link-error")
                }
            }
        } label: {
            Label("Server", systemImage: "server.rack")
                .font(.headline)
        }
    }

    private var pairSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter the one-time code shown in the board-api journal or HOST.md.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("8-character code", text: $pairCode)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(minHeight: controlHeight)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                    .accessibilityLabel("Pair code")
                    .accessibilityIdentifier("pair-code-field")
                    .onChange(of: pairCode) { _, newValue in
                        let cleaned = newValue
                            .filter { $0.isLetter || $0.isNumber }
                            .uppercased()
                        pairCode = String(cleaned.prefix(8))
                    }

                Button {
                    Task { await pair() }
                } label: {
                    HStack {
                        if isPairing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "link")
                        }
                        Text(isPairing ? "Linking" : "Link this phone")
                    }
                    .frame(maxWidth: .infinity, minHeight: controlHeight)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pairCode.count != 8 || isPairing || isTesting)
                .accessibilityIdentifier("pair-button")
            }
        } label: {
            Label("Pair", systemImage: "key.horizontal")
                .font(.headline)
        }
    }

    private var privacyNote: some View {
        Label(
            "The phone stores only its board token and server ID in Keychain. GitHub and coding-agent credentials stay on the server.",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func testConnection() async {
        isTesting = true
        errorMessage = nil
        connectionMessage = nil
        defer { isTesting = false }
        do {
            let health = try await model.testConnection(baseURLString: baseURLString)
            let url = try ServerURLValidator.validatedURL(from: baseURLString)
            baseURLString = url.absoluteString
            connectionMessage = "Connected to board-api \(health.version)."
        } catch {
            errorMessage = shortMessage(for: error)
        }
    }

    private func pair() async {
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        do {
            let url = try await model.link(baseURLString: baseURLString, code: pairCode)
            baseURLString = url.absoluteString
            pairCode = ""
        } catch {
            errorMessage = shortMessage(for: error)
        }
    }

    private func shortMessage(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The server could not be reached."
    }
}
