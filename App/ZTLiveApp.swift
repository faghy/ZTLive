import SwiftUI

@main
struct ZTLiveApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .environmentObject(model)
                    .tabItem { Label("Avvisi", systemImage: "exclamationmark.shield") }
                RouteScreen()
                    .tabItem { Label("Percorso", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            }
        }
    }
}
