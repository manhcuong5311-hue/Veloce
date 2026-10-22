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
// Since 1.1 Veloce is free: every feature is unlocked for everyone and the
// app is supported by AdMob ads. The former lifetime product is reused as the
// one-time "Remove Ads" purchase; the yearly subscription is no longer sold.
//
// Responsibilities:
//   • `isAdFree` — Remove Ads / any past purchase (lifetime or yearly) → no ads
//   • `hasLegacyPro` — people who paid for Pro keep their 50 AI/day:
//       an active yearly subscription, or the lifetime bought before the switch
//   • AI fair-use limits (chat 5/day, expense parsing 30/day; legacy Pro 50/100)
//   • Purchase / restore of Remove Ads, out-of-band transaction updates

@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: Published

    /// Every former Pro feature is free now. Kept so the many existing
    /// `isProUser` checks simply resolve to "unlocked".
    var isProUser: Bool { true }

    /// No ads: owns Remove Ads (the lifetime product) or ever bought Pro.
    @Published private(set) var isAdFree:            Bool    = false
    /// Paid for Pro before the free switch → keeps the higher AI allowance.
    @Published private(set) var hasLegacyPro:        Bool    = false
    /// Still paying for the (no longer sold) yearly plan — shown a "you can cancel" note.
    @Published private(set) var hasActiveYearly:     Bool    = false
    @Published private(set) var products:            [Product] = []
    @Published private(set) var isLoadingProducts:   Bool    = false
    @Published              var errorMessage:        String? = nil   // shown by RemoveAdsSheet

    // MARK: AI usage

    @Published private(set) var aiMessagesUsedToday: Int = 0
    @Published private(set) var aiParsesUsedToday:   Int = 0
    static let freeAILimit    = 5
    static let proAILimit     = 50   // legacy Pro; matches CHAT_HARD_LIMIT on the server
    static let freeParseLimit = 30
    static let proParseLimit  = 100  // matches PARSE_HARD_LIMIT on the server

    /// Lifetime purchases made before this date were "Pro" purchases.
    private static let freeSwitchDate: Date =
        Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 10, day: 23)) ?? .distantFuture

    var aiDailyLimit: Int    { hasLegacyPro ? Self.proAILimit    : Self.freeAILimit }
    var parseDailyLimit: Int { hasLegacyPro ? Self.proParseLimit : Self.freeParseLimit }

    var canUseAI: Bool { aiMessagesUsedToday < aiDailyLimit }

    /// Daily AI chat allowance used up.
    var isAtOptimalLimit: Bool { aiMessagesUsedToday >= aiDailyLimit }

    var freeAIRemaining: Int { max(0, aiDailyLimit - aiMessagesUsedToday) }

    /// Cloud (LLM) expense parsing still available today; the on-device parser
    /// is used once this runs out.
    var canParseWithAI: Bool { aiParsesUsedToday < parseDailyLimit }

    // MARK: Convenience product accessors

    var lifetimeProduct: Product? { products.first { $0.id == ProductID.lifetime } }
    var yearlyProduct:   Product? { products.first { $0.id == ProductID.yearly   } }
    /// "Remove Ads" is the former lifetime product.
    var removeAdsProduct: Product? { lifetimeProduct }

    // MARK: Private

    private var transactionListener: Task<Void, Error>?
    private let proKey     = "veloce_is_pro"
    private let aiCountKey = "veloce_ai_count"
    private let aiDateKey  = "veloce_ai_date"
    private let everPurchasedKey = "veloce_ever_purchased"
    private let legacyProKey     = "veloce_legacy_pro"
    private let parseCountKey    = "veloce_ai_parse_count"

    // MARK: Init

    init() {
        // Restore cached entitlement immediately so UI is correct while the
        // async entitlement check runs in the background.
        let defaults = UserDefaults.standard
        // Anyone the old app knew as Pro stays ad-free (and keeps 50 AI/day).
        if defaults.bool(forKey: proKey) {
            defaults.set(true, forKey: everPurchasedKey)
            if defaults.object(forKey: legacyProKey) == nil { defaults.set(true, forKey: legacyProKey) }
        }
        isAdFree            = defaults.bool(forKey: everPurchasedKey)
        hasLegacyPro        = defaults.bool(forKey: legacyProKey)
        aiParsesUsedToday   = defaults.integer(forKey: parseCountKey)
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

    func recordParseUsage() {
        resetAICountIfNewDay()
        aiParsesUsedToday += 1
        UserDefaults.standard.set(aiParsesUsedToday, forKey: parseCountKey)
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

    /// Scans the user's transactions and updates `isAdFree`, `hasLegacyPro`
    /// and `hasActiveYearly` (+ their UserDefaults caches).
    ///
    /// Ad-free is sticky: anyone who ever bought the lifetime or the yearly
    /// plan stays ad-free, even after the subscription ends. We never turn it
    /// off just because nothing was found (offline / first launch).
    private func updateEntitlements() async {
        var ownsLifetime = false, lifetimeIsLegacy = false, activeYearly = false
        for await result in Transaction.currentEntitlements {
            guard let tx = try? checkVerified(result), tx.revocationDate == nil else { continue }
            switch tx.productID {
            case ProductID.lifetime:
                ownsLifetime = true
                if tx.originalPurchaseDate < Self.freeSwitchDate { lifetimeIsLegacy = true }
            case ProductID.yearly:
                activeYearly = true
            default:
                break
            }
        }

        var everPurchased = ownsLifetime || activeYearly
        if !everPurchased {
            for await result in Transaction.all {
                if let tx = try? checkVerified(result), ProductID.all.contains(tx.productID),
                   tx.revocationDate == nil {
                    everPurchased = true
                    break
                }
            }
        }

        let defaults = UserDefaults.standard
        if everPurchased {
            isAdFree = true
            defaults.set(true, forKey: everPurchasedKey)
        }
        hasActiveYearly = activeYearly
        // Legacy Pro: a lifetime from the Pro era (permanent) or a running yearly plan.
        if lifetimeIsLegacy { defaults.set(true, forKey: legacyProKey) }
        if !ownsLifetime { defaults.set(false, forKey: legacyProKey) }
        hasLegacyPro = activeYearly || defaults.bool(forKey: legacyProKey)
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
        UserDefaults.standard.set(0,     forKey: parseCountKey)
        UserDefaults.standard.set(today, forKey: aiDateKey)
        aiMessagesUsedToday = 0
        aiParsesUsedToday   = 0
    }
}

// MARK: - StoreError

enum StoreError: LocalizedError {
    case failedVerification
    var errorDescription: String? { "Transaction verification failed." }
}
