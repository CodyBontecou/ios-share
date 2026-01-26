import Foundation

struct Config {
    static let appGroup = "group.com.imagehost.shared"
    static let keychainService = "com.imagehost"
    static let keychainAccessGroup = "group.com.imagehost.shared"

    // Keys for Keychain (legacy - kept for migration)
    static let uploadTokenKey = "uploadToken"

    // History file name
    static let historyFileName = "upload_history.json"
    static let maxHistoryCount = 100

    // Image processing
    static let maxUploadDimension: CGFloat = 4096
    static let thumbnailSize: CGFloat = 200
    static let jpegQuality: CGFloat = 0.85

    // Shared UserDefaults
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    // Shared container URL
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    // MARK: - Backend Configuration

    /// Backend URL from build configuration
    static var backendURL: String {
        // Read from Info.plist (injected from xcconfig via BACKEND_URL build setting)
        if let url = Bundle.main.object(forInfoDictionaryKey: "BackendURL") as? String,
           !url.isEmpty {
            return url
        }
        // Fallback to hardcoded production URL if build config not set
        return "https://img.yourdomain.com"
    }
}
