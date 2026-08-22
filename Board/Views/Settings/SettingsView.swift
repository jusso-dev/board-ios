import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var baseURLString: String

    @State private var draftURL = ""
    @State private var isSaving = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var confirmsUnlink = false

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                addressSection
                securitySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                draftURL = baseURLString
            }
            .confirmationDialog(
                "Forget this server?",
                isPresented: $confirmsUnlink,
                titleVisibility: .visible
            ) {
                Button("Forget local token", role: .destructive) {
                    Task {
                        await model.unlink()
                        baseURLString = ""
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the token and server ID from Keychain, plus cached cards. Pair again to reconnect.")
            }
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        if let server = model.server {
            Section("Linked server") {
                LabeledContent("Name", value: server.name)
                LabeledContent("Version", value: server.version)
                LabeledContent("Server ID") {
                    Text(server.serverID.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("GitHub", value: server.ghLogin ?? "Not signed in")
                LabeledContent("Harnesses", value: server.harnesses.map(\.title).joined(separator: ", "))
                LabeledContent("Listen", value: server.listen)

                Link(destination: server.lanURL) {
                    LabeledContent("LAN URL") {
                        Label(server.lanURL.absoluteString, systemImage: "arrow.up.right.square")
                            .lineLimit(1)
                    }
                }
                if let tailscaleURL = server.tailscaleURL {
                    Link(destination: tailscaleURL) {
                        LabeledContent("Tailscale URL") {
                            Label(tailscaleURL.absoluteString, systemImage: "arrow.up.right.square")
                                .lineLimit(1)
                        }
                    }
                } else {
                    LabeledContent("Tailscale URL", value: "Not configured")
                }
                LabeledContent("MagicDNS", value: server.tailscaleDNS ?? "Not configured")
            }
        }
    }

    private var addressSection: some View {
        Section {
            TextField("Server URL", text: $draftURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings-server-url")

            Button {
                Task { await saveAddress() }
            } label: {
                if isSaving {
                    HStack {
                        ProgressView()
                        Text("Checking server")
                    }
                } else {
                    Label("Test and use this URL", systemImage: "network")
                }
            }
            .disabled(isSaving || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Address")
        } footer: {
            Text("Use the same server through MagicDNS, its Tailscale IP, or its LAN IP. A different server needs a new pairing.")
        }
    }

    private var securitySection: some View {
        Section {
            Button("Forget local token", role: .destructive) {
                confirmsUnlink = true
            }
            .accessibilityIdentifier("unlink-button")

            Text("New keys are minted on the server. Board does not expose token minting in the phone UI.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Security")
        } footer: {
            Text("The board token and server ID are stored only in Keychain. The server URL is stored in app settings.")
        }
    }

    private func saveAddress() async {
        isSaving = true
        resultMessage = nil
        errorMessage = nil
        defer { isSaving = false }
        do {
            let url = try await model.changeServerURL(draftURL)
            draftURL = url.absoluteString
            baseURLString = url.absoluteString
            resultMessage = "Connected to \(model.server?.name ?? "board-api")."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The server could not be reached."
        }
    }
}
