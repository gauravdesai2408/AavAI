import AppKit
import ApplicationServices
import SwiftUI

@main
struct AavAIApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var dictionary: DictionaryStore
    @StateObject private var coordinator: DictationCoordinator
    @StateObject private var runtime: LocalServiceManager
    @StateObject private var permissions: PermissionManager
    @StateObject private var settings: AppSettingsManager
    @StateObject private var audioDevices: AudioDeviceManager

    init() {
        let dictionary = DictionaryStore()
        let runtime = LocalServiceManager.shared
        let permissions = PermissionManager()
        let settings = AppSettingsManager()
        let audioDevices = AudioDeviceManager.shared
        let backend = BackendClient(baseURL: URL(string: ProcessInfo.processInfo.environment["AAVAI_BACKEND_URL"] ?? "http://127.0.0.1:8787")!)
        _dictionary = StateObject(wrappedValue: dictionary)
        _runtime = StateObject(wrappedValue: runtime)
        _permissions = StateObject(wrappedValue: permissions)
        _settings = StateObject(wrappedValue: settings)
        _audioDevices = StateObject(wrappedValue: audioDevices)
        let coordinator = DictationCoordinator(
            audio: MicrophoneCapture(),
            transcription: InferenceSelection.usesNativeApple ? NativeTranscription() : backend,
            cleanup: InferenceSelection.usesNativeApple ? NativeCleanup() : backend,
            focus: MacFocusReader(), inserter: MacTextInserter(), history: JSONHistoryStore(), dictionary: dictionary,
            isServiceReady: { runtime.status.isReady }
        )
        _coordinator = StateObject(wrappedValue: coordinator)
        // Referencing the imported C global `kAXTrustedCheckOptionPrompt` is rejected by
        // Swift 6 strict concurrency because Clang imports it as mutable shared state.
        // The Accessibility API dictionary key's stable string value avoids that unsafe
        // global access while preserving the exact framework behavior.

        AppBootstrap.shared.configure(
            coordinator: coordinator,
            runtime: runtime,
            permissions: permissions
        )
    }

    var body: some Scene {
        Window("AavAI", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(dictionary)
                .environmentObject(runtime)
                .environmentObject(permissions)
                .environmentObject(settings)
                .environmentObject(audioDevices)
        }
        MenuBarExtra("AavAI", systemImage: "waveform") {
            AavAIMenuBarView().environmentObject(runtime)
        }
    }

}

private struct AavAIMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: LocalServiceManager

    var body: some View {
        Text(runtime.status.label)
        if InferenceSelection.usesNativeApple {
            Button("Download Apple English Speech Assets…") {
                Task { await runtime.installNativeAssets() }
            }
            .disabled(runtime.status == .starting)
        }
        Button("Open AavAI") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit AavAI") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
