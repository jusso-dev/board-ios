import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Binding var baseURLString: String

    var body: some View {
        @Bindable var bindableModel = model

        Group {
            switch model.phase {
            case .loading:
                ProgressView("Opening Board")
                    .accessibilityIdentifier("board-loading")
            case .needsLink:
                ServerLinkView(baseURLString: $baseURLString)
            case .linked:
                BoardShellView(baseURLString: $baseURLString)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .alert(item: $bindableModel.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK")) {
                    model.dismissNotice()
                }
            )
        }
    }
}
