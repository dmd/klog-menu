import AppKit
import KlogMenuKit
import SwiftUI

@main
struct KlogMenuApp: App {
    @StateObject private var store = KlogStore()

    init() {
        if !Klog.isInstalled {
            let directories = Klog.searchDirectories.map { ($0 as NSString).abbreviatingWithTildeInPath }
            Self.quit(
                title: "klog not found",
                message: "klog-menu needs the klog command-line tool (klog.jotaen.net). It looked in \(directories.joined(separator: ", ")). Install klog, then open klog-menu again."
            )
        }
        if !Klog.hasNoteCommand {
            Self.quit(
                title: "klog is too old",
                message: "klog-menu needs klog 7.2 or later. Update klog, then open klog-menu again."
            )
        }
    }

    private static func quit(title: String, message: String) -> Never {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
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
