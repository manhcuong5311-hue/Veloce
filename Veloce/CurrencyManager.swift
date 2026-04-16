import Foundation
import SwiftUI
import Combine
// MARK: - CurrencyManager
//
// Single responsibility: currency conversion and currency-switch coordination.
//
// Architecture decision — "store in display currency, convert on change":
//   All amounts (expenses, budgets, income, saving goal) are stored in whatever
//   currency the user currently has selected. When they switch currencies we
//   convert every stored amount using the rates below, so the user always sees
//   the same real-world value regardless of the chosen display currency.
//
// Why not "always store in USD"?
//   This app launched as VND-first. A USD-base approach would require a
//   backward-compatible migration layer that could corrupt existing data during
//   import/export. Converting on-the-fly on every switch is safer and equally
//   correct for the expected (rare) currency-change use case.
//
// Exchange rates:
//   Baked-in constants serve as fallbacks. `refreshRates()` is called on launch
//   to fetch live mid-market rates from open.er-api.com (free tier, no key).
//   Conversion silently uses the fallback table when the network is unavailable.

@MainActor
final class CurrencyManager: ObservableObject {

    static let shared = CurrencyManager()

    // MARK: - Rates (USD pivot)
    // 1 USD = X units of each currency — fallback values used until refreshRates() succeeds.
    private var ratesFromUSD: [String: Double] = [
        "USD": 1.0,
        "VND": 25_400.0,
        "EUR": 0.923,
        "JPY": 149.8,
        "GBP": 0.791,
        "KRW": 1_349.0,
        "SGD": 1.345,
        "THB": 35.54,
    ]

    // MARK: - Convert

    /// Converts `amount` from one currency to another, using USD as the pivot.
    ///
    ///   convert(25_400, from: .vnd, to: .usd)  → 1.0
    ///   convert(1.0,    from: .usd, to: .vnd)  → 25_400.0
    ///
    func convert(_ amount: Double, from: AppCurrency, to: AppCurrency) -> Double {
        guard from != to, amount != 0 else { return amount }

        let fromRate = ratesFromUSD[from.rawValue] ?? 1.0
        let toRate   = ratesFromUSD[to.rawValue]   ?? 1.0

        // Step 1: normalise to USD.  Step 2: convert to target.
        return (amount / fromRate) * toRate
    }

    // MARK: - Change Currency

    /// Switches the active currency and converts ALL stored financial data so
    /// every number still represents the same real-world value.
    ///
    /// Call this instead of writing `veloce_currency` directly. The method:
    ///   1. Converts expenses, category budgets, income, and saving goal.
    ///   2. Writes the new currency key to UserDefaults *before* updating the
    ///      ViewModel so any reactive formatter calls (`toCurrencyString()`,
    ///      etc.) immediately see the new symbol and formatting rules.
    ///   3. Assigns updated collections to `vm`, triggering Combine auto-save.
    ///
    func changeCurrency(to newCurrency: AppCurrency, vm: ExpenseViewModel) {
        let oldCurrency = AppCurrency.current
        guard oldCurrency != newCurrency else { return }

        // -- Convert helper (captures old→new pair) --
        let doConvert: (Double) -> Double = { [self] amount in
            self.convert(amount, from: oldCurrency, to: newCurrency)
        }

        // 1. Convert all expense amounts.
        let convertedExpenses = vm.expenses.map { expense -> Expense in
            var e = expense
            e.amount = doConvert(e.amount)
            return e
        }

        // 2. Convert category budgets.
        //    Recompute `spent` from the freshly-converted expenses rather than
        //    converting the old `spent` value — this keeps totals consistent
        //    and avoids floating-point drift from double conversions.
        let convertedCategories = vm.categories.map { cat -> Category in
            var c = cat
            c.budget = doConvert(c.budget)
            c.spent  = convertedExpenses
                .filter { $0.categoryId == c.id }
                .reduce(0) { $0 + $1.amount }
            return c
        }

        // 3. Convert income and saving goal.
        let convertedIncome      = doConvert(vm.monthlyIncome)
        let convertedSavingGoal  = doConvert(vm.savingGoal)

        // 4. Persist the new currency key FIRST so formatters use the correct
        //    symbol and decimal rules when the ViewModel publishes its changes.
        UserDefaults.standard.set(newCurrency.rawValue, forKey: "veloce_currency")

        // 5. Sync-save all converted amounts immediately.
        //    The currency key (step 4) and the converted amounts MUST be consistent
        //    on disk. Without this, a force-kill between the key write and the
        //    debounced Combine saves would leave new-currency key + old-currency
        //    amounts on disk — causing wildly wrong values on next launch
        //    (e.g. 100,000 VND stored but read as $100,000 USD).
        let store = PersistenceStore.shared
        store.saveCategoriesSync(convertedCategories)
        store.saveExpensesSync(convertedExpenses)
        store.saveMonthlyIncome(convertedIncome)   // UserDefaults — synchronous by nature
        store.saveSavingGoal(convertedSavingGoal)  // UserDefaults — synchronous by nature

        // 6. Push updates to the ViewModel (triggers UI refresh).
        //    The Combine sinks will fire another write, but the data is already
        //    safely on disk — those writes are harmless belt-and-suspenders.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            vm.expenses      = convertedExpenses
            vm.categories    = convertedCategories
            vm.monthlyIncome = convertedIncome
            vm.savingGoal    = convertedSavingGoal
        }
    }

    // MARK: - Live Rate Fetch

    /// Fetches up-to-date mid-market exchange rates and updates the internal
    /// rate table. Uses open.er-api.com (free tier, no API key required).
    /// Falls back silently — baked-in constants remain active on network failure.
    func refreshRates() async throws {
        struct ERResponse: Decodable {
            let result: String
            let rates:  [String: Double]
        }

        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(ERResponse.self, from: data)

        guard resp.result == "success" else { return }

        // Only update currencies the app actually supports.
        let supported = Set(AppCurrency.allCases.map(\.rawValue))
        for (code, rate) in resp.rates where supported.contains(code) {
            ratesFromUSD[code] = rate
        }
    }

    // MARK: - Rate for display (optional helper)

    /// Returns the exchange rate between two currencies, e.g. for informational UI.
    func rate(from: AppCurrency, to: AppCurrency) -> Double {
        convert(1.0, from: from, to: to)
    }
}
