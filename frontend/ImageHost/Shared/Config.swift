import Foundation

enum HostingMode {
    case saas           // Managed backend, pre-configured URL
    case selfHosted     // User-provided backend URL
}

struct Config {
    static let appGroup = "group.com.imagehost.shared"
    static let keychainService = "com.imagehost"
    static let keychainAccessGroup = "group.com.imagehost.shared"

    // Keys for UserDefaults
    static let backendUrlKey = "backendUrl"
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

    /// SaaS backend URL from build configuration
    static var saasBackendURL: String {
        // Read from Info.plist (injected from xcconfig via BACKEND_URL build setting)
        if let url = Bundle.main.object(forInfoDictionaryKey: "BackendURL") as? String,
           !url.isEmpty {
            return url
        }
        // Fallback to hardcoded production URL if build config not set
        return "https://img.yourdomain.com"
    }

    /// Runtime detection of hosting mode
    static var hostingMode: HostingMode {
        // Check if user has configured a custom backend URL
        if let customUrl = sharedDefaults?.string(forKey: backendUrlKey),
           !customUrl.isEmpty,
           customUrl != saasBackendURL {
            return .selfHosted
        }
        return .saas
    }

    /// The effective backend URL to use for API calls
    static var effectiveBackendURL: String {
        switch hostingMode {
        case .saas:
            return saasBackendURL
        case .selfHosted:
            return sharedDefaults?.string(forKey: backendUrlKey) ?? saasBackendURL
        }
    }

    /// Check if currently in SaaS mode
    static var isSaaSMode: Bool {
        hostingMode == .saas
    }
}
