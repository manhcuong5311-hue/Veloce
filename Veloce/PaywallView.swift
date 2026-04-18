import SwiftUI
import StoreKit

// MARK: - PaywallView
//
// Design decisions:
//   • Prices come from `product.displayPrice` — App Store localises them
//     automatically (e.g. "$9.99", "9,99 €", "249.000 ₫").
//   • Feature copy says "50 AI messages / day" (not "unlimited") to match
//     the actual SubscriptionManager.proAILimit = 50 hard cap.
//   • Trial copy is derived from `subManager.yearlyTrialDescription` so it
//     stays correct when the trial duration changes in App Store Connect.
//   • While products are loading we show skeleton placeholders so the layout
//     does not shift on arrival.
//   • Sandbox / simulator fallback: when products array is empty (no StoreKit
//     config present) the purchase button calls `mockUnlockPro()` so the
//     onboarding/debug flow still works.

struct PaywallView: View {

    @EnvironmentObject private var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// When set, shows a contextual "Unlock to access X" line in the hero so the
    /// user knows exactly which feature triggered the paywall.
    var triggerFeature: String? = nil

    @State private var selectedPlan: PlanType = .lifetime
    @State private var isPurchasing            = false
    @State private var isRestoring             = false
    @State private var showError               = false
    @State private var glowPulse               = false

    enum PlanType: String {
        case lifetime = "com.veloce.lifetime"
        case yearly   = "com.veloce.yearly"
    }

    // MARK: - Derived helpers

    private var lifetimeProduct: Product? { subManager.lifetimeProduct }
    private var yearlyProduct:   Product? { subManager.yearlyProduct   }

    /// App-Store-localised price string, with hardcoded fallback for simulator.
    private func price(for plan: PlanType) -> String {
        switch plan {
        case .lifetime: return lifetimeProduct?.displayPrice ?? "$19.99"
        case .yearly:   return yearlyProduct?.displayPrice   ?? "$9.99"
        }
    }

    /// Trial copy pulled from the real product offer, e.g. "7-day free trial".
    private var yearlySubtext: String {
        let trial = subManager.yearlyTrialDescription ?? String(localized: "paywall_trial_fallback")
        return "\(trial) · \(String(localized: "paywall_cancel_anytime"))"
    }

    private var isLoading: Bool { subManager.isLoadingProducts }
    private var isAnyActionRunning: Bool { isPurchasing || isRestoring }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
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

            // Close button
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.trailing, 20)
                .padding(.top, 58)
                .disabled(isAnyActionRunning)
            }
        }
        .preferredColorScheme(.dark)
        .alert("paywall_purchase_failed", isPresented: $showError) {
            Button("OK", role: .cancel) { subManager.errorMessage = nil }
        } message: {
            Text(subManager.errorMessage ?? String(localized: "paywall_error_generic"))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            // Re-fetch products if the view appears and we have none yet.
            if subManager.products.isEmpty {
                Task { await subManager.loadProducts() }
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D0920"), Color(hex: "1A1240"), Color(hex: "0D0920")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
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
            ZStack {
                Circle()
                    .fill(Color(hex: "7B6CF0").opacity(glowPulse ? 0.22 : 0.10))
                    .frame(width: 110, height: 110)
                    .blur(radius: glowPulse ? 18 : 10)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "A99CF5"), Color(hex: "7B6CF0")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(hex: "7B6CF0").opacity(0.6), radius: 20, y: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("paywall_title")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let feature = triggerFeature {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(format: String(localized: "paywall_unlock_feature_fmt"), feature))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text("paywall_hero_subtitle")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Features
    // NOTE: "50 AI messages / day" is intentional — the app enforces a hard
    // 50-message daily cap for Pro users (SubscriptionManager.proAILimit = 50).
    // Never write "unlimited" here unless the cap is removed.

    private var featuresSection: some View {
        VStack(spacing: 0) {
            FeatureRow(
                icon:  "chart.bar.doc.horizontal.fill",
                color: Color(hex: "A99CF5"),
                title: "paywall_feature_insights_title",
                subtitle: "paywall_feature_insights_subtitle"
            )
            rowDivider
            FeatureRow(
                icon:  "sparkles",
                color: Color(hex: "9B8BF4"),
                title: "paywall_feature_ai_title",
                subtitle: "paywall_feature_ai_subtitle"
            )
            rowDivider
            FeatureRow(
                icon:  "arrow.clockwise.circle.fill",
                color: Color(hex: "7EC8A4"),
                title: "paywall_feature_recurring_title",
                subtitle: "paywall_feature_recurring_subtitle"
            )
            rowDivider
            FeatureRow(
                icon:  "paintpalette.fill",
                color: Color(hex: "F0A070"),
                title: "paywall_feature_categories_title",
                subtitle: "paywall_feature_categories_subtitle"
            )
            rowDivider
            FeatureRow(
                icon:  "arrow.up.arrow.down.circle.fill",
                color: Color(hex: "5B8DB8"),
                title: "paywall_feature_history_title",
                subtitle: "paywall_feature_history_subtitle"
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

    private var rowDivider: some View {
        Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 52)
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            // Lifetime
            PlanCard(
                title:       "paywall_plan_lifetime",
                price:       isLoading ? "···"    : price(for: .lifetime),
                badge:       "paywall_plan_best_value",
                description: String(localized: "paywall_plan_lifetime_desc"),
                isSelected:  selectedPlan == .lifetime
            ) {
                withAnimation(.spring(response: 0.22)) { selectedPlan = .lifetime }
            }

            // Yearly (with trial copy from real product offer)
            PlanCard(
                title:       "paywall_plan_yearly",
                price:       isLoading ? "···"    : price(for: .yearly),
                badge:       nil,
                description: yearlySubtext,
                isSelected:  selectedPlan == .yearly
            ) {
                withAnimation(.spring(response: 0.22)) { selectedPlan = .yearly }
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 14) {
            // Primary purchase button
            Button(action: handlePurchase) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "A99CF5"), Color(hex: "6B5CE7")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(height: 54)
                        .shadow(color: Color(hex: "7B6CF0").opacity(0.45), radius: 16, y: 6)
                        .opacity(isAnyActionRunning ? 0.7 : 1.0)

                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("paywall_upgrade_btn")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isAnyActionRunning || isLoading)

            // Apple ID payment disclosure — required by App Store guidelines.
            appleIDPaymentNotice

            // Restore
            Button(action: handleRestore) {
                if isRestoring {
                    ProgressView().tint(.white.opacity(0.45)).scaleEffect(0.8)
                } else {
                    Text("paywall_restore_purchase")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .disabled(isAnyActionRunning)
        }
    }

    // MARK: - Apple ID Payment Notice
    // Apple App Store Review Guideline 3.1.1 requires paywalls to disclose
    // how and when the user will be billed before they tap the purchase button.

    @ViewBuilder
    private var appleIDPaymentNotice: some View {
        VStack(spacing: 5) {
            // Billing line — adapts to selected plan
            Group {
                if selectedPlan == .yearly, let trial = subManager.yearlyTrialDescription {
                    // e.g. "After your 7-day free trial, $9.99/year billed to your Apple ID."
                    Text(String(format: String(localized: "paywall_billing_yearly_fmt"), trial, price(for: .yearly)))
                } else {
                    // Lifetime: single charge, no renewal
                    Text(String(format: String(localized: "paywall_billing_lifetime_fmt"), price(for: .lifetime)))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.50))
            .multilineTextAlignment(.center)

            // Renewal disclosure (yearly only)
            if selectedPlan == .yearly {
                Text("paywall_billing_renewal")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.30))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.18), value: selectedPlan)
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        HStack(spacing: 0) {
            Link(String(localized: "paywall_privacy_policy"),
                 destination: URL(string: "https://manhcuong5311-hue.github.io/Veloce/")!)
            Text("  ·  ").foregroundStyle(.white.opacity(0.2))
            Link(String(localized: "paywall_terms_of_use"),
                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Text("  ·  ").foregroundStyle(.white.opacity(0.2))
            Button(String(localized: "paywall_restore_btn"), action: handleRestore)
                .disabled(isAnyActionRunning)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.28))
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func handlePurchase() {
        guard !isAnyActionRunning else { return }

        let productID = selectedPlan.rawValue
        if let product = subManager.products.first(where: { $0.id == productID }) {
            isPurchasing = true
            Task {
                defer { isPurchasing = false }
                do {
                    try await subManager.purchase(product)
                    if subManager.isProUser { dismiss() }
                } catch {
                    subManager.errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } else {
            // Dev / Simulator: StoreKit config absent → mock the unlock so
            // the rest of the app is testable.
            subManager.mockUnlockPro()
            dismiss()
        }
    }

    private func handleRestore() {
        guard !isAnyActionRunning else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            await subManager.restorePurchases()
            if subManager.isProUser { dismiss() }
            // If restore failed, `subManager.errorMessage` is set and the
            // alert binding will fire on the next render cycle.
            if subManager.errorMessage != nil { showError = true }
        }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon:     String
    let color:    Color
    let title:    LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
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
    let title:       LocalizedStringKey
    let price:       String
    let badge:       LocalizedStringKey?
    let description: String   // String (not LocalizedStringKey) because yearly
                              // description is built at runtime from product data.
    let isSelected:  Bool
    let onTap:       () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color(hex: "A99CF5") : .white.opacity(0.2),
                            lineWidth: 2
                        )
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
                    Text(verbatim: description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Price (App Store-localised via product.displayPrice)
                Text(price)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .redacted(reason: price == "···" ? .placeholder : [])
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
