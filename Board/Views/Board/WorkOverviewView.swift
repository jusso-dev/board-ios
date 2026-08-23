import SwiftUI

struct WorkOverviewView: View {
    @Environment(AppModel.self) private var model

    let onOpen: (RepositoryCard) -> Void

    @State private var searchText = ""

    private let columnOrder: [BoardColumn] = [.running, .ready, .review, .backlog, .done]

    var body: some View {
        Group {
            if model.overviewCards.isEmpty && !model.isLoadingOverview {
                VStack(spacing: 18) {
                    ContentUnavailableView {
                        Label("No board cards", systemImage: "rectangle.grid.2x2")
                    } description: {
                        Text("Open GitHub issues appear here after they receive a supported board:* label.")
                    }
                    if model.isOverviewPartial {
                        partialWarning
                            .padding(.horizontal, 24)
                    }
                }
            } else {
                List {
                    Section {
                        WorkOverviewSummary(cards: model.overviewCards, jobs: model.jobs)
                    }

                    if model.isOverviewPartial {
                        Section {
                            partialWarning
                        }
                    }

                    ForEach(columnOrder) { column in
                        let cards = cards(in: column)
                        if !cards.isEmpty {
                            Section {
                                ForEach(cards) { value in
                                    WorkOverviewRow(
                                        value: value,
                                        job: model.latestJob(for: value),
                                        onOpen: { onOpen(value) }
                                    )
                                }
                            } header: {
                                Label("\(column.title) · \(cards.count)", systemImage: column.systemImage)
                                    .foregroundStyle(column.tint)
                                    .accessibilityLabel("\(column.title), \(cards.count) cards")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, prompt: "Search cards or repositories")
        .refreshable {
            await model.refreshFromUserGesture()
        }
        .overlay {
            if model.isLoadingOverview && model.overviewCards.isEmpty {
                ProgressView("Loading all work")
                    .padding(18)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("overview-loading")
            }
        }
        .accessibilityIdentifier("work-overview")
    }

    private func cards(in column: BoardColumn) -> [RepositoryCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.overviewCards
            .filter { $0.card.column == column }
            .filter { value in
                guard !query.isEmpty else { return true }
                return value.repo.localizedCaseInsensitiveContains(query)
                    || value.card.title.localizedCaseInsensitiveContains(query)
                    || value.card.body.localizedCaseInsensitiveContains(query)
                    || value.card.labels.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                    || String(value.card.number).contains(query)
            }
            .sorted { $0.card.updatedAt > $1.card.updatedAt }
    }

    private var partialWarning: some View {
        Label(
            partialWarningText,
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .accessibilityIdentifier("overview-partial-warning")
    }

    private var partialWarningText: String {
        let owners = model.overviewUnavailableOwners
        guard !owners.isEmpty else {
            return "GitHub refresh was limited. Showing latest available cards; try again later."
        }
        let shown = owners.prefix(3).joined(separator: ", ")
        let remainder = owners.count - min(owners.count, 3)
        let suffix = remainder > 0 ? " and \(remainder) more" : ""
        return "Could not refresh \(shown)\(suffix). Showing latest available cards; try again later."
    }
}

private struct WorkOverviewSummary: View {
    let cards: [RepositoryCard]
    let jobs: [JobRecord]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                metric("Running", value: runningCount, colour: .orange)
                metric("Pending", value: pendingCount, colour: .blue)
            }
            GridRow {
                metric("In review", value: reviewCount, colour: .purple)
                metric("Repositories", value: repositoryCount, colour: .secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "All work summary. \(runningCount) running, \(pendingCount) pending, \(reviewCount) in review, \(repositoryCount) repositories"
        )
        .accessibilityIdentifier("work-overview-summary")
    }

    private var runningCount: Int {
        cards.filter { value in
            value.card.column == .running
                || jobs.contains { $0.repo == value.repo && $0.issue == value.card.number && $0.status.isActive }
        }.count
    }

    private var pendingCount: Int {
        cards.filter { $0.card.column == .ready || $0.card.column == .backlog }.count
    }

    private var reviewCount: Int {
        cards.filter { $0.card.column == .review }.count
    }

    private var repositoryCount: Int {
        Set(cards.map(\.repo)).count
    }

    private func metric(_ title: String, value: Int, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(colour)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }
}

private struct WorkOverviewRow: View {
    let value: RepositoryCard
    let job: JobRecord?
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(value.repo)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        Text("#\(value.card.number)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(value.card.updatedAt, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(value.card.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(value.repo) issue \(value.card.number), \(value.card.title)")
            .accessibilityHint("Opens the repository board and card details")
            .accessibilityIdentifier("overview-card-\(value.repo)-\(value.card.number)")

            HStack(spacing: 8) {
                if let job {
                    Label(job.harness.title, systemImage: job.harness.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(job.status.tint)
                    StatusPill(status: job.status)
                } else {
                    Label("No job", systemImage: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if let prURL = job?.prURL {
                    Link(destination: prURL) {
                        Label("Open PR", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("Open pull request for \(value.repo) issue \(value.card.number)")
                } else if job?.status.isTerminal == true {
                    Label("No PR", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(job?.hasUnverifiedSuccess == true ? Color.orange : .red)
                }
            }

            if value.card.column == .done && job?.prURL == nil {
                Label("Done is only a label. No verified pull request is recorded.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }
}
