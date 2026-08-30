import AppKit
import SwiftUI
import SwiftData

/// Ensures development launches also use the bundled LifeOS icon in the Dock.
final class LifeOSAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let image = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = image
        }
    }
}

/// LifeOS application entry point. The initial release stores all data locally.
@main
struct LifeOSApp: App {
    @NSApplicationDelegateAdaptor(LifeOSAppDelegate.self) private var appDelegate
    private let modelContainer = ModelContainerFactory.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 620)
                .modelContainer(modelContainer)
        }
        .defaultSize(width: 1_180, height: 760)
    }
}
