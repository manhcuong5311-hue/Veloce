import SwiftUI
import StoreKit

// MARK: - PaywallView

struct PaywallView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PlanType = .lifetime
    @State private var isPurchasing  = false
    @State private var showError     = false
    @State private var glowPulse     = false

    enum PlanType: String {
        case lifetime = "com.veloce.lifetime"
        case yearly   = "com.veloce.yearly"
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Background ───────────────────────────────────────
            backgroundGradient

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.top, 68)
                        .padding(.bottom, 28)

                    featuresSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    planSelector
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    ctaSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    legalFooter
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                }
            }

            // ── Close ────────────────────────────────────────────
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.trailing, 20)
                .padding(.top, 58)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Purchase Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subManager.errorMessage ?? "Something went wrong. Please try again.")
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glowPulse = true } }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D0920"), Color(hex: "1A1240"), Color(hex: "0D0920")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Ambient glow blobs
            Circle()
                .fill(Color(hex: "7B6CF0").opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -60, y: -40)
            Circle()
                .fill(Color(hex: "9B8BF4").opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 100, y: 200)
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 18) {
            // Icon with animated glow ring
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color(hex: "7B6CF0").opacity(glowPulse ? 0.22 : 0.10))
                    .frame(width: 110, height: 110)
                    .blur(radius: glowPulse ? 18 : 10)
                // Main icon circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "A99CF5"), Color(hex: "7B6CF0")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(hex: "7B6CF0").opacity(0.6), radius: 20, y: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Unlock Premium")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Take full control of your finances")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            FeatureRow(
                icon: "sparkles",
                color: Color(hex: "A99CF5"),
                title: "Unlimited AI insights",
                subtitle: "Chat freely with your personal finance AI"
            )
            Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 52)
            FeatureRow(
                icon: "paintpalette.fill",
                color: Color(hex: "7EC8A4"),
                title: "Customize categories",
                subtitle: "Personalize icons & colors for every group"
            )
            Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 52)
            FeatureRow(
                icon: "arrow.up.arrow.down.circle.fill",
                color: Color(hex: "F0A070"),
                title: "Export & import your data",
                subtitle: "Back up and restore your full financial history"
            )
            Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 52)
            FeatureRow(
                icon: "bolt.fill",
                color: Color(hex: "9B8BF4"),
                title: "Faster, smarter AI responses",
                subtitle: "Priority processing for Pro members"
            )
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            PlanCard(
                title:       "Lifetime",
                price:       "$19.99",
                badge:       "BEST VALUE",
                description: "One-time payment · Yours forever",
                isSelected:  selectedPlan == .lifetime,
                onTap:       { withAnimation(.spring(response: 0.22)) { selectedPlan = .lifetime } }
            )
            PlanCard(
                title:       "Yearly",
                price:       "$9.99 / yr",
                badge:       nil,
                description: "7-day free trial · Cancel anytime",
                isSelected:  selectedPlan == .yearly,
                onTap:       { withAnimation(.spring(response: 0.22)) { selectedPlan = .yearly } }
            )
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 14) {
            // Primary
            Button(action: handlePurchase) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "A99CF5"), Color(hex: "6B5CE7")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 54)
                        .shadow(color: Color(hex: "7B6CF0").opacity(0.45), radius: 16, y: 6)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Upgrade to Premium")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isPurchasing)

            // Restore
            Button(action: handleRestore) {
                Text("Restore Purchase")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        HStack(spacing: 0) {
            Link("Privacy Policy",
                 destination: URL(string: "https://manhcuong5311-hue.github.io/Veloce/")!)
            Text("  ·  ").foregroundStyle(.white.opacity(0.2))
            Link("Terms of Use",
                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Text("  ·  ").foregroundStyle(.white.opacity(0.2))
            Button("Restore", action: handleRestore)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.28))
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func handlePurchase() {
        let productID = selectedPlan.rawValue
        if let product = subManager.products.first(where: { $0.id == productID }) {
            isPurchasing = true
            Task {
                do {
                    try await subManager.purchase(product)
                    if subManager.isProUser { dismiss() }
                } catch {
                    subManager.errorMessage = error.localizedDescription
                    showError = true
                }
                isPurchasing = false
            }
        } else {
            // Dev / Simulator: no StoreKit config → mock unlock
            subManager.mockUnlockPro()
            dismiss()
        }
    }

    private func handleRestore() {
        Task {
            await subManager.restorePurchases()
            if subManager.isProUser { dismiss() }
        }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon:     String
    let color:    Color
    let title:    String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            // Icon bubble
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let title:       String
    let price:       String
    let badge:       String?
    let description: String
    let isSelected:  Bool
    let onTap:       () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Radio
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color(hex: "A99CF5") : .white.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color(hex: "A99CF5")).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(hex: "A99CF5"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "A99CF5").opacity(0.18), in: Capsule())
                        }
                    }
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Text(price)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(hex: "7B6CF0").opacity(0.20) : .white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color(hex: "A99CF5").opacity(0.6) : .white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .animation(.spring(response: 0.22), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager.shared)
}
