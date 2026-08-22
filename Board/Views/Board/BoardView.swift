import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onCreate: (BoardColumn) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(BoardColumn.allCases) { column in
                        KanbanColumnView(
                            column: column,
                            cards: model.cards.filter { $0.column == column },
                            height: max(proxy.size.height - 16, 220),
                            width: columnWidth,
                            onCreate: { onCreate(column) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.visible)
            .background(Color(.systemGroupedBackground))
        }
        .overlay {
            if model.isLoadingBoard && model.cards.isEmpty {
                ProgressView("Loading cards")
                    .padding(18)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("cards-loading")
            }
        }
        .accessibilityIdentifier("kanban-board")
    }

    private var columnWidth: CGFloat {
        horizontalSizeClass == .regular ? 340 : 292
    }
}
