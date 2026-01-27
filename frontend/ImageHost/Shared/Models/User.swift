import Foundation

struct User: Codable, Equatable {
    let id: String
    let email: String
    let subscriptionTier: String
    let subscriptionStatus: String?
    let hasSubscriptionAccess: Bool?
    let emailVerified: Bool
    let storageUsedBytes: Int
    let storageLimitBytes: Int
    let imageCount: Int?
    let uploadsRemaining: Int?
    let trialEndsAt: String?
    let trialDaysRemaining: Int?
    let currentPeriodEnd: String?

    var storageUsedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(storageUsedBytes), countStyle: .file)
    }

    var storageLimitFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(storageLimitBytes), countStyle: .file)
    }

    var storagePercentUsed: Double {
        guard storageLimitBytes > 0 else { return 0 }
        return Double(storageUsedBytes) / Double(storageLimitBytes) * 100
    }

    /// Whether user is in trial period
    var isInTrial: Bool {
        subscriptionTier == "trial" || subscriptionStatus == "trialing"
    }

    /// Whether user has any active subscription access
    var hasActiveSubscription: Bool {
        hasSubscriptionAccess ?? (subscriptionStatus == "active" || subscriptionStatus == "trialing")
    }

    /// Formatted trial end date
    var trialEndDate: Date? {
        guard let trialEndsAt = trialEndsAt else { return nil }
        return ISO8601DateFormatter().date(from: trialEndsAt)
    }

    /// Formatted subscription end date
    var subscriptionEndDate: Date? {
        guard let currentPeriodEnd = currentPeriodEnd else { return nil }
        return ISO8601DateFormatter().date(from: currentPeriodEnd)
    }

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case email
        case subscriptionTier = "subscription_tier"
        case subscriptionStatus = "subscription_status"
        case hasSubscriptionAccess = "has_subscription_access"
        case emailVerified = "email_verified"
        case storageUsedBytes = "storage_used_bytes"
        case storageLimitBytes = "storage_limit_bytes"
        case imageCount = "image_count"
        case uploadsRemaining = "uploads_remaining"
        case trialEndsAt = "trial_ends_at"
        case trialDaysRemaining = "trial_days_remaining"
        case currentPeriodEnd = "current_period_end"
    }
}
