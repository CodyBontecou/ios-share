import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "HOST\nYOUR\nIMAGES",
            subtitle: "Secure cloud storage"
        ),
        OnboardingPage(
            title: "SHARE\nFROM\nANYWHERE",
            subtitle: "iOS Share Sheet integration"
        ),
        OnboardingPage(
            title: "GET\nDIRECT\nLINKS",
            subtitle: "Instant shareable URLs"
        ),
        OnboardingPage(
            title: "STAY\nORGAN-\nIZED",
            subtitle: "All uploads in one place"
        )
    ]

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with logo
                HStack {
                    Spacer()
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, GoogleSpacing.lg)
                .padding(.top, GoogleSpacing.sm)

                // Main content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        BrutalOnboardingPageView(
                            page: page,
                            pageNumber: index + 1,
                            totalPages: pages.count
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom section
                VStack(spacing: GoogleSpacing.md) {
                    // Minimal line indicators
                    HStack(spacing: GoogleSpacing.xxs) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Rectangle()
                                .fill(index == currentPage ? Color.white : Color.white.opacity(0.2))
                                .frame(width: index == currentPage ? 24 : 12, height: 2)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    // Action buttons
                    HStack(spacing: GoogleSpacing.sm) {
                        if currentPage < pages.count - 1 {
                            Button(action: {
                                hasCompletedOnboarding = true
                            }) {
                                Text("SKIP")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        Rectangle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }

                        Button(action: {
                            if currentPage == pages.count - 1 {
                                hasCompletedOnboarding = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPage += 1
                                }
                            }
                        }) {
                            Text(currentPage == pages.count - 1 ? "START" : "NEXT")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white)
                        }
                    }
                    .padding(.horizontal, GoogleSpacing.lg)
                }
                .padding(.bottom, GoogleSpacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct BrutalOnboardingPageView: View {
    let page: OnboardingPage
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: GoogleSpacing.xl)

            // Page counter
            Text("\(pageNumber)/\(totalPages)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, GoogleSpacing.sm)

            // Giant title
            Text(page.title)
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.white)
                .lineSpacing(-8)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // Subtitle at bottom
            HStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 24, height: 1)

                Text(page.subtitle.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(2)
            }
            .padding(.bottom, GoogleSpacing.xxxl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GoogleSpacing.lg)
    }
}

#Preview {
    OnboardingView()
}
