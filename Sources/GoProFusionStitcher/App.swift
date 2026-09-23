import SwiftUI

@main
struct GoProFusionStitcherApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("GoPro Fusion Stitcher") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}
