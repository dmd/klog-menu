import KlogMenuKit
import SwiftUI

@main
struct KlogMenuApp: App {
    @StateObject private var store = KlogStore()

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
