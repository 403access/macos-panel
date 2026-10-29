import AppKit
import SwiftUI

@main
struct MacosPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = SystemMonitor()

    init() {
        MenuBarDisplay.migrateLegacyPreferenceIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        // Open the panel in a normal window for layout work: `MacosPanel --preview-panel`.
        if ProcessInfo.processInfo.arguments.contains("--preview-panel") {
            let hosting = NSHostingView(rootView: PanelView(monitor: SystemMonitor()))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 302, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Panel Preview"
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
        #endif
    }
}
