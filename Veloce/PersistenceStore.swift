import Foundation

// MARK: - Persistence Store
// Saves categories, expenses, income, and saving goal to disk using JSON.
// Reads are synchronous (fast, small files). Writes happen on a background queue.

final class PersistenceStore {

    static let shared = PersistenceStore()

    // MARK: Keys

    private enum Key {
        static let categories   = "veloce_categories"
        static let expenses     = "veloce_expenses"
        static let monthlyIncome = "veloce_monthly_income"
        static let savingGoal    = "veloce_saving_goal"
    }

    // MARK: Private

    private let encoder   = JSONEncoder()
    private let decoder   = JSONDecoder()
    private let saveQueue = DispatchQueue(label: "veloce.persistence", qos: .utility)

    private let docsDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    private func fileURL(_ name: String) -> URL {
        docsDir.appendingPathComponent("\(name).json")
    }

    // MARK: Categories

    func saveCategories(_ categories: [Category]) {
        saveJSON(categories, name: Key.categories)
    }

    func loadCategories() -> [Category]? {
        loadJSON([Category].self, name: Key.categories)
    }

    // MARK: Expenses

    func saveExpenses(_ expenses: [Expense]) {
        saveJSON(expenses, name: Key.expenses)
    }

    func loadExpenses() -> [Expense]? {
        loadJSON([Expense].self, name: Key.expenses)
    }

    // MARK: Settings (UserDefaults — lightweight scalars)

    func saveMonthlyIncome(_ value: Double) {
        UserDefaults.standard.set(value, forKey: Key.monthlyIncome)
    }

    func loadMonthlyIncome() -> Double {
        let v = UserDefaults.standard.double(forKey: Key.monthlyIncome)
        return v > 0 ? v : 15_000_000   // sensible default
    }

    func saveSavingGoal(_ value: Double) {
        UserDefaults.standard.set(value, forKey: Key.savingGoal)
    }

    func loadSavingGoal() -> Double {
        let v = UserDefaults.standard.double(forKey: Key.savingGoal)
        return v > 0 ? v : 3_000_000
    }

    // MARK: Generic helpers

    /// Encodes and writes on a background thread (non-blocking).
    private func saveJSON<T: Encodable>(_ value: T, name: String) {
        do {
            let data = try encoder.encode(value)
            let url  = fileURL(name)
            saveQueue.async {
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("[PersistenceStore] Write error (\(name)): \(error)")
                }
            }
        } catch {
            print("[PersistenceStore] Encode error (\(name)): \(error)")
        }
    }

    /// Reads synchronously (files are small; called only at app launch).
    private func loadJSON<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            print("[PersistenceStore] Load error (\(name)): \(error)")
            return nil
        }
    }
}
