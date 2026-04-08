//
//  testApp.swift
//  test
//
//  Created by cbzw008 on 2026/3/31.
//

import SwiftUI
import SwiftData

@main
struct testApp: App {
    init() {
        TerminalPersistenceStore.migrateLaunchPreferencesIfNeeded()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
