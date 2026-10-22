import SwiftUI
import StoreKit

// MARK: - RemoveAdsSheet
//
// The only purchase in Veloce since 1.1: a one-time "Remove Ads" (the former
// lifetime product). Every feature is already free; this only turns ads off.

struct RemoveAdsSheet: View {

    @EnvironmentObject private var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var isRestoring  = false
    @State private var showError    = false

    private var isBusy: Bool { isPurchasing || isRestoring }

    private var priceText: String {
        subManager.removeAdsProduct?.displayPrice ?? "$9.99"
    }

    var body: some View {
        ZStack(alignment: .top) {
            VeloceTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 68)
                        .padding(.bottom, 28)

                    benefits
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    cta
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    footer
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
                        .foregroundStyle(VeloceTheme.textPrimary.opacity(0.4))
                        .frame(width: 30, height: 30)
                        .background(VeloceTheme.textPrimary.opacity(0.07), in: Circle())
                }
                .padding(.trailing, 20)
                .padding(.top, 58)
                .disabled(isBusy)
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
        .onChange(of: subManager.isAdFree) { _, adFree in
            if adFree && isPurchasing { dismiss() }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(VeloceTheme.accentBg)
                    .frame(width: 92, height: 92)
                Image(systemName: "nosign")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(VeloceTheme.accent)
            }
            Text("remove_ads_title")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(VeloceTheme.textPrimary)
            Text("remove_ads_subtitle")
                .font(.system(size: 15))
                .foregroundStyle(VeloceTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(spacing: 0) {
            benefitRow(icon: "eye.slash.fill", text: "remove_ads_benefit_no_ads")
            Divider().padding(.leading, 56)
            benefitRow(icon: "infinity", text: "remove_ads_benefit_once")
            Divider().padding(.leading, 56)
            benefitRow(icon: "heart.fill", text: "remove_ads_benefit_support")
        }
        .background(VeloceTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func benefitRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VeloceTheme.accent)
                .frame(width: 30, height: 30)
                .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VeloceTheme.textPrimary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VeloceTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - CTA

    @ViewBuilder
    private var cta: some View {
        if subManager.isAdFree {
            Label("remove_ads_owned", systemImage: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VeloceTheme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Button(action: purchase) {
                Group {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(String(format: String(localized: "remove_ads_cta_fmt"), priceText))
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(VeloceTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isBusy || subManager.removeAdsProduct == nil)
        }

        Button(action: restore) {
            Text(isRestoring ? "settings_restoring" : "settings_restore_purchases")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
        }
        .disabled(isBusy)
        .padding(.top, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Text("remove_ads_footer")
                .font(.system(size: 11))
                .foregroundStyle(VeloceTheme.textTertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Link(String(localized: "paywall_privacy"), destination: URL(string: "https://manhcuong5311-hue.github.io/Veloce/")!)
                Text("·").foregroundStyle(VeloceTheme.textTertiary)
                Link(String(localized: "paywall_terms"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(VeloceTheme.textSecondary)
        }
    }

    // MARK: - Actions

    private func purchase() {
        guard let product = subManager.removeAdsProduct else { return }
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await subManager.purchase(product)
                if subManager.isAdFree { dismiss() }
            } catch {
                subManager.errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            await subManager.restorePurchases()
            isRestoring = false
            if subManager.isAdFree {
                dismiss()
            } else {
                subManager.errorMessage = subManager.errorMessage ?? String(localized: "remove_ads_restore_none")
                showError = true
            }
        }
    }
}

#Preview {
    RemoveAdsSheet().environmentObject(SubscriptionManager.shared)
}
