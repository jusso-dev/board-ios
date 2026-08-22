import SwiftUI

struct RepositoryPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let repositories: [Repo]
    let selectedRepository: String?
    let onSelectAll: () -> Void
    let onSelect: (Repo) -> Void

    @State private var searchText = ""

    private var filteredRepositories: [Repo] {
        repositories.filter { $0.matchesRepositorySearch(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredRepositories.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            allRepositoriesButton
                        }
                        ForEach(filteredRepositories) { repo in
                            repositoryButton(repo)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Repositories")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search repositories"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var allRepositoriesButton: some View {
        Button {
            onSelectAll()
            dismiss()
        } label: {
            HStack {
                Image(systemName: "rectangle.grid.2x2")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All work")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Every repository with a board card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selectedRepository == nil {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All work")
        .accessibilityValue(selectedRepository == nil ? "Selected" : "")
        .accessibilityHint("Show cards from every repository")
        .accessibilityIdentifier("repo-all-work")
    }

    private func repositoryButton(_ repo: Repo) -> some View {
        Button {
            onSelect(repo)
            dismiss()
        } label: {
            HStack {
                Image(systemName: repo.isPrivate ? "lock" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.shortName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(repo.ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let description = repo.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if repo.nameWithOwner == selectedRepository {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(repo.nameWithOwner)
        .accessibilityValue(repo.nameWithOwner == selectedRepository ? "Selected" : "")
        .accessibilityHint("Select repository")
        .accessibilityIdentifier("repo-\(repo.nameWithOwner)")
    }
}
