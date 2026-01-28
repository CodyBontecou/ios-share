import Foundation

/// Preset link format options
enum LinkFormat: String, CaseIterable, Identifiable {
    case rawURL = "raw"
    case markdownAlt = "markdown_alt"
    case html = "html"
    case bbcode = "bbcode"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rawURL: return "Raw URL"
        case .markdownAlt: return "Markdown"
        case .html: return "HTML"
        case .bbcode: return "BBCode"
        case .custom: return "Custom"
        }
    }

    var template: String {
        switch self {
        case .rawURL: return "{url}"
        case .markdownAlt: return "![{filename}]({url})"
        case .html: return "<img src=\"{url}\" alt=\"{filename}\">"
        case .bbcode: return "[img]{url}[/img]"
        case .custom: return "{url}"
        }
    }

    var previewExample: String {
        switch self {
        case .rawURL: return "https://example.com/img.jpg"
        case .markdownAlt: return "![photo.jpg](https://...)"
        case .html: return "<img src=\"https://...\">"
        case .bbcode: return "[img]https://...[/img]"
        case .custom: return "Custom format"
        }
    }
}

/// Service for formatting upload URLs based on user preferences
final class LinkFormatService {
    static let shared = LinkFormatService()

    private init() {}

    /// Current link format preference
    var currentFormat: LinkFormat {
        get {
            guard let rawValue = Config.sharedDefaults?.string(forKey: Config.linkFormatKey),
                  let format = LinkFormat(rawValue: rawValue) else {
                return .rawURL
            }
            return format
        }
        set {
            Config.sharedDefaults?.set(newValue.rawValue, forKey: Config.linkFormatKey)
        }
    }

    /// Custom format template (used when format is .custom)
    var customTemplate: String {
        get {
            Config.sharedDefaults?.string(forKey: Config.customLinkFormatKey) ?? "{url}"
        }
        set {
            Config.sharedDefaults?.set(newValue, forKey: Config.customLinkFormatKey)
        }
    }

    /// Format a URL using the current format preference
    /// - Parameters:
    ///   - url: The image URL
    ///   - filename: Optional original filename for templates that support it
    /// - Returns: Formatted string ready for clipboard
    func format(url: String, filename: String? = nil) -> String {
        let template = currentFormat == .custom ? customTemplate : currentFormat.template
        return applyTemplate(template, url: url, filename: filename)
    }

    /// Format a URL using a specific format
    /// - Parameters:
    ///   - url: The image URL
    ///   - format: The format to use
    ///   - filename: Optional original filename
    /// - Returns: Formatted string
    func format(url: String, using format: LinkFormat, filename: String? = nil) -> String {
        let template = format == .custom ? customTemplate : format.template
        return applyTemplate(template, url: url, filename: filename)
    }

    /// Preview what a format will look like with an example URL
    func preview(format: LinkFormat, customTemplate: String? = nil) -> String {
        let template = format == .custom ? (customTemplate ?? self.customTemplate) : format.template
        return applyTemplate(template, url: "https://img.example.com/abc123.jpg", filename: "photo.jpg")
    }

    // MARK: - Private

    private func applyTemplate(_ template: String, url: String, filename: String?) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{url}", with: url)

        // Extract filename from URL if not provided
        let name = filename ?? URL(string: url)?.lastPathComponent ?? "image"
        result = result.replacingOccurrences(of: "{filename}", with: name)

        return result
    }
}
