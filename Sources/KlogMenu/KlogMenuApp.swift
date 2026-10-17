import AppKit
import KlogMenuKit
import SwiftUI

@main
struct KlogMenuApp: App {
    @StateObject private var store = KlogStore()

    init() {
        guard !Klog.isInstalled else { return }
        let directories = Klog.searchDirectories.map { ($0 as NSString).abbreviatingWithTildeInPath }
        let alert = NSAlert()
        alert.messageText = "klog not found"
        alert.informativeText = "klog-menu needs the klog command-line tool (klog.jotaen.net). It looked in \(directories.joined(separator: ", ")). Install klog, then open klog-menu again."
        alert.addButton(withTitle: "Quit")
        NSApplication.shared.activate()
        alert.runModal()
        exit(1)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.running == nil ? "clock" : "record.circle")
                Text(store.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
