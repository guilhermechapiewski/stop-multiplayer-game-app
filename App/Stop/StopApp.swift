import StopNetworking
import SwiftUI

@main
struct StopApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let store = StoreLocation.makeStore(wipe: LaunchOptions(arguments: arguments).wipesStore)
        var factory: any TransportFactory = NWTransportFactory()
        #if DEBUG
        // `-demoGames`: browse a fake network with a few games on it (for screenshots), not the real one.
        if arguments.contains("-demoGames") {
            let demo = PreviewData.demoNetwork()
            Self.demo = demo
            factory = demo.network
        }
        #endif
        _model = State(initialValue: AppModel(store: store, factory: factory, launchArguments: arguments))
    }

    #if DEBUG
    @MainActor private static var demo: DemoNetwork?
    #endif

    /// XCTest sets this for the app that hosts unit tests (not for an app launched by UI tests).
    static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .fontDesign(.rounded)
                .tint(Theme.accent)
                .reduceMotion(forced: model.isUITesting)
                .task {
                    // As the unit tests' host app, stay idle: no store reads, no networking.
                    guard !Self.isHostingUnitTests else { return }
                    await model.bootstrap()
                }
        }
        .onChange(of: scenePhase) { model.scenePhaseChanged($1) }
    }
}
