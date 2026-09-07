import AppKit
import ApplicationServices
import Foundation

final class FocusSnapshot: @unchecked Sendable {
    let context: FocusContext
    fileprivate let element: AXUIElement?
    let processIdentifier: pid_t

    init(context: FocusContext, element: AXUIElement?, processIdentifier: pid_t) {
        self.context = context
        self.element = element
        self.processIdentifier = processIdentifier
    }
}

@MainActor
final class MacFocusReader: FocusReading {
    private let maximumContextLength = 800
    private var lastExternalProcessIdentifier: pid_t?
    private var activationObserver: NSObjectProtocol?

    init() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ownPID {
            lastExternalProcessIdentifier = frontmost.processIdentifier
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated {
                self?.lastExternalProcessIdentifier = application.processIdentifier
            }
        }
    }

    func capture() -> FocusSnapshot {
        guard AXIsProcessTrusted() else {
            return emptySnapshot()
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ownPID {
            lastExternalProcessIdentifier = frontmost.processIdentifier
            return capture(processIdentifier: frontmost.processIdentifier)
        }
        if let lastExternalProcessIdentifier {
            return capture(processIdentifier: lastExternalProcessIdentifier)
        }
        return emptySnapshot()
    }

    private func capture(processIdentifier: pid_t) -> FocusSnapshot {
        let application = AXUIElementCreateApplication(processIdentifier)
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &raw)
        guard status == .success, let raw else {
            let runningApplication = NSRunningApplication(processIdentifier: processIdentifier)
            return FocusSnapshot(
                context: .init(
                    bundleIdentifier: runningApplication?.bundleIdentifier,
                    applicationName: runningApplication?.localizedName,
                    category: Self.category(bundle: runningApplication?.bundleIdentifier),
                    nearbyText: "",
                    isSecure: false
                ),
                element: nil,
                processIdentifier: processIdentifier
            )
        }
        let element = raw as! AXUIElement
        let app = NSRunningApplication(processIdentifier: processIdentifier)
        let bundle = app?.bundleIdentifier
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        let secure = role == "AXSecureTextField" || subrole == "AXSecureTextField"
        let value = (stringAttribute(kAXValueAttribute, from: element) ?? "").suffix(maximumContextLength)
        let context = FocusContext(
            bundleIdentifier: bundle,
            applicationName: app?.localizedName,
            category: Self.category(bundle: bundle),
            nearbyText: secure ? "" : String(value),
            isSecure: secure
        )
        return FocusSnapshot(context: context, element: element, processIdentifier: processIdentifier)
    }

    private func emptySnapshot() -> FocusSnapshot {
        FocusSnapshot(
            context: .init(bundleIdentifier: nil, applicationName: nil, category: .generic, nearbyText: "", isSecure: false),
            element: nil,
            processIdentifier: 0
        )
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    static func category(bundle: String?) -> AppCategory {
        let id = (bundle ?? "").lowercased()
        if id.contains("mail") || id.contains("outlook") { return .email }
        if id.contains("slack") || id.contains("teams") || id.contains("discord") { return .workChat }
        if id.contains("pages") || id.contains("word") || id.contains("notion") || id.contains("notes") { return .document }
        return .generic
    }
}

@MainActor
struct MacTextInserter: TextInserting {
    func insert(_ text: String, into snapshot: FocusSnapshot) async -> InsertionResult {
        guard !snapshot.context.isSecure else {
            return .init(method: .clipboardOnly, succeeded: false, reason: "secureField", targetApplication: snapshot.context.applicationName)
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let target = NSRunningApplication(processIdentifier: snapshot.processIdentifier) {
            target.activate()
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard snapshot.processIdentifier != 0,
              let currentApp = NSWorkspace.shared.frontmostApplication,
              currentApp.processIdentifier == snapshot.processIdentifier else {
            copy(text)
            return .init(method: .clipboardOnly, succeeded: false, reason: "focusChanged", targetApplication: snapshot.context.applicationName)
        }
        if let element = snapshot.element,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: snapshot.context.applicationName)
        }
        let previousClipboard = captureClipboard()
        copy(text)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .init(method: .clipboardOnly, succeeded: false, reason: "eventCreationFailed", targetApplication: snapshot.context.applicationName)
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(250))
        restoreClipboard(previousClipboard, ifStillContaining: text)
        return .init(method: .clipboardPaste, succeeded: true, reason: nil, targetApplication: snapshot.context.applicationName)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func captureClipboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private func restoreClipboard(_ items: [NSPasteboardItem], ifStillContaining insertedText: String) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.string(forType: .string) == insertedText else { return }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
