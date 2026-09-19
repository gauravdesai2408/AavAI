import CryptoKit
import Foundation
import Security

actor JSONHistoryStore: HistoryStoring {
    private let fileURL: URL
    private var encryptionKey: SymmetricKey?
    private var entries: [TranscriptEntry] = []
    private var hasLoaded = false
    private var loadError: HistoryStoreError?
    private let initialLoad: Task<InitialState, Never>
    private static let magic = Data("AAVAI-HISTORY-1\n".utf8)

    init(fileURL: URL? = nil, keyData: Data? = nil, keyLoader: (@Sendable () -> Data?)? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "AavAI", directoryHint: .isDirectory)
        let resolvedFileURL = fileURL ?? base.appending(path: "history.json")
        self.fileURL = resolvedFileURL
        self.encryptionKey = nil
        let loadKey = keyLoader ?? { Self.loadOrCreateKey() }
        self.initialLoad = Task.detached(priority: .userInitiated) {
            let loadedKeyData = keyData ?? loadKey()
            let key = loadedKeyData.map(SymmetricKey.init(data:))
            do {
                guard let key else { throw HistoryStoreError.keyUnavailable }
                guard FileManager.default.fileExists(atPath: resolvedFileURL.path) else {
                    return InitialState(keyData: loadedKeyData, entries: [], error: nil)
                }
                let stored = try Data(contentsOf: resolvedFileURL)
                let clear: Data
                if stored.starts(with: Self.magic) {
                    clear = try AES.GCM.open(AES.GCM.SealedBox(combined: stored.dropFirst(Self.magic.count)), using: key)
                } else { clear = stored }
                let entries = try JSONDecoder().decode([TranscriptEntry].self, from: clear)
                if !stored.starts(with: Self.magic) {
                    try Self.encryptedData(entries: entries, key: key).write(to: resolvedFileURL, options: [.atomic, .completeFileProtection])
                }
                return InitialState(keyData: loadedKeyData, entries: entries, error: nil)
            } catch {
                return InitialState(keyData: loadedKeyData, entries: [], error: error as? HistoryStoreError ?? .unreadable)
            }
        }
    }

    func list() async -> [TranscriptEntry] { await ensureLoaded(); return entries.sorted { $0.createdAt > $1.createdAt } }
    func validate() async throws { await ensureLoaded(); if let loadError { throw loadError } }
    func append(_ entry: TranscriptEntry) async throws { try await validate(); try commit(entries + [entry]) }
    func delete(id: UUID) async throws { try await validate(); try commit(entries.filter { $0.id != id }) }
    func deleteAll() async throws { try await validate(); try commit([]) }
    func delete(before cutoff: Date) async throws {
        try await validate()
        let kept = entries.filter { $0.createdAt >= cutoff }
        if kept.count != entries.count { try commit(kept) }
    }

    private func ensureLoaded() async {
        guard !hasLoaded else { return }
        let state = await initialLoad.value
        guard !hasLoaded else { return }
        encryptionKey = state.keyData.map(SymmetricKey.init(data:))
        entries = state.entries
        loadError = state.error
        hasLoaded = true
    }

    private func commit(_ proposed: [TranscriptEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let encryptionKey else { throw HistoryStoreError.keyUnavailable }
        let data = try Self.encryptedData(entries: proposed, key: encryptionKey)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        entries = proposed
    }

    private static func encryptedData(entries: [TranscriptEntry], key: SymmetricKey) throws -> Data {
        let clear = try JSONEncoder().encode(entries)
        guard let combined = try AES.GCM.seal(clear, using: key).combined else { throw HistoryStoreError.encryptionFailed }
        return magic + combined
    }

    static func loadOrCreateKey(service: String = "com.aavai.mac.history") -> Data? {
        let account = "local-history-key"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let lookup = SecItemCopyMatching(query as CFDictionary, &result)
        if lookup == errSecSuccess, let data = result as? Data { return data }
        guard lookup == errSecItemNotFound else { return nil }

        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecSuccess { return data }
        if added == errSecDuplicateItem {
            var existing: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &existing) == errSecSuccess else { return nil }
            return existing as? Data
        }
        return nil
    }
}

private struct InitialState: Sendable {
    let keyData: Data?
    let entries: [TranscriptEntry]
    let error: HistoryStoreError?
}

enum HistoryStoreError: Error, LocalizedError, Sendable {
    case keyUnavailable, encryptionFailed, unreadable
    var errorDescription: String? {
        switch self {
        case .keyUnavailable: "The history encryption key is unavailable. Existing data has not been changed."
        case .encryptionFailed: "History could not be encrypted."
        case .unreadable: "History could not be read safely. Existing data has not been changed."
        }
    }
}

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var terms: [String]
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReady = false
    private let defaults: UserDefaults
    private let keyLoader: @Sendable () -> Data?
    private var key: SymmetricKey?
    private var loading: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, keyLoader: @escaping @Sendable () -> Data? = {
        JSONHistoryStore.loadOrCreateKey(service: "com.aavai.mac.dictionary")
    }) {
        self.defaults = defaults
        self.keyLoader = keyLoader
        self.terms = []
        // No Keychain access until loading is explicitly requested by the app.
    }
    func load() async {
        if let loading { await loading.value; return }
        if isReady { return }
        let loader = keyLoader
        let task = Task { @MainActor in
            guard let data = await Task.detached(operation: loader).value, data.count == 32 else {
                errorMessage = "Dictionary encryption key unavailable. Existing terms are unchanged."; return
            }
            key = SymmetricKey(data: data)
            do {
                if let stored = defaults.data(forKey: "encryptedDictionaryV1"), let key {
                    let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: stored), using: key)
                    terms = try JSONDecoder().decode([String].self, from: clear)
                    // Merge legacy additions from a prior release before removing
                    // plaintext; never silently discard either version's entries.
                    if let legacy = defaults.stringArray(forKey: "dictionaryTerms"), !legacy.isEmpty {
                        try persist(Array(Set(terms + legacy)).sorted())
                    }
                } else {
                    try persist(defaults.stringArray(forKey: "dictionaryTerms") ?? [])
                }
                defaults.removeObject(forKey: "dictionaryTerms")
                isReady = true; errorMessage = nil
            } catch { errorMessage = "Dictionary could not be loaded safely. Existing data is unchanged." }
        }
        loading = task
        await task.value
        loading = nil
    }
    func add(_ value: String) {
        guard isReady else { return }
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) else { return }
        update((terms + [term]).sorted())
    }
    func remove(at offsets: IndexSet) {
        guard isReady else { return }
        var proposed = terms; proposed.remove(atOffsets: offsets); update(proposed)
    }
    func deleteAll() {
        guard isReady else { errorMessage = "Dictionary must be unlocked before deletion can be confirmed."; return }
        update([])
    }
    private func update(_ proposed: [String]) {
        do { try persist(proposed); defaults.removeObject(forKey: "dictionaryTerms"); errorMessage = nil }
        catch { errorMessage = "Dictionary change could not be saved." }
    }
    private func persist(_ proposed: [String]) throws {
        guard let key else { throw HistoryStoreError.keyUnavailable }
        let clear = try JSONEncoder().encode(proposed)
        guard let sealed = try AES.GCM.seal(clear, using: key).combined else { throw HistoryStoreError.encryptionFailed }
        // Authenticate before replacing anything. UserDefaults does not expose
        // durable-write errors; disk durability remains a platform limitation.
        guard try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key) == clear else {
            throw HistoryStoreError.encryptionFailed
        }
        defaults.set(sealed, forKey: "encryptedDictionaryV1")
        terms = proposed
    }
}
