import SwiftUI

@main
struct BoardApp: App {
    @State private var model: AppModel
    @State private var hasBootstrapped = false
    @AppStorage("board.baseURL") private var baseURLString = ""

    private let resetForUITesting: Bool

    @MainActor
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let credentials = KeychainCredentialStore()
        let cache = CardCache()
        let api: any BoardAPIClientProtocol
        if arguments.contains("-board-ui-testing") {
            api = MockBoardAPIClient()
        } else {
            api = BoardAPIClient(credentials: credentials)
        }
        _model = State(initialValue: AppModel(api: api, credentials: credentials, cache: cache))
        resetForUITesting = arguments.contains("-reset-state")
    }

    var body: some Scene {
        WindowGroup {
            RootView(baseURLString: $baseURLString)
                .environment(model)
                .tint(.accentColor)
                .task {
                    guard !hasBootstrapped else { return }
                    hasBootstrapped = true
                    if resetForUITesting {
                        baseURLString = ""
                    }
                    await model.bootstrap(
                        baseURLString: baseURLString,
                        resetForUITesting: resetForUITesting
                    )
                }
        }
    }
}
