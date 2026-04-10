import SwiftUI
import StoreKit

// MARK: - PaywallView

struct PaywallView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PlanType = .lifetime
    @State private var isPurchasing = false
    @State private var showError    = false

    enum PlanType: String {
        case lifetime = "com.veloce.lifetime"
        case yearly   = "com.veloce.yearly"
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dark gradient background
            LinearGradient(
                colors: [Color(hex: "120D2B"), Color(hex: "1E1650"), Color(hex: "120D2B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.top, 60)
                        .padding(.bottom, 32)

                    planSelector
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    featuresSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 36)

                    ctaSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }

            // Close button
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .padding(.trailing, 20)
                .padding(.top, 56)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Purchase Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subManager.errorMessage ?? "Something went wrong. Please try again.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "9B8BF4"), Color(hex: "7B6CF0")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(hex: "7B6CF0").opacity(0.55), radius: 24, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Unlock Pro")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Smarter spending with AI")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 12) {
            PlanCard(
                title: "Lifetime",
                price: "$19.99",
                badge: "BEST VALUE",
                description: "One-time payment",
                isSelected: selectedPlan == .lifetime,
                onTap: { withAnimation(.spring(response: 0.2)) { selectedPlan = .lifetime } }
            )

            PlanCard(
                title: "Yearly",
                price: "$9.99/year",
                badge: nil,
                description: "7-day free trial · Cancel anytime",
                isSelected: selectedPlan == .yearly,
                onTap: { withAnimation(.spring(response: 0.2)) { selectedPlan = .yearly } }
            )
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProFeatureRow(icon: "brain.head.profile", title: "AI Financial Assistant")
            ProFeatureRow(icon: "chart.bar.xaxis",    title: "Smart Insights per category")
            ProFeatureRow(icon: "infinity",            title: "Unlimited expense tracking")
            ProFeatureRow(icon: "star.fill",           title: "Future premium features")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 16) {
            // Continue
            Button(action: handleContinue) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "9B8BF4"), Color(hex: "6B5CE7")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 56)
                        .shadow(color: Color(hex: "7B6CF0").opacity(0.4), radius: 12, y: 6)

                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isPurchasing)

            // Restore
            Button(action: handleRestore) {
                Text("Restore Purchases")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Not now
            Button(action: { dismiss() }) {
                Text("Not now")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Actions

    private func handleContinue() {
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
            // No StoreKit config (dev/simulator) — mock purchase
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
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color(hex: "9B8BF4") : .white.opacity(0.2),
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "9B8BF4"))
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: "9B8BF4"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(Color(hex: "9B8BF4").opacity(0.2))
                                )
                        }
                    }
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Text(price)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(hex: "7B6CF0").opacity(0.18) : .white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color(hex: "9B8BF4").opacity(0.55) : .white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ProFeatureRow

private struct ProFeatureRow: View {
    let icon:  String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "9B8BF4"))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: "9B8BF4").opacity(0.15))
                )

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "9B8BF4").opacity(0.7))
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager.shared)
}
