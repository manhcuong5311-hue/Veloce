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

    private let encoder        = JSONEncoder()
    private let decoder        = JSONDecoder()
    /// Serial queue for all file I/O. Never used for slow operations (iCloud lookup, etc.)
    /// so that saveQueue.sync on the main thread always returns in < 1 ms.
    private let saveQueue      = DispatchQueue(label: "veloce.persistence",  qos: .utility)
    /// Dedicated queue for the one-time iCloud container resolution.
    /// Kept separate so that url(forUbiquityContainerIdentifier:) — which can take seconds —
    /// never blocks saveQueue and never freezes the main thread via saveQueue.sync.
    private let iCloudSetupQueue = DispatchQueue(label: "veloce.icloud.setup", qos: .background)

    // Local baseline — App Group when configured, else Documents.
    private let localDir: URL = {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PersistenceStore.appGroupID
        ) {
            return groupURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // Resolved asynchronously by setupICloud(). Read/written only on saveQueue
    // so it is always consistent with concurrent file writes.
    private var iCloudDir: URL?

    // MARK: URL helpers (called from saveQueue)

    /// Local file URL — always used for writes so loadJSON finds data at launch
    /// (iCloudDir is nil during the async startup window).
    private func localFileURL(_ name: String) -> URL {
        localDir.appendingPathComponent("\(name).json")
    }

    /// iCloud file URL — only non-nil after setupICloud completes AND sync is enabled.
    private func iCloudFileURL(_ name: String) -> URL? {
        guard UserDefaults.standard.bool(forKey: Key.iCloudSync),
              let dir = iCloudDir else { return nil }
        return dir.appendingPathComponent("\(name).json")
    }

    // MARK: Init

    private init() {
        setupICloud()
    }

    // MARK: iCloud Setup

    /// Resolves the ubiquity Documents container on iCloudSetupQueue (NOT saveQueue).
    /// url(forUbiquityContainerIdentifier:) can block for several seconds on first launch;
    /// by keeping it off saveQueue we ensure saveQueue.sync never stalls the main thread.
    private func setupICloud() {
        iCloudSetupQueue.async { [weak self] in
            guard let self else { return }
            guard let ubiquityURL = FileManager.default
                .url(forUbiquityContainerIdentifier: PersistenceStore.iCloudContainer)?
                .appendingPathComponent("Documents")
            else { return }   // iCloud not signed-in or not available
            try? FileManager.default.createDirectory(
                at: ubiquityURL, withIntermediateDirectories: true
            )
            // Publish the resolved URL on saveQueue so effectiveDir/fileURL
            // reads are serialized with all file writes.
            self.saveQueue.async { self.iCloudDir = ubiquityURL }
        }
    }

    // MARK: iCloud Sync Toggle (called from SettingsView)

    /// True when iCloud Drive is available on this device.
    var isICloudAvailable: Bool {
        // iCloudDir is only mutated on saveQueue, so reading it here is safe.
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

    /// Async save — enqueues the write to the background queue.
    /// Suitable for debounced Combine sinks; NOT guaranteed to complete before force-kill.
    func saveCategories(_ categories: [Category]) {
        print("[PersistenceStore] saveCategories (async) — \(categories.count) categories scheduled")
        saveJSON(categories, name: Key.categories)
    }

    /// Synchronous save — blocks the caller until the write is committed to disk.
    /// Use this for every structural mutation (add / edit / delete / reorder group) so data
    /// survives an immediate force-kill.
    func saveCategoriesSync(_ categories: [Category]) {
        print("[PersistenceStore] saveCategoriesSync — writing \(categories.count) categories …")
        saveJSONSync(categories, name: Key.categories)
        print("[PersistenceStore] ✅ saveCategoriesSync — committed to disk")
    }

    func loadCategories() -> [Category]? {
        let result = loadJSON([Category].self, name: Key.categories)
        if let result {
            print("[PersistenceStore] loadCategories — loaded \(result.count) categories from disk")
        } else {
            print("[PersistenceStore] loadCategories — no saved file; will use defaults")
        }
        return result
    }

    /// Blocks until all pending background writes have finished.
    /// Call from app-lifecycle hooks (scene going .inactive / .background) so
    /// any in-flight debounced saves are guaranteed to reach disk.
    func flush() {
        print("[PersistenceStore] 🔄 flush() — draining saveQueue …")
        saveQueue.sync {}
        print("[PersistenceStore] ✅ flush() — all pending writes committed")
    }

    // MARK: Expenses

    func saveExpenses(_ expenses: [Expense]) {
        saveJSON(expenses, name: Key.expenses)
    }

    /// Synchronous save — blocks the caller until the write is committed to disk.
    /// Use this for every structural mutation (add / edit / delete expense) so data
    /// survives an immediate force-kill.
    func saveExpensesSync(_ expenses: [Expense]) {
        print("[PersistenceStore] saveExpensesSync — writing \(expenses.count) expenses …")
        saveJSONSync(expenses, name: Key.expenses)
        print("[PersistenceStore] ✅ saveExpensesSync — committed to disk")
    }

    func loadExpenses() -> [Expense]? {
        loadJSON([Expense].self, name: Key.expenses)
    }

    // MARK: Recurring Expenses

    func saveRecurring(_ items: [RecurringExpense]) {
        saveJSON(items, name: Key.recurring)
    }

    /// Synchronous save for recurring expenses — guarantees write before force-kill.
    func saveRecurringSync(_ items: [RecurringExpense]) {
        print("[PersistenceStore] saveRecurringSync — writing \(items.count) recurring items …")
        saveJSONSync(items, name: Key.recurring)
        print("[PersistenceStore] ✅ saveRecurringSync — committed to disk")
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

    /// Encodes and writes on the background queue (non-blocking).
    /// Not guaranteed to complete before a force-kill — use saveJSONSync for structural data.
    private func saveJSON<T: Encodable>(_ value: T, name: String) {
        do {
            let data = try encoder.encode(value)
            saveQueue.async { [self] in
                // Always write local — loadJSON reads localDir on every launch because
                // iCloudDir is nil during the async startup window.
                do {
                    try data.write(to: localFileURL(name), options: .atomic)
                } catch {
                    print("[PersistenceStore] ❌ Async write error (local/\(name)): \(error)")
                }
                // Mirror to iCloud when sync is enabled and the container is resolved.
                if let cloudURL = iCloudFileURL(name) {
                    try? data.write(to: cloudURL, options: .atomic)
                }
            }
        } catch {
            print("[PersistenceStore] ❌ Encode error (\(name)): \(error)")
        }
    }

    /// Encodes synchronously, then blocks on saveQueue until the write is committed.
    /// saveQueue is only used for file I/O (iCloud setup has its own queue),
    /// so this returns in < 1 ms and is safe to call from the main thread.
    private func saveJSONSync<T: Encodable>(_ value: T, name: String) {
        do {
            let data = try encoder.encode(value)
            saveQueue.sync { [self] in
                // Always write local — same reason as saveJSON above.
                do {
                    try data.write(to: localFileURL(name), options: .atomic)
                } catch {
                    print("[PersistenceStore] ❌ Sync write error (local/\(name)): \(error)")
                }
                // Mirror to iCloud when sync is enabled and the container is resolved.
                if let cloudURL = iCloudFileURL(name) {
                    try? data.write(to: cloudURL, options: .atomic)
                }
            }
        } catch {
            print("[PersistenceStore] ❌ Encode error (\(name)): \(error)")
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
