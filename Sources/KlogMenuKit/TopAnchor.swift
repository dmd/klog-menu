import AppKit
import SwiftUI

struct TopAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ nsView: AnchorView, context: Context) {}

    final class AnchorView: NSView {
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            DispatchQueue.main.async { [weak self] in self?.fitWindow() }
        }

        private func fitWindow() {
            guard let window, bounds.height > 0, abs(window.frame.height - bounds.height) > 0.5 else { return }
            let top = window.frame.maxY
            window.setFrame(
                NSRect(x: window.frame.minX, y: top - bounds.height, width: window.frame.width, height: bounds.height),
                display: true
            )
        }
    }
}
