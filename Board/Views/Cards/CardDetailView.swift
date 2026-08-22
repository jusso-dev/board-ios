import SwiftUI

struct CardDetailView: View {
    @Environment(AppModel.self) private var model
    let number: Int

    @State private var showsRunSheet = false
    @State private var destinationJobID: UUID?

    var body: some View {
        Group {
            if let card = model.card(number: number) {
                cardContent(card)
            } else {
                ProgressView("Loading card")
            }
        }
        .navigationTitle("Issue #\(number)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: number) {
            await model.loadCard(number: number)
            await model.refreshJobs(showError: false)
        }
        .sheet(isPresented: $showsRunSheet) {
            RunJobSheet(issue: number) { job in
                destinationJobID = job.id
            }
        }
        .navigationDestination(item: $destinationJobID) { id in
            JobView(jobID: id)
        }
    }

    private func cardContent(_ card: Card) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let column = card.column {
                            Label(column.title, systemImage: column.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(column.tint)
                        } else {
                            Text("No board column")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link(destination: card.url) {
                            Label("GitHub", systemImage: "arrow.up.right.square")
                        }
                        .font(.subheadline.weight(.semibold))
                    }

                    Text(card.title)
                        .font(.title2.bold())
                        .accessibilityIdentifier("card-detail-title")

                    Text("Updated \(card.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if card.column == .review {
                        Text("Review is a board label. Verify the pull request in Last job below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if card.column == .done {
                        Text("Done is a board label. It does not prove that a pull request was opened or merged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Body")
                        .font(.headline)
                    Text(card.body.isEmpty ? "No description." : card.body)
                        .font(.body)
                        .foregroundStyle(card.body.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }

                if !card.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Labels")
                            .font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(card.labels, id: \.self) { label in
                                Text(label)
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(.tertiarySystemFill), in: .capsule)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Comments")
                        .font(.headline)
                    Text("Comments are not supplied by board-api 0.1.0.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                jobSection(card)

                Button {
                    showsRunSheet = true
                } label: {
                    Label("Run this card", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isOffline)
                .accessibilityHint("Choose a server-side coding harness and optional crew")
                .accessibilityIdentifier("run-card-button")
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func jobSection(_ card: Card) -> some View {
        if let job = model.latestJob(for: card) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last job")
                    .font(.headline)
                Button {
                    destinationJobID = job.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: job.harness.systemImage)
                            .foregroundStyle(job.status.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.harness.title)
                                .font(.body.weight(.semibold))
                            Text(job.branch)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        StatusPill(status: job.status)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open last job, \(job.harness.title), \(job.status.title)")

                if let prURL = job.prURL {
                    Link(destination: prURL) {
                        Label("Open pull request", systemImage: "arrow.up.right.square")
                    }
                }

                Label(
                    job.outcomeSummary,
                    systemImage: job.outcomeSystemImage
                )
                .font(.subheadline)
                .foregroundStyle(job.hasUnverifiedSuccess ? .orange : job.status.tint)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if card.column == .review || card.column == .done {
            Label(
                "No server job record is available for this issue. Open GitHub before treating the work as delivered.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(.orange)
        }
    }
}
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: proposal.width ?? x, height: y + rowHeight), points)
    }
}
