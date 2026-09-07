import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()
    private var panel: NSPanel?

    func show(coordinator: DictationCoordinator) {
        guard panel == nil else { return }
        let host = NSHostingController(rootView: FloatingBarView().environmentObject(coordinator))
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 170, height: 48),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        if let screen = NSScreen.main {
            panel.setFrameOrigin(.init(x: screen.visibleFrame.midX - 85, y: screen.visibleFrame.minY + 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
