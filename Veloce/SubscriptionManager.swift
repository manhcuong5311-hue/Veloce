import StoreKit
import SwiftUI
import Combine
// MARK: - Product IDs

private enum ProductID {
    static let lifetime = "com.veloce.lifetime"
    static let yearly   = "com.veloce.yearly"
    static var all: [String] { [lifetime, yearly] }
}

// MARK: - SubscriptionManager (StoreKit 2)
//
// Responsibilities:
//   • Fetch products from the App Store
//   • Purchase lifecycle (success / userCancelled / pending)
//   • Verify transactions via Transaction.currentEntitlements
//   • Listen for out-of-band updates (renewals, revocations, Ask-to-Buy)
//   • Restore via AppStore.sync()
//   • Cache entitlement in UserDefaults for offline use
//   • AI usage rate-limiting (free: 3/day, pro: 50/day)

@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: Published

    @Published private(set) var isProUser:           Bool    = false
    @Published private(set) var products:            [Product] = []
    @Published private(set) var isLoadingProducts:   Bool    = false
    @Published              var errorMessage:        String? = nil   // consumed by PaywallView

    // MARK: AI usage

    @Published private(set) var aiMessagesUsedToday: Int = 0
    static let freeAILimit = 3
    static let proAILimit  = 50  // hard cap shown in paywall as "50 AI / day"

    var canUseAI: Bool {
        isProUser
            ? aiMessagesUsedToday < SubscriptionManager.proAILimit
            : aiMessagesUsedToday < SubscriptionManager.freeAILimit
    }

    /// Pro user who has hit the daily 50-message soft cap.
    var isAtOptimalLimit: Bool {
        isProUser && aiMessagesUsedToday >= SubscriptionManager.proAILimit
    }

    var freeAIRemaining: Int {
        max(0, SubscriptionManager.freeAILimit - aiMessagesUsedToday)
    }

    // MARK: Convenience product accessors

    var lifetimeProduct: Product? { products.first { $0.id == ProductID.lifetime } }
    var yearlyProduct:   Product? { products.first { $0.id == ProductID.yearly   } }

    // MARK: Private

    private var transactionListener: Task<Void, Error>?
    private let proKey     = "veloce_is_pro"
    private let aiCountKey = "veloce_ai_count"
    private let aiDateKey  = "veloce_ai_date"

    // MARK: Init

    init() {
        // Restore cached entitlement immediately so UI is correct while the
        // async entitlement check runs in the background.
        isProUser           = UserDefaults.standard.bool(forKey: proKey)
        aiMessagesUsedToday = loadTodayAICount()
        transactionListener = listenForTransactions()

        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Load Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: ProductID.all)
            // Lifetime first, then yearly (drives the paywall card order).
            products = fetched.sorted { $0.id == ProductID.lifetime && $1.id != ProductID.lifetime }
        } catch {
            // Silently ignore — happens in dev/simulator without a StoreKit config.
            // UI falls back to hardcoded display prices.
        }
    }

    // MARK: - Purchase

    /// Returns normally on success/cancelled/pending. Throws only on system errors.
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let tx = try checkVerified(verification)
            await updateEntitlements()
            await tx.finish()
        case .userCancelled:
            break
        case .pending:
            // Ask-to-Buy or StoreKit pending — do nothing; `Transaction.updates`
            // listener will fire once approved.
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    /// Syncs the App Store receipt and re-evaluates current entitlements.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Entitlement refresh (call on launch + after purchase/restore)

    func refreshEntitlements() async {
        await updateEntitlements()
    }

    // MARK: - Trial copy helper

    /// Human-readable trial string derived from the App Store offer, e.g. "7-day free trial".
    /// Returns nil when no free trial is configured for the yearly product.
    var yearlyTrialDescription: String? {
        guard
            let offer = yearlyProduct?.subscription?.introductoryOffer,
            offer.paymentMode == .freeTrial
        else { return nil }

        let p = offer.period
        let unitString: String
        switch p.unit {
        case .day:   unitString = p.value == 1 ? "day"   : "days"
        case .week:  unitString = p.value == 1 ? "week"  : "weeks"
        case .month: unitString = p.value == 1 ? "month" : "months"
        case .year:  unitString = p.value == 1 ? "year"  : "years"
        @unknown default: unitString = "days"
        }
        return "\(p.value)-\(unitString) free trial"
    }

    // MARK: - AI Usage

    func recordAIUsage() {
        resetAICountIfNewDay()
        aiMessagesUsedToday += 1
        UserDefaults.standard.set(aiMessagesUsedToday, forKey: aiCountKey)
    }

    // MARK: - Dev / Simulator helpers (no StoreKit config)

    func mockUnlockPro() {
        isProUser = true
        UserDefaults.standard.set(true, forKey: proKey)
    }

    func mockRevokePro() {
        isProUser = false
        UserDefaults.standard.set(false, forKey: proKey)
    }

    // MARK: - Private

    /// Background task: handles renewals, revocations, and Ask-to-Buy approvals
    /// that arrive while the app is running or relaunches after approval.
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let tx = try await self.checkVerified(result)
                    await self.updateEntitlements()
                    await tx.finish()
                } catch {
                    // Unverified transaction — ignore.
                }
            }
        }
    }

    /// Scans `Transaction.currentEntitlements` for valid (non-revoked) purchases
    /// and updates `isProUser` + the UserDefaults cache.
    private func updateEntitlements() async {
        var purchasedIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            do {
                let tx = try checkVerified(result)
                // A revoked transaction means the user got a refund or the
                // subscription lapsed; exclude it.
                if tx.revocationDate == nil {
                    purchasedIDs.insert(tx.productID)
                }
            } catch {
                // Unverified — skip.
            }
        }

        let isPro = purchasedIDs.contains(ProductID.lifetime) ||
                    purchasedIDs.contains(ProductID.yearly)
        isProUser = isPro
        // Persist offline cache so the user keeps access without a network call.
        UserDefaults.standard.set(isPro, forKey: proKey)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let payload): return payload
        }
    }

    // MARK: AI count helpers

    private func loadTodayAICount() -> Int {
        resetAICountIfNewDay()
        return UserDefaults.standard.integer(forKey: aiCountKey)
    }

    private func resetAICountIfNewDay() {
        let today  = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let stored = UserDefaults.standard.string(forKey: aiDateKey) ?? ""
        guard stored != today else { return }
        UserDefaults.standard.set(0,     forKey: aiCountKey)
        UserDefaults.standard.set(today, forKey: aiDateKey)
        aiMessagesUsedToday = 0
    }
}

// MARK: - StoreError

enum StoreError: LocalizedError {
    case failedVerification
    var errorDescription: String? { "Transaction verification failed." }
}
