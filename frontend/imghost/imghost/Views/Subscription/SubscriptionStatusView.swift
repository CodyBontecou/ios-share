import SwiftUI

struct SubscriptionStatusView: View {
    @EnvironmentObject var subscriptionState: SubscriptionState
    @EnvironmentObject var authState: AuthState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SUBSCRIPTION")
                    .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.brutalSurface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.brutalBorder),
                alignment: .bottom
            )

            // Status Card
            VStack(spacing: 16) {
                // Plan Badge
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CURRENT PLAN")
                            .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            .tracking(1)

                        HStack(spacing: 8) {
                            Text(planDisplayName)
                                .brutalTypography(.titleMedium)

                            statusBadge
                        }
                    }

                    Spacer()
                }

                // Trial/Subscription Info
                if let info = statusInfo {
                    HStack {
                        Image(systemName: info.icon)
                            .foregroundColor(info.color)

                        Text(info.text)
                            .brutalTypography(.bodyMedium, color: info.color)

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        Rectangle()
                            .stroke(info.color.opacity(0.5), lineWidth: 1)
                    )
                }

                // Manage Subscription Button
                if subscriptionState.status == .subscribed || subscriptionState.status == .trialing {
                    BrutalSecondaryButton(title: "Manage Subscription") {
                        openSubscriptionManagement()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
            .background(Color.brutalBackground)
        }
    }

    // MARK: - Computed Properties

    private var planDisplayName: String {
        switch subscriptionState.status {
        case .trialing:
            return "PRO TRIAL"
        case .subscribed:
            return "PRO"
        case .cancelled:
            return "PRO (CANCELLED)"
        default:
            return "FREE"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch subscriptionState.status {
        case .trialing:
            BrutalBadge(text: "TRIAL", style: .warning)
        case .subscribed:
            BrutalBadge(text: "ACTIVE", style: .success)
        case .cancelled:
            BrutalBadge(text: "CANCELLED", style: .warning)
        case .expired, .trialExpired:
            BrutalBadge(text: "EXPIRED", style: .error)
        default:
            EmptyView()
        }
    }

    private var statusInfo: (icon: String, text: String, color: Color)? {
        switch subscriptionState.status {
        case .trialing:
            if let days = subscriptionState.trialDaysRemaining {
                return (
                    icon: "clock.fill",
                    text: days == 1 ? "Trial ends tomorrow" : "Trial ends in \(days) days",
                    color: days <= 2 ? .brutalWarning : .brutalTextSecondary
                )
            }
            return nil

        case .subscribed:
            if let endDate = subscriptionState.currentPeriodEnd {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let dateString = formatter.string(from: endDate)
                return (
                    icon: subscriptionState.willRenew ? "arrow.triangle.2.circlepath" : "xmark.circle",
                    text: subscriptionState.willRenew ? "Renews on \(dateString)" : "Expires on \(dateString)",
                    color: .brutalTextSecondary
                )
            }
            return nil

        case .cancelled:
            if let endDate = subscriptionState.currentPeriodEnd {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let dateString = formatter.string(from: endDate)
                return (
                    icon: "exclamationmark.triangle",
                    text: "Access until \(dateString)",
                    color: .brutalWarning
                )
            }
            return nil

        case .expired, .trialExpired:
            return (
                icon: "xmark.circle.fill",
                text: "Your subscription has expired",
                color: .brutalError
            )

        default:
            return nil
        }
    }

    // MARK: - Actions

    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SubscriptionStatusView()
        .environmentObject(SubscriptionState.shared)
        .environmentObject(AuthState.shared)
        .background(Color.brutalBackground)
}
