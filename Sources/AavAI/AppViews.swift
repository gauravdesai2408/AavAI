import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: DictationCoordinator
    @EnvironmentObject private var dictionary: DictionaryStore
    @EnvironmentObject private var runtime: LocalServiceManager
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var settings: AppSettingsManager
    @EnvironmentObject private var audioDevices: AudioDeviceManager
    @State private var selection = "Home"
    @State private var newTerm = ""
    @State private var historySearch = ""
    @State private var confirmDeleteAll = false
    @State private var confirmResetLocalData = false
    @State private var selectedTranscript: TranscriptEntry?
    @State private var showDictation = false

    var body: some View {
        NavigationSplitView {
            List(["Home", "Dictionary", "Settings", "Plan", "Account"], id: \.self, selection: $selection) { Text($0) }
                .navigationTitle("AavAI")
        } detail: {
            switch selection {
            case "Dictionary": dictionaryView
            case "Settings": settingsView
            case "Plan": placeholder("Local plan", detail: "Unlimited local dictation · No API usage fees · Models run on this Mac.")
            case "Account": accountView
            default: homeView
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .task { await coordinator.loadHistory() }
        .sheet(item: $selectedTranscript) { entry in
            TranscriptDetailView(entry: entry)
        }
        .sheet(isPresented: $showDictation) {
            DictationDialogView().environmentObject(coordinator)
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Speak naturally. Write clearly.").font(.largeTitle.bold())
            Text("Hold Control + Space, speak, then release.").foregroundStyle(.secondary)
            if !permissions.allGranted { permissionCard }
            HStack(spacing: 8) {
                Circle().fill(runtime.status.isReady ? .green : .orange).frame(width: 9, height: 9)
                Text(runtime.status.label).font(.subheadline)
                Spacer()
                if case .failed = runtime.status {
                    Button("Retry") { Task { await runtime.restart() } }
                }
            }
            stateCard
            HStack(spacing: 12) {
                Button(action: toggleRecording) {
                    Label(coordinator.state == .listening ? "Stop and transcribe" : "Start dictation",
                          systemImage: coordinator.state == .listening ? "stop.fill" : "mic.fill")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing || !runtime.status.isReady)
                if coordinator.state == .listening {
                    Button("Cancel") { Task { await coordinator.cancel() } }
                        .keyboardShortcut(.cancelAction)
                }
                if coordinator.state != .idle && coordinator.state != .listening {
                    Button("Reset") { coordinator.reset() }
                }
            }
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                TextField("Search transcripts", text: $historySearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
            List(filteredHistory) { entry in
                Button { selectedTranscript = entry } label: {
                  VStack(alignment: .leading, spacing: 5) {
                    Text(entry.cleanedText).lineLimit(3)
                    Text("\(entry.applicationName ?? "Unknown app") · \(entry.createdAt.formatted()) · \(entry.latencyMilliseconds) ms")
                        .font(.caption).foregroundStyle(.secondary)
                  }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu {
                    Button("Open transcript") { selectedTranscript = entry }
                    Button("Copy") { coordinator.copyHistoryEntry(entry) }
                    Button("Insert again") { Task { await coordinator.insertHistoryEntry(entry) } }
                    Divider()
                    Button("Delete", role: .destructive) { Task { await coordinator.deleteHistory(id: entry.id) } }
                }
            }
        }.padding(28)
    }

    private var stateCard: some View {
        HStack(spacing: 14) {
            Circle().fill(stateColor).frame(width: 12, height: 12)
            Text(stateText).font(.headline)
            Spacer()
            if coordinator.recoverableText != nil {
                Button("Copy") { coordinator.copyRecoverableText() }
                Button("Retry insertion") { Task { await coordinator.retryLastInsertion() } }
            }
            if case .failed = coordinator.state { Button("Reset") { coordinator.reset() } }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Finish Mac permissions", systemImage: "lock.shield")
                .font(.headline)
            Text("Microphone records your voice. Accessibility inserts text and enables Control + Space in every app.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                permissionBadge("Microphone", permissions.microphone)
                permissionBadge("Accessibility", permissions.accessibility)
                Spacer()
                Button("Grant permissions") { Task { await permissions.requestEssentialPermissions() } }
                    .buttonStyle(.borderedProminent)
                Button("Refresh") { permissions.refresh() }
            }
        }
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func permissionBadge(_ title: String, _ state: PermissionState) -> some View {
        Label("\(title): \(state.rawValue)", systemImage: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(state == .granted ? .green : .orange)
            .font(.caption)
    }

    private var dictionaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictionary").font(.largeTitle.bold())
            Text("Teach AavAI names, products, and specialist vocabulary.").foregroundStyle(.secondary)
            HStack { TextField("Add a word or phrase", text: $newTerm); Button("Add") { dictionary.add(newTerm); newTerm = "" } }
            List { ForEach(dictionary.terms, id: \.self) { Text($0) }.onDelete(perform: dictionary.remove) }
        }.padding(28)
    }

    private var settingsView: some View {
        Form {
            Section("Shortcut") { LabeledContent("Push to talk", value: "Control + Space") }
            Section("Microphone") {
                Picker("Input device", selection: $audioDevices.selectedUID) {
                    Text("System default").tag("")
                    ForEach(audioDevices.devices) { device in Text(device.name).tag(device.uid) }
                }
                Button("Refresh microphones") { audioDevices.refresh() }
            }
            Section("Startup") {
                Toggle("Launch AavAI at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError { Text(error).foregroundStyle(.red).font(.caption) }
            }
            Section("Privacy") {
                Text("Audio and transcripts are processed locally and are not uploaded by local mode.")
                Button("Delete local history", role: .destructive) { confirmDeleteAll = true }
            }
            Section("Local AI") {
                Picker("Speech recognition", selection: Binding(
                    get: { runtime.recognitionMode },
                    set: { mode in Task { await runtime.setRecognitionMode(mode) } }
                )) {
                    Text("Accuracy — better on tested difficult whispers").tag("accurate")
                    Text("Speed — faster results").tag("fast")
                }
                .disabled(runtime.status == .starting || isProcessing || coordinator.state == .listening)
                Text("Accuracy mode takes longer. Both modes process audio on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Status", value: runtime.status.label)
                Button("Restart local services") { Task { await runtime.restart() } }
            }
            Section("Permissions") {
                permissionRow("Microphone", permissions.microphone, action: permissions.openMicrophoneSettings)
                permissionRow("Accessibility", permissions.accessibility, action: permissions.openAccessibilitySettings)
                permissionRow("Input Monitoring (optional)", permissions.inputMonitoring, action: permissions.openInputMonitoringSettings)
                Button("Refresh permission status") { permissions.refresh() }
            }
            Section("Diagnostics") {
                Button("Copy privacy-safe diagnostics") { settings.copyDiagnostics(runtime: runtime.status, permissions: permissions) }
                Button("Open logs") { settings.openLogs() }
            }
        }.formStyle(.grouped).navigationTitle("Settings")
            .confirmationDialog("Delete all local transcript history?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all history", role: .destructive) { Task { await coordinator.deleteAllHistory() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
    }

    private var accountView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("No account required").font(.largeTitle.bold())
            Text("Local mode works without sign-in and keeps processing on this Mac.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Local data").font(.title2.bold())
            Text("Delete transcript history and personal dictionary entries from this Mac.")
                .foregroundStyle(.secondary)
            Button("Delete all local data", role: .destructive) { confirmResetLocalData = true }
            Spacer()
        }
        .padding(28)
        .confirmationDialog("Delete all AavAI local data?", isPresented: $confirmResetLocalData, titleVisibility: .visible) {
            Button("Delete all local data", role: .destructive) {
                Task { await coordinator.deleteAllHistory(); dictionary.deleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Transcript history and dictionary entries will be permanently removed.") }
    }

    private func permissionRow(_ title: String, _ state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack {
            LabeledContent(title, value: state.rawValue)
            if state != .granted { Button("Open Settings", action: action) }
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View { VStack(spacing: 12) { Text(title).font(.largeTitle.bold()); Text(detail).foregroundStyle(.secondary) }.padding() }
    private func toggleRecording() {
        if coordinator.state == .listening {
            Task { await coordinator.finish() }
        } else {
            coordinator.reset()
            showDictation = true
            Task { await coordinator.start(previewOnly: true) }
        }
    }
    private var isProcessing: Bool {
        switch coordinator.state {
        case .finalizing, .cleaning, .inserting: true
        default: false
        }
    }
    private var stateText: String { switch coordinator.state { case .idle: "Ready"; case .listening: "Listening…"; case .finalizing: "Transcribing…"; case .cleaning: "Polishing…"; case .inserting: "Inserting…"; case .completed: "Transcript ready"; case .cancelled: "Cancelled"; case .failed(let error, _): error.message } }
    private var stateColor: Color { switch coordinator.state { case .listening: .red; case .failed: .orange; case .completed: .green; default: .blue } }
    private var filteredHistory: [TranscriptEntry] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return coordinator.history }
        return coordinator.history.filter {
            $0.cleanedText.localizedCaseInsensitiveContains(query)
                || $0.rawText.localizedCaseInsensitiveContains(query)
                || ($0.applicationName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

struct FloatingBarView: View {
    @EnvironmentObject private var coordinator: DictationCoordinator
    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 10) {
                Image(systemName: icon).symbolEffect(.pulse, isActive: coordinator.state == .listening)
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(coordinator.state == .listening ? "Stop and transcribe" : "Start dictation")
    }
    private var icon: String { coordinator.state == .listening ? "waveform" : "mic.fill" }
    private var label: String { switch coordinator.state { case .listening: "Listening"; case .cleaning, .finalizing: "Polishing"; case .failed: "Needs attention"; default: "AavAI" } }
    private var isProcessing: Bool {
        switch coordinator.state {
        case .finalizing, .cleaning, .inserting: true
        default: false
        }
    }
    private func toggleRecording() {
        if coordinator.state == .listening {
            Task { await coordinator.finish() }
        } else {
            coordinator.reset()
            Task { await coordinator.start() }
        }
    }
}
