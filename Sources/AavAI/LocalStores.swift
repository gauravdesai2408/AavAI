import CryptoKit
import Foundation
import Security

actor JSONHistoryStore: HistoryStoring {
    private let fileURL: URL
    private let encryptionKey: SymmetricKey?
    private var entries: [TranscriptEntry]
    private static let magic = Data("AAVAI-HISTORY-1\n".utf8)

    init(fileURL: URL? = nil, keyData: Data? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "AavAI", directoryHint: .isDirectory)
        self.fileURL = fileURL ?? base.appending(path: "history.json")
        self.encryptionKey = (keyData ?? Self.loadOrCreateKey()).map(SymmetricKey.init(data:))
        let stored = try? Data(contentsOf: self.fileURL)
        if let stored, stored.starts(with: Self.magic), let encryptionKey,
           let clear = try? AES.GCM.open(AES.GCM.SealedBox(combined: stored.dropFirst(Self.magic.count)), using: encryptionKey) {
            self.entries = (try? JSONDecoder().decode([TranscriptEntry].self, from: clear)) ?? []
        } else {
            self.entries = stored.flatMap { try? JSONDecoder().decode([TranscriptEntry].self, from: $0) } ?? []
            if stored != nil, let encryptionKey,
               let migrated = try? Self.encryptedData(entries: self.entries, key: encryptionKey) {
                try? migrated.write(to: self.fileURL, options: [.atomic, .completeFileProtection])
            }
        }
    }

    func list() -> [TranscriptEntry] { entries.sorted { $0.createdAt > $1.createdAt } }
    func append(_ entry: TranscriptEntry) throws { entries.append(entry); try persist() }
    func delete(id: UUID) throws { entries.removeAll { $0.id == id }; try persist() }
    func deleteAll() throws { entries.removeAll(); try persist() }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let encryptionKey else { throw HistoryStoreError.keyUnavailable }
        let data = try Self.encryptedData(entries: entries, key: encryptionKey)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func encryptedData(entries: [TranscriptEntry], key: SymmetricKey) throws -> Data {
        let clear = try JSONEncoder().encode(entries)
        guard let combined = try AES.GCM.seal(clear, using: key).combined else { throw HistoryStoreError.encryptionFailed }
        return magic + combined
    }

    private static func loadOrCreateKey() -> Data? {
        let service = "com.aavai.mac.history"
        let account = "local-history-key"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data { return data }

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
        return added == errSecSuccess || added == errSecDuplicateItem ? data : nil
    }
}

private enum HistoryStoreError: Error { case keyUnavailable, encryptionFailed }

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var terms: [String]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.terms = defaults.stringArray(forKey: "dictionaryTerms") ?? []
    }
    func add(_ value: String) {
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) else { return }
        terms.append(term); terms.sort(); defaults.set(terms, forKey: "dictionaryTerms")
    }
    func remove(at offsets: IndexSet) { terms.remove(atOffsets: offsets); defaults.set(terms, forKey: "dictionaryTerms") }
    func deleteAll() { terms.removeAll(); defaults.removeObject(forKey: "dictionaryTerms") }
}
