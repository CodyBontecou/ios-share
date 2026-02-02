import Foundation

struct Config {
    static let appGroup = "group.com.imghost.shared"
    static let keychainService = "com.imghost"
    static let keychainAccessGroup = "group.com.imghost.shared"

    // Keys for Keychain (legacy - kept for migration)
    static let uploadTokenKey = "uploadToken"

    // History file name
    static let historyFileName = "upload_history.json"
    static let maxHistoryCount = 100

    // Image processing
    static let maxUploadDimension: CGFloat = 4096
    static let thumbnailSize: CGFloat = 400
    static let thumbnailQuality: CGFloat = 0.85
    static let jpegQuality: CGFloat = 0.85

    // Link Format Settings
    static let linkFormatKey = "linkFormat"
    static let customLinkFormatKey = "customLinkFormat"

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
