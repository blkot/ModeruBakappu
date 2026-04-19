//
//  ModeruBakappuApp.swift
//  ModeruBakappu
//
//  Created by wangshenhao on 2026/4/19.
//

import SwiftUI

@main
struct ModeruBakappuApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .task {
                    appModel.loadIfNeeded()
                }
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}
