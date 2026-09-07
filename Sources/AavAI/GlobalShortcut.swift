import AppKit

@MainActor
final class GlobalShortcutMonitor {
    private var global: Any?
    private var local: Any?
    private var held = false
    private var started = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    func start() {
        guard !started else { return }
        started = true
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in self?.handle($0) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event); return event }
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }; if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil; held = false; started = false
    }
    private func handle(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, held {
            held = false
            onCancel?()
            return
        }
        // Control+Space is the development default. Production exposes rebinding and conflict checks.
        guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control) else { return }
        if event.type == .keyDown, !held { held = true; onPress?() }
        if event.type == .keyUp, held { held = false; onRelease?() }
    }
}
