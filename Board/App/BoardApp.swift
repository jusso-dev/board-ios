import SwiftUI

@main
struct BoardApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
            api = MockBoardAPIClient(
                revealsCardOnSecondOverview: arguments.contains("-reveal-card-on-foreground")
            )
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
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    if hasBootstrapped {
                        await model.refreshWhenActive()
                    } else {
                        if resetForUITesting {
                            baseURLString = ""
                        }
                        await model.bootstrap(
                            baseURLString: baseURLString,
                            resetForUITesting: resetForUITesting
                        )
                        guard !Task.isCancelled else { return }
                        hasBootstrapped = true
                    }
                }
        }
    }
}
