import AppKit
import Foundation

enum LocalRuntimeStatus: Equatable, Sendable {
    case stopped
    case starting
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting local AI…"
        case .ready: "Local AI ready"
        case .failed(let message): "Local AI unavailable: \(message)"
        }
    }

    var isReady: Bool { self == .ready }
}

@MainActor
final class LocalServiceManager: ObservableObject {
    static let shared = LocalServiceManager()

    @Published private(set) var status: LocalRuntimeStatus = .stopped
    private var processes: [Process] = []
    private var logHandles: [FileHandle] = []
    private var startupTask: Task<Void, Never>?

    func startIfNeeded() async {
        if status == .ready || status == .starting { return }
        if await backendIsHealthy() {
            status = .starting
            do {
                try await prewarmCleanupModel()
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
            return
        }

        status = .starting
        do {
            let runtime = try resolveRuntimeDirectory()
            let bin = runtime.appending(path: "bin", directoryHint: .isDirectory)
            let ollama = runtime.appending(path: "ollama", directoryHint: .isDirectory)
            let models = runtime.appending(path: "models", directoryHint: .isDirectory)

            if !(await isHealthy(URL(string: "http://127.0.0.1:8080/health")!)) {
                try launch(
                    executable: bin.appending(path: "whisper-server"),
                    arguments: [
                        "--model", models.appending(path: "ggml-small.en.bin").path,
                        "--host", "127.0.0.1", "--port", "8080"
                    ],
                    environment: ["DYLD_LIBRARY_PATH": bin.path],
                    logName: "whisper"
                )
            }
            try await waitUntilHealthy(URL(string: "http://127.0.0.1:8080/health")!, service: "Whisper", attempts: 120)

            if !(await isHealthy(URL(string: "http://127.0.0.1:11434/api/tags")!)) {
                try launch(
                    executable: ollama.appending(path: "ollama"),
                    arguments: ["serve"],
                    environment: [
                        "OLLAMA_HOST": "127.0.0.1:11434",
                        "OLLAMA_MODELS": models.appending(path: "ollama", directoryHint: .isDirectory).path
                    ],
                    logName: "ollama"
                )
            }
            try await waitUntilHealthy(URL(string: "http://127.0.0.1:11434/api/tags")!, service: "Ollama", attempts: 90)

            if !(await backendIsHealthy()) {
                try launch(
                    executable: bin.appending(path: "node"),
                    arguments: [runtime.appending(path: "backend/src/server.mjs").path],
                    environment: ["AAVAI_PROVIDER": "local"],
                    logName: "backend"
                )
            }
            try await waitUntilHealthy(URL(string: "http://127.0.0.1:8787/health")!, service: "AavAI backend", attempts: 40)
            try await prewarmCleanupModel()
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func restart() async {
        stopOwnedProcesses()
        status = .stopped
        await startIfNeeded()
    }

    func stopOwnedProcesses() {
        for process in processes.reversed() where process.isRunning { process.terminate() }
        processes.removeAll()
        for handle in logHandles { try? handle.close() }
        logHandles.removeAll()
        status = .stopped
    }

    private func resolveRuntimeDirectory() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["AAVAI_RUNTIME_DIR"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appending(path: "LocalRuntime", directoryHint: .isDirectory))
        }
        let project = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(project.appending(path: ".runtime-bundle", directoryHint: .isDirectory))

        for candidate in candidates where runtimeIsComplete(candidate) { return candidate }
        throw RuntimeError("Local models are not installed. Run scripts/build-app.sh once.")
    }

    private func runtimeIsComplete(_ root: URL) -> Bool {
        let required = [
            "bin/whisper-server", "bin/node", "ollama/ollama", "ollama/llama-server",
            "models/ggml-small.en.bin", "models/ollama", "backend/src/server.mjs"
        ]
        return required.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0).path) }
    }

    private func launch(executable: URL, arguments: [String], environment: [String: String], logName: String) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RuntimeError("Missing executable: \(executable.lastPathComponent)")
        }
        let logs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "AavAI/Logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appending(path: "\(logName).log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        processes.append(process)
        logHandles.append(handle)
    }

    private func backendIsHealthy() async -> Bool {
        await isHealthy(URL(string: "http://127.0.0.1:8787/health")!)
    }

    private func isHealthy(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        if url.port == 8787,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dependencies = object["dependencies"] as? [String: Any] {
            return dependencies["provider"] as? String == "local"
                && dependencies["whisper"] as? Bool != false
                && dependencies["ollama"] as? Bool != false
        }
        return true
    }

    private func waitUntilHealthy(_ url: URL, service: String, attempts: Int) async throws {
        for _ in 0..<attempts {
            if await isHealthy(url) { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw RuntimeError("\(service) did not start. Check AavAI logs.")
    }

    private func prewarmCleanupModel() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8787/v1/cleanup")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "transcript": "Ready",
            "context": [
                "bundleIdentifier": NSNull(), "applicationName": "AavAI",
                "category": "generic", "nearbyText": "", "isSecure": false
            ],
            "locale": "en", "dictionary": []
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RuntimeError("The cleanup model failed its startup check. Check AavAI logs.")
        }
    }
}

private struct RuntimeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppBootstrap.shared.applicationDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        LocalServiceManager.shared.stopOwnedProcesses()
    }
}

@MainActor
final class AppBootstrap {
    static let shared = AppBootstrap()

    private let shortcut = GlobalShortcutMonitor()
    private var coordinator: DictationCoordinator?
    private var runtime: LocalServiceManager?
    private var permissions: PermissionManager?
    private var launchFinished = false
    private var started = false

    private init() {}

    func configure(
        coordinator: DictationCoordinator,
        runtime: LocalServiceManager,
        permissions: PermissionManager
    ) {
        self.coordinator = coordinator
        self.runtime = runtime
        self.permissions = permissions
        if launchFinished { start() }

        // SwiftUI can restore a MenuBarExtra app without forwarding the usual
        // delegate launch callback. Deferring one turn guarantees AppKit's run
        // loop exists while keeping `start()` idempotent if the callback arrives.
        DispatchQueue.main.async {
            AppBootstrap.shared.start()
        }
    }

    func applicationDidFinishLaunching() {
        launchFinished = true
        start()
    }

    func start() {
        guard !started,
              let coordinator,
              let runtime,
              let permissions else { return }
        started = true

        shortcut.onPress = { Task { await coordinator.start() } }
        shortcut.onRelease = { Task { await coordinator.finish() } }
        shortcut.onCancel = { Task { await coordinator.cancel() } }
        shortcut.start()
        FloatingPanelController.shared.show(coordinator: coordinator)

        Task { await runtime.startIfNeeded() }
        Task { await permissions.requestEssentialPermissions() }
    }
}
