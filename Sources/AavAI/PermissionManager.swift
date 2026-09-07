import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement

enum PermissionState: String, Sendable {
    case granted = "Granted"
    case denied = "Not granted"
    case notDetermined = "Not requested"
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphone: PermissionState = .notDetermined
    @Published private(set) var accessibility: PermissionState = .notDetermined
    @Published private(set) var inputMonitoring: PermissionState = .notDetermined
    private var activationObserver: NSObjectProtocol?

    var allGranted: Bool { microphone == .granted && accessibility == .granted }

    init() {
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func refresh() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        inputMonitoring = CGPreflightListenEventAccess() ? .granted : .denied
    }

    func requestEssentialPermissions() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        refresh()
    }

    func openMicrophoneSettings() { openPrivacyPane("Privacy_Microphone") }
    func openAccessibilitySettings() { openPrivacyPane("Privacy_Accessibility") }
    func openInputMonitoringSettings() { openPrivacyPane("Privacy_ListenEvent") }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class AppSettingsManager: ObservableObject {
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?

    init() { refresh() }

    func refresh() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refresh()
    }

    func copyDiagnostics(runtime: LocalRuntimeStatus, permissions: PermissionManager) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let report = """
        AavAI diagnostics
        Version: \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(ProcessInfo.processInfo.machineHardwareName)
        Runtime: \(runtime.label)
        Microphone: \(permissions.microphone.rawValue)
        Accessibility: \(permissions.accessibility.rawValue)
        Input Monitoring: \(permissions.inputMonitoring.rawValue)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func openLogs() {
        let logs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "AavAI/Logs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logs)
    }
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &value, &size, nil, 0)
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
