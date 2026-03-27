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
        let schema = Schema([ClipboardItem.self])
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = supportDirectory.appendingPathComponent("ClipboardHistory", isDirectory: true)
        let storeURL = appDirectory.appendingPathComponent("ClipboardHistory.store")
        
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        Settings {
            SettingsView(appDelegate: appDelegate)
        }
            .modelContainer(container)
    }
}
