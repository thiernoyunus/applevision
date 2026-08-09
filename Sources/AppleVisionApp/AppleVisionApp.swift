import AppKit
import OSLog
import SwiftUI

@main
struct AppleVisionDesktopApp: App {
    private let logger = Logger(subsystem: "com.thiernodiallo.AppleVisionApp", category: "lifecycle")

    init() {
        logger.notice("AppleVisionApp launched")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("AppleVision OCR") {
            ContentView()
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.automatic)
    }
}
