import StoreKit
import SwiftUI
import Combine

// MARK: - Product IDs

private enum ProductID {
    static let lifetime = "com.veloce.lifetime"
    static let yearly   = "com.veloce.yearly"
    static var all: [String] { [lifetime, yearly] }
}

// MARK: - SubscriptionManager

@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    @Published private(set) var isProUser: Bool = false
    @Published private(set) var products: [Product] = []
    @Published var errorMessage: String? = nil

    // AI usage tracking
    @Published private(set) var aiMessagesUsedToday: Int = 0
    static let freeAILimit = 3
    static let proAILimit  = 50   // soft cap — never surfaced in paywall copy

    var canUseAI: Bool {
        isProUser
            ? aiMessagesUsedToday < SubscriptionManager.proAILimit
            : aiMessagesUsedToday < SubscriptionManager.freeAILimit
    }
    /// True only when a Pro user has hit the silent daily soft cap
    var isAtOptimalLimit: Bool {
        isProUser && aiMessagesUsedToday >= SubscriptionManager.proAILimit
    }
    var freeAIRemaining: Int { max(0, SubscriptionManager.freeAILimit - aiMessagesUsedToday) }

    private var transactionListener: Task<Void, Error>?
    private let proKey        = "veloce_is_pro"
    private let aiCountKey    = "veloce_ai_count"
    private let aiDateKey     = "veloce_ai_date"

    init() {
        isProUser          = UserDefaults.standard.bool(forKey: proKey)
        aiMessagesUsedToday = loadTodayAICount()
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await checkSubscriptionStatus() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: ProductID.all)
            // Lifetime first
            products = storeProducts.sorted { $0.id == ProductID.lifetime && $1.id != ProductID.lifetime }
        } catch {
            // No products configured (dev / simulator without StoreKit config)
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Check Status

    func checkSubscriptionStatus() async {
        await updatePurchasedProducts()
    }

    // MARK: - AI Usage

    func recordAIUsage() {
        resetAICountIfNewDay()
        aiMessagesUsedToday += 1
        UserDefaults.standard.set(aiMessagesUsedToday, forKey: aiCountKey)
    }

    // MARK: - Mock (Dev / Simulator without StoreKit config)

    func mockUnlockPro() {
        isProUser = true
        UserDefaults.standard.set(true, forKey: proKey)
    }

    func mockRevokePro() {
        isProUser = false
        UserDefaults.standard.set(false, forKey: proKey)
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    guard let self else { return }
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {}
            }
        }
    }

    private func updatePurchasedProducts() async {
        var purchasedIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.revocationDate == nil {
                    purchasedIDs.insert(transaction.productID)
                }
            } catch {}
        }
        let isPro = purchasedIDs.contains(ProductID.lifetime) ||
                    purchasedIDs.contains(ProductID.yearly)
        isProUser = isPro
        UserDefaults.standard.set(isPro, forKey: proKey)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let safe): return safe
        }
    }

    private func loadTodayAICount() -> Int {
        resetAICountIfNewDay()
        return UserDefaults.standard.integer(forKey: aiCountKey)
    }

    private func resetAICountIfNewDay() {
        let stored = UserDefaults.standard.string(forKey: aiDateKey) ?? ""
        let today  = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        if stored != today {
            UserDefaults.standard.set(0, forKey: aiCountKey)
            UserDefaults.standard.set(today, forKey: aiDateKey)
            aiMessagesUsedToday = 0
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
