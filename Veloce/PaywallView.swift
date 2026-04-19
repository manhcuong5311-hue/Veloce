import SwiftUI
import StoreKit

// MARK: - PaywallView
//
// Design decisions:
//   • Prices come from `product.displayPrice` — App Store localises them
//     automatically (e.g. "$9.99", "9,99 €", "249.000 ₫").
//   • Yearly plan shows a per-month equivalent (product.price / 12) so the
//     user sees a smaller number ("$0.83/mo") with the annual total below.
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

    /// Monthly equivalent for the yearly plan, formatted in the correct locale.
    private var yearlyMonthlyPrice: String {
        guard let product = yearlyProduct else { return "$0.83" }
        let monthly = product.price / 12
        return monthly.formatted(product.priceFormatStyle)
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
            Color(hex: "F7F4EF").ignoresSafeArea()

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
                        .foregroundStyle(Color(hex: "1C1C1E").opacity(0.4))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "1C1C1E").opacity(0.07), in: Circle())
                }
                .padding(.trailing, 20)
                .padding(.top, 58)
                .disabled(isAnyActionRunning)
            }
        }
        .alert("paywall_purchase_failed", isPresented: $showError) {
            Button("OK", role: .cancel) { subManager.errorMessage = nil }
        } message: {
            Text(subManager.errorMessage ?? String(localized: "paywall_error_generic"))
        }
        .onAppear {
            if subManager.products.isEmpty {
                Task { await subManager.loadProducts() }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color(hex: "6B5CE7").opacity(0.10))
                    .frame(width: 90, height: 90)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "A99CF5"), Color(hex: "6B5CE7")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: Color(hex: "6B5CE7").opacity(0.25), radius: 12, y: 5)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("paywall_title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "1C1C1E"))

                if let feature = triggerFeature {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(format: String(localized: "paywall_unlock_feature_fmt"), feature))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "6B5CE7"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(hex: "6B5CE7").opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: "6B5CE7").opacity(0.2), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text("paywall_hero_subtitle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "6C6C72"))
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
                color: Color(hex: "6B5CE7"),
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
                color: Color(hex: "34C759"),
                title: "paywall_feature_recurring_title",
                subtitle: "paywall_feature_recurring_subtitle"
            )
            rowDivider
            FeatureRow(
                icon:  "paintpalette.fill",
                color: Color(hex: "FF9F0A"),
                title: "paywall_feature_categories_title",
                subtitle: "paywall_feature_categories_subtitle"
            )
            rowDivider
            FeatureRow(
                icon:  "arrow.up.arrow.down.circle.fill",
                color: Color(hex: "007AFF"),
                title: "paywall_feature_history_title",
                subtitle: "paywall_feature_history_subtitle"
            )
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color(hex: "EBEBEB"))
            .padding(.leading, 52)
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            // Lifetime
            PlanCard(
                title:        "paywall_plan_lifetime",
                price:        isLoading ? "···" : price(for: .lifetime),
                priceSubtext: nil,
                badge:        "paywall_plan_best_value",
                description:  String(localized: "paywall_plan_lifetime_desc"),
                isSelected:   selectedPlan == .lifetime
            ) {
                withAnimation(.spring(response: 0.22)) { selectedPlan = .lifetime }
            }

            // Yearly — lead with per-month equivalent, annual total below
            PlanCard(
                title:        "paywall_plan_yearly",
                price:        isLoading ? "···" : "\(yearlyMonthlyPrice)/mo",
                priceSubtext: isLoading ? nil : "\(price(for: .yearly))/yr",
                badge:        nil,
                description:  yearlySubtext,
                isSelected:   selectedPlan == .yearly
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
                        .opacity(isAnyActionRunning ? 0.7 : 1.0)

                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("paywall_upgrade_btn")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: Color(hex: "6B5CE7").opacity(0.30), radius: 12, y: 5)
            }
            .disabled(isAnyActionRunning || isLoading)

            // Apple ID payment disclosure — required by App Store guidelines.
            appleIDPaymentNotice

            // Restore
            Button(action: handleRestore) {
                if isRestoring {
                    ProgressView().tint(Color(hex: "8E8E93")).scaleEffect(0.8)
                } else {
                    Text("paywall_restore_purchase")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "8E8E93"))
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
            .foregroundStyle(Color(hex: "8E8E93"))
            .multilineTextAlignment(.center)

            // Renewal disclosure (yearly only)
            if selectedPlan == .yearly {
                Text("paywall_billing_renewal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "AEAEB2"))
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
            Text("  ·  ").foregroundStyle(Color(hex: "C7C7CC"))
            Link(String(localized: "paywall_terms_of_use"),
                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Text("  ·  ").foregroundStyle(Color(hex: "C7C7CC"))
            Button(String(localized: "paywall_restore_btn"), action: handleRestore)
                .disabled(isAnyActionRunning)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(hex: "AEAEB2"))
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
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let title:        LocalizedStringKey
    let price:        String
    let priceSubtext: String?   // e.g. "$9.99/yr" shown below the monthly price
    let badge:        LocalizedStringKey?
    let description:  String    // String (not LocalizedStringKey) because yearly
                                // description is built at runtime from product data.
    let isSelected:   Bool
    let onTap:        () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color(hex: "6B5CE7") : Color(hex: "C7C7CC"),
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color(hex: "6B5CE7")).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(hex: "6B5CE7"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "6B5CE7").opacity(0.10), in: Capsule())
                        }
                    }
                    Text(verbatim: description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8E8E93"))
                }

                Spacer()

                // Price column — two lines when priceSubtext is provided
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .redacted(reason: price == "···" ? .placeholder : [])
                    if let subtext = priceSubtext {
                        Text(subtext)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "8E8E93"))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(hex: "6B5CE7").opacity(0.06) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color(hex: "6B5CE7").opacity(0.65) : Color(hex: "E8E3DC"),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.0 : 0.04), radius: 6, y: 2)
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
