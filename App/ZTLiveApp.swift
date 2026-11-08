// Copyright (C) 2026 Serafino Christian
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct ZTLiveApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .environmentObject(model)
                    .tabItem { Label("Avvisi", systemImage: "exclamationmark.shield") }
                RouteScreen()
                    .tabItem { Label("Percorso", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            }
            .task { await model.updateData() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.updateData() }
                }
            }
        }
    }
}
