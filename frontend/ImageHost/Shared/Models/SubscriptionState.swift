import Foundation

/// Manages subscription state across the app
@MainActor
final class SubscriptionState: ObservableObject {
    static let shared = SubscriptionState()

    @Published private(set) var status: Status = .loading
    @Published private(set) var tier: String = "free"
    @Published private(set) var trialDaysRemaining: Int?
    @Published private(set) var currentPeriodEnd: Date?
    @Published private(set) var trialEndsAt: Date?
    @Published private(set) var willRenew: Bool = false
    @Published private(set) var uploadsRemaining: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    enum Status: Equatable {
        case loading
        case noSubscription      // Never subscribed, no trial - show paywall
        case trialing            // In free trial - allow access
        case trialExpired        // Trial ended, needs subscription - show paywall
        case subscribed          // Active paid subscription - allow access
        case expired             // Subscription lapsed - show paywall
        case cancelled           // Cancelled but still active until period end

        var displayName: String {
            switch self {
            case .loading:
                return "Loading..."
            case .noSubscription:
                return "No Subscription"
            case .trialing:
                return "Free Trial"
            case .trialExpired:
                return "Trial Expired"
            case .subscribed:
                return "Pro"
            case .expired:
                return "Expired"
            case .cancelled:
                return "Cancelled"
            }
        }
    }

    /// Whether user has access to app features
    var hasAccess: Bool {
        switch status {
        case .trialing, .subscribed, .cancelled:
            return true
        default:
            return false
        }
    }

    /// Whether to show the paywall
    var shouldShowPaywall: Bool {
        switch status {
        case .noSubscription, .trialExpired, .expired:
            return true
        default:
            return false
        }
    }

    /// Check subscription status from backend
    func checkStatus() async {
        isLoading = true
        error = nil

        do {
            let response = try await SubscriptionService.shared.getSubscriptionStatus()
            updateFromResponse(response)
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            print("Failed to check subscription status: \(error)")

            // Default to no subscription on error
            status = .noSubscription
        }
    }

    /// Update state from backend response
    func updateFromResponse(_ response: SubscriptionStatusResponse) {
        tier = response.tier

        switch response.status {
        case "active":
            status = .subscribed
        case "trialing":
            status = .trialing
        case "expired":
            if response.tier == "trial" || tier == "free" {
                status = .trialExpired
            } else {
                status = .expired
            }
        case "cancelled":
            status = .cancelled
        case "none":
            status = .noSubscription
        default:
            status = .noSubscription
        }

        trialDaysRemaining = response.trialDaysRemaining
        uploadsRemaining = response.uploadsRemaining
        willRenew = response.willRenew

        if let expiresAtString = response.expiresAt {
            currentPeriodEnd = ISO8601DateFormatter().date(from: expiresAtString)
        }

        if let trialEndsAtString = response.trialEndsAt {
            trialEndsAt = ISO8601DateFormatter().date(from: trialEndsAtString)
        }
    }

    /// Reset state on logout
    func reset() {
        status = .loading
        tier = "free"
        trialDaysRemaining = nil
        currentPeriodEnd = nil
        trialEndsAt = nil
        willRenew = false
        uploadsRemaining = nil
        error = nil
    }
}

// MARK: - Response Types

struct SubscriptionStatusResponse: Codable {
    let status: String
    let tier: String
    let hasAccess: Bool
    let productId: String?
    let expiresAt: String?
    let trialEndsAt: String?
    let trialDaysRemaining: Int?
    let uploadsRemaining: Int?
    let willRenew: Bool
    let user: SubscriptionUserInfo?

    enum CodingKeys: String, CodingKey {
        case status
        case tier
        case hasAccess = "has_access"
        case productId = "product_id"
        case expiresAt = "expires_at"
        case trialEndsAt = "trial_ends_at"
        case trialDaysRemaining = "trial_days_remaining"
        case uploadsRemaining = "uploads_remaining"
        case willRenew = "will_renew"
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        tier = try container.decode(String.self, forKey: .tier)
        hasAccess = try container.decodeIfPresent(Bool.self, forKey: .hasAccess) ?? false
        productId = try container.decodeIfPresent(String.self, forKey: .productId)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        trialEndsAt = try container.decodeIfPresent(String.self, forKey: .trialEndsAt)
        trialDaysRemaining = try container.decodeIfPresent(Int.self, forKey: .trialDaysRemaining)
        uploadsRemaining = try container.decodeIfPresent(Int.self, forKey: .uploadsRemaining)
        willRenew = try container.decodeIfPresent(Bool.self, forKey: .willRenew) ?? false
        user = try container.decodeIfPresent(SubscriptionUserInfo.self, forKey: .user)
    }
}

struct SubscriptionUserInfo: Codable {
    let subscriptionTier: String
    let storageLimitBytes: Int
    let storageUsedBytes: Int
    let imageCount: Int

    enum CodingKeys: String, CodingKey {
        case subscriptionTier = "subscription_tier"
        case storageLimitBytes = "storage_limit_bytes"
        case storageUsedBytes = "storage_used_bytes"
        case imageCount = "image_count"
    }
}

struct VerifyPurchaseResponse: Codable {
    let success: Bool
    let subscription: SubscriptionInfo?
    let user: SubscriptionUserInfo?
    let error: String?

    struct SubscriptionInfo: Codable {
        let status: String
        let tier: String
        let productId: String
        let expiresAt: String
        let isTrialPeriod: Bool
        let trialEndsAt: String?

        enum CodingKeys: String, CodingKey {
            case status
            case tier
            case productId = "product_id"
            case expiresAt = "expires_at"
            case isTrialPeriod = "is_trial_period"
            case trialEndsAt = "trial_ends_at"
        }
    }
}

struct RestorePurchasesResponse: Codable {
    let success: Bool
    let message: String?
    let subscription: VerifyPurchaseResponse.SubscriptionInfo?
    let user: SubscriptionUserInfo?
    let error: String?
    let expiredAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case subscription
        case user
        case error
        case expiredAt = "expired_at"
    }
}
