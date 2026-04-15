import Foundation
import WidgetKit

// MARK: - Persistence Store
// Saves categories, expenses, income, and saving goal to disk using JSON.
// Reads are synchronous (fast, small files). Writes happen on a background queue.
//
// Storage hierarchy (highest to lowest priority):
//   1. iCloud Documents — when "veloce_icloud_sync" is true and iCloud is available (Pro).
//   2. App Group container — shared with the VeloceWidget extension.
//   3. Documents directory — final fallback.
//
// App Group: both the main app and the VeloceWidget extension share
// `group.com.veloce.shared` so the widget can read WidgetData without
// needing access to the full expense JSON.
// Set up the App Group in Xcode → Signing & Capabilities → App Groups on
// both the main target and the Widget Extension target.

// MARK: - Widget snapshot (shared with the Widget Extension via App Group)

struct VeloceWidgetData: Codable {
    let totalBudget:   Double
    let totalSpent:    Double
    let currency:      String   // AppCurrency.rawValue
    let updatedAt:     Date
}

final class PersistenceStore {

    static let shared = PersistenceStore()

    // MARK: Identifiers
    static let appGroupID      = "group.com.veloce.shared"
    static let iCloudContainer = "iCloud.com.SamCorp.Veloce"

    // MARK: Keys

    private enum Key {
        static let categories    = "veloce_categories"
        static let expenses      = "veloce_expenses"
        static let monthlyIncome = "veloce_monthly_income"
        static let savingGoal    = "veloce_saving_goal"
        static let recurring     = "veloce_recurring"
        static let widgetData    = "veloce_widget_data"
        static let iCloudSync    = "veloce_icloud_sync"
    }

    // Keys for files that should be migrated between local ↔ iCloud.
    private let migratedKeys = [Key.categories, Key.expenses, Key.recurring]

    // MARK: Private

    private let encoder   = JSONEncoder()
    private let decoder   = JSONDecoder()
    private let saveQueue = DispatchQueue(label: "veloce.persistence", qos: .utility)

    // Local baseline — App Group when configured, else Documents.
    private let localDir: URL = {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PersistenceStore.appGroupID
        ) {
            return groupURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // Resolved asynchronously by setupICloud(); nil until iCloud is confirmed available.
    // Accessed only from saveQueue after initial setup to avoid data races.
    private var iCloudDir: URL?

    // MARK: Computed directory

    // Called from saveQueue or at load time (before saveQueue is busy).
    private var effectiveDir: URL {
        if UserDefaults.standard.bool(forKey: Key.iCloudSync), let url = iCloudDir {
            return url
        }
        return localDir
    }

    private func fileURL(_ name: String) -> URL {
        effectiveDir.appendingPathComponent("\(name).json")
    }

    // MARK: Init

    private init() {
        setupICloud()
    }

    // MARK: iCloud Setup

    /// Resolves the ubiquity Documents container on a background thread (required by Apple).
    /// Once resolved, the URL is stored so subsequent writes go to iCloud.
    private func setupICloud() {
        saveQueue.async { [weak self] in
            guard let self else { return }
            guard let ubiquityURL = FileManager.default
                .url(forUbiquityContainerIdentifier: PersistenceStore.iCloudContainer)?
                .appendingPathComponent("Documents")
            else { return }   // iCloud not signed-in or not available
            try? FileManager.default.createDirectory(
                at: ubiquityURL, withIntermediateDirectories: true
            )
            self.iCloudDir = ubiquityURL
        }
    }

    // MARK: iCloud Sync Toggle (called from SettingsView)

    /// True when iCloud Drive is available on this device.
    var isICloudAvailable: Bool {
        // Check synchronously from main thread — acceptable since iCloudDir
        // is only nil until the first saveQueue task completes (~ms).
        saveQueue.sync { iCloudDir != nil }
    }

    var isICloudSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.iCloudSync)
    }

    /// Enable or disable iCloud sync. Migrates JSON files between local and iCloud storage.
    /// - Parameter enabled: The desired state.
    func setICloudSync(enabled: Bool) {
        saveQueue.async { [weak self] in
            guard let self else { return }
            guard let cloudURL = self.iCloudDir else { return }   // iCloud not available

            let src = enabled ? self.localDir : cloudURL
            let dst = enabled ? cloudURL      : self.localDir

            for key in self.migratedKeys {
                let from = src.appendingPathComponent("\(key).json")
                let to   = dst.appendingPathComponent("\(key).json")
                guard FileManager.default.fileExists(atPath: from.path) else { continue }

                // Last-write-wins: only overwrite if source is newer or destination absent.
                if FileManager.default.fileExists(atPath: to.path) {
                    let srcMod = (try? FileManager.default.attributesOfItem(atPath: from.path))?[.modificationDate] as? Date
                    let dstMod = (try? FileManager.default.attributesOfItem(atPath: to.path))?[.modificationDate] as? Date
                    if let s = srcMod, let d = dstMod, d >= s { continue }
                }

                try? FileManager.default.removeItem(at: to)
                try? FileManager.default.copyItem(at: from, to: to)
            }

            UserDefaults.standard.set(enabled, forKey: Key.iCloudSync)
        }
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

    // MARK: Recurring Expenses

    func saveRecurring(_ items: [RecurringExpense]) {
        saveJSON(items, name: Key.recurring)
    }

    func loadRecurring() -> [RecurringExpense]? {
        loadJSON([RecurringExpense].self, name: Key.recurring)
    }

    // MARK: Settings (UserDefaults — lightweight scalars)

    func saveMonthlyIncome(_ value: Double) {
        UserDefaults.standard.set(value, forKey: Key.monthlyIncome)
    }

    func loadMonthlyIncome() -> Double {
        let v = UserDefaults.standard.double(forKey: Key.monthlyIncome)
        return v > 0 ? v : 15_000_000
    }

    func saveSavingGoal(_ value: Double) {
        UserDefaults.standard.set(value, forKey: Key.savingGoal)
    }

    func loadSavingGoal() -> Double {
        let v = UserDefaults.standard.double(forKey: Key.savingGoal)
        return v > 0 ? v : 3_000_000
    }

    // MARK: Widget Data

    func saveWidgetData(_ data: VeloceWidgetData) {
        saveJSON(data, name: Key.widgetData)
        WidgetKit.WidgetCenter.shared.reloadAllTimelines()
    }

    func loadWidgetData() -> VeloceWidgetData? {
        loadJSON(VeloceWidgetData.self, name: Key.widgetData)
    }

    // MARK: Generic helpers

    /// Encodes and writes on a background thread (non-blocking).
    private func saveJSON<T: Encodable>(_ value: T, name: String) {
        do {
            let data = try encoder.encode(value)
            // Capture effectiveDir on the caller's thread (main), then write async.
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
        // At launch, iCloudDir may not yet be resolved (async setup is in-flight).
        // We check both local and iCloud (if available) and pick the newer file.
        var candidates: [URL] = [localDir.appendingPathComponent("\(name).json")]
        if let cloudURL = iCloudDir {
            candidates.append(cloudURL.appendingPathComponent("\(name).json"))
        }

        // Find the most-recently-modified file among candidates.
        let best = candidates
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max {
                let a = (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date ?? .distantPast
                let b = (try? FileManager.default.attributesOfItem(atPath: $1.path))?[.modificationDate] as? Date ?? .distantPast
                return a < b
            }

        guard let url = best else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            print("[PersistenceStore] Load error (\(name)): \(error)")
            return nil
        }
    }
}
