import StopNetworking
import SwiftUI

@main
struct StopApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let store = StoreLocation.makeStore(wipe: LaunchOptions(arguments: arguments).wipesStore)
        _model = State(initialValue: AppModel(store: store, factory: NWTransportFactory(), launchArguments: arguments))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .fontDesign(.rounded)
                .tint(Theme.accent)
                .reduceMotion(forced: model.isUITesting)
                .task { await model.bootstrap() }
        }
        .onChange(of: scenePhase) { model.scenePhaseChanged($1) }
    }
}
