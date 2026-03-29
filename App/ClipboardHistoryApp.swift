//
//  ClipboardHistoryApp.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import SwiftUI
import SwiftData

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let container: ModelContainer = {
        if AppDelegate.isRunningAutomatedTests {
            let schema = Schema([ClipboardItem.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
        return try! ClipboardStoreBootstrapper.makeContainer()
    }()

    var body: some Scene {
        Settings {
            SettingsView(appDelegate: appDelegate)
        }
            .modelContainer(container)
    }
}
