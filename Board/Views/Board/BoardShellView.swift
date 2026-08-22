import SwiftUI

struct BoardShellView: View {
    @Environment(AppModel.self) private var model
    @Binding var baseURLString: String
    @State private var createColumn: BoardColumn?
    @State private var showsRepoPicker = false
    @State private var showsSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.selectedRepo == nil {
                    WorkOverviewView { value in
                        Task {
                            await model.selectRepo(value.repo)
                            path.append(value.card.number)
                        }
                    }
                } else if model.repos.isEmpty {
                    emptyRepos
                } else {
                    BoardView { column in
                        createColumn = column
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { number in
                CardDetailView(number: number)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    repoPicker
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await model.reloadBoard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh board")
                    .disabled(model.isLoadingBoard || model.isLoadingOverview)

                    Button {
                        createColumn = .backlog
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create backlog card")
                    .accessibilityIdentifier("create-card-button")
                    .disabled(model.selectedRepo == nil || model.isOffline)

                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-button")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if model.isOffline {
                        offlineBanner
                    }
                    if let warning = model.refreshWarning {
                        refreshWarningBanner(warning)
                    }
                    if let server = model.server {
                        ServerConnectionBar(server: server)
                    }
                }
            }
        }
        .sheet(item: $createColumn) { column in
            CreateCardSheet(initialColumn: column)
        }
        .sheet(isPresented: $showsRepoPicker) {
            RepositoryPickerView(
                repositories: model.repos,
                selectedRepository: model.selectedRepo,
                onSelectAll: {
                    Task {
                        path = NavigationPath()
                        await model.selectAllRepositories()
                    }
                }
            ) { repo in
                Task {
                    path = NavigationPath()
                    await model.selectRepo(repo.nameWithOwner)
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(baseURLString: $baseURLString)
        }
    }

    private var navigationTitle: String {
        model.repos.first(where: { $0.nameWithOwner == model.selectedRepo })?.shortName ?? "All work"
    }

    private var repoPicker: some View {
        Button {
            showsRepoPicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox")
                Text(navigationTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .accessibilityLabel("Choose repository")
        .accessibilityValue(model.selectedRepo ?? "All repositories")
        .accessibilityIdentifier("repo-picker")
    }

    private var emptyRepos: some View {
        ContentUnavailableView {
            Label("No repositories", systemImage: "shippingbox")
        } description: {
            Text("The server did not return a GitHub repository. Check gh authentication on the board guest.")
        } actions: {
            Button("Try again") {
                Task { await model.loadRepos() }
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("empty-repositories")
    }

    private var offlineBanner: some View {
        Label("Offline. Showing the last saved cards. Changes need the server.", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.17))
            .accessibilityIdentifier("offline-banner")
    }

    private func refreshWarningBanner(_ warning: String) -> some View {
        Label(warning, systemImage: "arrow.triangle.2.circlepath")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.16))
            .accessibilityIdentifier("refresh-warning")
    }
}
private struct ServerConnectionBar: View {
    let server: ServerResponse

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.subheadline.weight(.semibold))
                Text(server.ghLogin.map { "GitHub: \($0)" } ?? "GitHub not signed in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(server.harnesses.map(\.title).joined(separator: " · "))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Menu {
                Link(destination: server.lanURL) {
                    Label("Open LAN URL", systemImage: "network")
                }
                if let tailscaleURL = server.tailscaleURL {
                    Link(destination: tailscaleURL) {
                        Label("Open Tailscale URL", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
                if let tailscaleDNS = server.tailscaleDNS {
                    Text(tailscaleDNS)
                }
            } label: {
                Image(systemName: "info.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Server addresses")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("server-summary")
    }
}
