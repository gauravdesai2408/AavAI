import Foundation

enum PrivacyPreferences {
    static var saveHistory: Bool { UserDefaults.standard.bool(forKey: "privacy.saveHistory") }
    static var useContext: Bool { UserDefaults.standard.bool(forKey: "privacy.useContext") }
    static var allowClipboard: Bool {
        // Preserve the established insertion workflow; users may explicitly
        // disable the clipboard fallback without disabling Accessibility insertion.
        UserDefaults.standard.object(forKey: "privacy.allowClipboard") as? Bool ?? true
    }
}
