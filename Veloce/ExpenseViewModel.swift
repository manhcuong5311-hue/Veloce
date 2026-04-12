import SwiftUI
import Combine

// MARK: - Parse result

enum ParseResult {
    case added                         // parsed + category found → expense added automatically
    case needsCategory(ParsedExpense)  // parsed OK but category unknown → show picker
    case failed                        // couldn't extract an amount
}

// MARK: - Expense Group (for timeline display)

struct ExpenseGroup: Identifiable {
    let id: String          // stable: ISO date string
    let title: String       // "Today", "Yesterday", "Monday, 7 Apr"
    let items: [Expense]
}

// MARK: - ViewModel

@MainActor
final class ExpenseViewModel: ObservableObject {

    // MARK: Published

    @Published var categories: [Category] = []
    @Published var expenses:   [Expense]  = []
    @Published var highlightedCategoryId: UUID? = nil
    @Published var isHeightRelative = false

    // Settings — backed by PersistenceStore
    var monthlyIncome: Double {
        didSet { PersistenceStore.shared.saveMonthlyIncome(monthlyIncome) }
    }
    var savingGoal: Double {
        didSet { PersistenceStore.shared.saveSavingGoal(savingGoal) }
    }

    // Combine auto-save
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed

    var visibleCategories: [Category] { categories.filter { !$0.isHidden } }

    var totalBudget: Double   { categories.reduce(0) { $0 + $1.budget } }
    var totalSpent:  Double   { categories.reduce(0) { $0 + $1.spent  } }
    var overallRatio: Double  { totalBudget > 0 ? min(totalSpent / totalBudget, 1) : 0 }
    var maxCategorySpent: Double { visibleCategories.map(\.spent).max() ?? 1 }

    /// Pre-sorted expenses (descending date) — used as source for grouping
    var sortedExpenses: [Expense] {
        expenses.sorted { $0.date > $1.date }
    }

    /// Timeline sections grouped by calendar day
    var expenseGroups: [ExpenseGroup] {
        let cal = Calendar.current
        let sorted = sortedExpenses
        var buckets: [(Date, [Expense])] = []
        var currentDay: Date?
        var currentItems: [Expense] = []

        for expense in sorted {
            let day = cal.startOfDay(for: expense.date)
            if let cd = currentDay, cal.isDate(cd, inSameDayAs: day) {
                currentItems.append(expense)
            } else {
                if let cd = currentDay {
                    buckets.append((cd, currentItems))
                }
                currentDay = day
                currentItems = [expense]
            }
        }
        if let cd = currentDay { buckets.append((cd, currentItems)) }

        let iso = ISO8601DateFormatter()
        return buckets.map { date, items in
            ExpenseGroup(id: iso.string(from: date), title: date.dayBucket, items: items)
        }
    }

    // MARK: Column helpers

    func barRatio(for category: Category) -> Double {
        if isHeightRelative {
            let max = maxCategorySpent
            return max > 0 ? min(category.spent / max, 1.0) : 0
        }
        return min(category.spentRatio, 1.0)
    }

    func statusColor(for category: Category) -> Color {
        switch category.spentRatio {
        case ..<0.75:  return VeloceTheme.ok
        case ..<1.0:   return VeloceTheme.caution
        default:       return VeloceTheme.over
        }
    }

    func categoryColor(for category: Category) -> Color {
        Color(hex: category.colorHex)
    }

    // MARK: CRUD

    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        adjustSpent(categoryId: expense.categoryId, delta: +expense.amount)
        highlight(expense.categoryId)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func deleteExpense(_ expense: Expense) {
        adjustSpent(categoryId: expense.categoryId, delta: -expense.amount)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            expenses.removeAll { $0.id == expense.id }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func updateExpense(_ updated: Expense, replacing old: Expense) {
        adjustSpent(categoryId: old.categoryId, delta: -old.amount)
        adjustSpent(categoryId: updated.categoryId, delta: +updated.amount)
        if let i = expenses.firstIndex(where: { $0.id == updated.id }) {
            expenses[i] = updated
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: AI input

    /// Full pipeline: parse text → match category → add or return `.needsCategory`.
    func parseExpenseResult(from text: String) -> ParseResult {
        guard let parsed = AIService.parseExpense(text) else { return .failed }

        let matched = resolveCategory(parsed.categoryName)

        if let cat = matched {
            addExpense(Expense(title: parsed.title, amount: parsed.amount,
                               categoryId: cat.id, date: parsed.date))
            return .added
        }

        return .needsCategory(parsed)
    }

    /// Resolves a detected category name to one of the user's actual categories.
    func resolveCategory(_ detectedName: String?) -> Category? {
        guard let name = detectedName else { return nil }
        let lower = name.lowercased()
        if let c = categories.first(where: { $0.name.lowercased() == lower }) { return c }
        if let c = categories.first(where: {
            lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower)
        }) { return c }
        return nil
    }

    @discardableResult
    func parseAndAddExpense(from text: String) -> Bool {
        switch parseExpenseResult(from: text) {
        case .added: return true
        default:     return false
        }
    }

    // MARK: Budget

    func updateBudget(categoryId: UUID, newBudget: Double) {
        guard let i = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            categories[i].budget = newBudget
        }
    }

    /// No-animation update used during live drag so the bar height tracks the finger without lag.
    func updateBudgetLive(categoryId: UUID, newBudget: Double) {
        guard let i = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        categories[i].budget = newBudget
    }

    func updateCategory(_ updated: Category) {
        guard let i = categories.firstIndex(where: { $0.id == updated.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            categories[i] = updated
        }
    }

    func deleteExpenses(_ items: [Expense]) {
        for exp in items { deleteExpense(exp) }
    }

    func toggleCategoryVisibility(id: UUID) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.3)) { categories[i].isHidden.toggle() }
    }

    func reorderCategories(from source: IndexSet, to destination: Int) {
        withAnimation(.spring(response: 0.3)) {
            categories.move(fromOffsets: source, toOffset: destination)
        }
    }

    func moveCategory(id: UUID, by direction: Int) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        let j = i + direction
        guard j >= 0 && j < categories.count else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            categories.swapAt(i, j)
        }
    }

    // MARK: AI

    func insight(for category: Category) -> AIInsight? {
        AIService.generateInsight(for: category, previousSpent: category.spent * 0.72)
    }

    func monthlyAdvice() -> [AIAdvice] {
        AIService.generateAdvice(income: monthlyIncome, categories: categories, savingGoal: savingGoal)
    }

    func expenses(for categoryId: UUID) -> [Expense] {
        expenses.filter { $0.categoryId == categoryId }.sorted { $0.date > $1.date }
    }

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    // MARK: Private helpers

    private func adjustSpent(categoryId: UUID, delta: Double) {
        guard let i = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            categories[i].spent += delta
        }
    }

    private func highlight(_ id: UUID) {
        highlightedCategoryId = id
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            highlightedCategoryId = nil
        }
    }

    // MARK: Default data

    private static func defaultCategories() -> [Category] {
        [
            Category(name: "Food",          icon: "fork.knife",           budget: 3_000_000, spent: 0, colorHex: "E07A5F"),
            Category(name: "Transport",     icon: "car.fill",             budget: 1_500_000, spent: 0, colorHex: "5B8DB8"),
            Category(name: "Shopping",      icon: "bag.fill",             budget: 2_000_000, spent: 0, colorHex: "9B84D0"),
            Category(name: "Bills",         icon: "bolt.fill",            budget: 2_500_000, spent: 0, colorHex: "D4A853"),
            Category(name: "Health",        icon: "heart.fill",           budget: 1_000_000, spent: 0, colorHex: "5BA88C"),
            Category(name: "Entertainment", icon: "popcorn.fill",         budget: 1_000_000, spent: 0, colorHex: "C97BA8"),
            Category(name: "Other",         icon: "ellipsis.circle.fill", budget: 500_000,   spent: 0, colorHex: "8A95A8"),
        ]
    }

    // MARK: Init — loads persisted data, then wires Combine auto-save

    init() {
        let store = PersistenceStore.shared

        // Load persisted state (or fall back to defaults)
        self.categories    = store.loadCategories() ?? Self.defaultCategories()
        self.expenses      = store.loadExpenses()   ?? []
        self.monthlyIncome = store.loadMonthlyIncome()
        self.savingGoal    = store.loadSavingGoal()

        // Auto-save whenever published collections change (debounced 400 ms)
        $categories
            .dropFirst()                         // skip the initial assignment
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { store.saveCategories($0) }
            .store(in: &cancellables)

        $expenses
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { store.saveExpenses($0) }
            .store(in: &cancellables)
    }
}
