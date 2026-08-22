import SwiftUI

struct KanbanColumnView: View {
    @Environment(AppModel.self) private var model
    let column: BoardColumn
    let cards: [Card]
    let height: CGFloat
    let width: CGFloat
    let onCreate: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(cards) { card in
                        CardTile(card: card, job: model.latestJob(for: card))
                            .draggable("board-card:\(card.number)") {
                                CardDragPreview(card: card)
                            }
                    }
                    if cards.isEmpty {
                        emptyState
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.visible)
            .refreshable {
                await model.reloadBoard()
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(column.tint.opacity(isDropTarget ? 0.16 : 0.06))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isDropTarget ? column.tint : Color(.separator).opacity(0.45), lineWidth: isDropTarget ? 2 : 1)
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  value.hasPrefix("board-card:"),
                  let number = Int(value.dropFirst("board-card:".count)) else {
                return false
            }
            Task { await model.moveCard(number: number, to: column) }
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column, \(cards.count) cards")
        .accessibilityIdentifier("column-\(column.rawValue.replacingOccurrences(of: "board:", with: ""))")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: column.systemImage)
                .foregroundStyle(column.tint)
                .accessibilityHidden(true)
            Text(column.title)
                .font(.headline)
            Text(cards.count, format: .number)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: .capsule)
            Spacer()
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .frame(width: 34, height: 34)
            }
            .disabled(model.isOffline)
            .accessibilityLabel("Create \(column.title.lowercased()) card")
            .accessibilityIdentifier("add-card-\(column.rawValue.replacingOccurrences(of: "board:", with: ""))")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Drop cards here")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .accessibilityLabel("No cards in \(column.title)")
    }
}

private struct CardTile: View {
    @Environment(AppModel.self) private var model
    let card: Card
    let job: JobRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: card.number) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("#\(card.number)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(card.updatedAt, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(card.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if !card.body.isEmpty {
                        Text(card.body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Issue \(card.number), \(card.title)")
            .accessibilityValue(card.column?.title ?? "No board column")
            .accessibilityHint("Opens card details")
            .accessibilityIdentifier("card-\(card.number)")

            HStack(spacing: 8) {
                if let job {
                    Label(job.harness.title, systemImage: job.harness.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(job.status.tint)
                        .lineLimit(1)
                    StatusPill(status: job.status)
                }

                Spacer(minLength: 4)

                if let prURL = job?.prURL {
                    Link(destination: prURL) {
                        Label("PR", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("Open pull request for issue \(card.number)")
                }

                Menu {
                    ForEach(BoardColumn.allCases.filter { $0 != card.column }) { destination in
                        Button {
                            Task { await model.moveCard(number: card.number, to: destination) }
                        } label: {
                            Label("Move to \(destination.title)", systemImage: destination.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 36, height: 36)
                }
                .disabled(model.isOffline)
                .accessibilityLabel("Move issue \(card.number)")
                .accessibilityIdentifier("move-card-\(card.number)")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color(.separator).opacity(0.22), lineWidth: 1)
        }
        .accessibilityActions {
            ForEach(BoardColumn.allCases.filter { $0 != card.column }) { destination in
                Button("Move to \(destination.title)") {
                    Task { await model.moveCard(number: card.number, to: destination) }
                }
            }
        }
    }
}

private struct CardDragPreview: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(card.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(card.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

struct StatusPill: View {
    let status: JobStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.13), in: .capsule)
            .accessibilityLabel("Job status: \(status.title)")
    }
}

extension BoardColumn {
    var tint: Color {
        switch self {
        case .backlog: .secondary
        case .ready: .blue
        case .running: .orange
        case .review: .purple
        case .done: .green
        }
    }
}

extension JobStatus {
    var tint: Color {
        switch self {
        case .queued: .secondary
        case .running: .orange
        case .cancelling: .orange
        case .cancelled: .secondary
        case .succeeded: .green
        case .failed: .red
        }
    }
}
