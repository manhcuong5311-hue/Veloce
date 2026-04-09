import SwiftUI
import Combine

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

    // Settings
    var monthlyIncome: Double = 15_000_000
    var savingGoal:    Double = 3_000_000

    // MARK: Computed (cached via lazy pattern in body)

    var totalBudget: Double   { categories.reduce(0) { $0 + $1.budget } }
    var totalSpent:  Double   { categories.reduce(0) { $0 + $1.spent  } }
    var overallRatio: Double  { totalBudget > 0 ? min(totalSpent / totalBudget, 1) : 0 }
    var maxCategorySpent: Double { categories.map(\.spent).max() ?? 1 }

    /// Pre-sorted expenses (descending date) — used as source for grouping
    var sortedExpenses: [Expense] {
        expenses.sorted { $0.date > $1.date }
    }

    /// Timeline sections grouped by calendar day
    var expenseGroups: [ExpenseGroup] {
        let cal = Calendar.current
        let sorted = sortedExpenses
        // Group by start-of-day
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

    @discardableResult
    func parseAndAddExpense(from text: String) -> Bool {
        guard let parsed = AIService.parseExpense(text) else { return false }
        let cat = categories.first { $0.name == parsed.categoryName }
            ?? categories.first { $0.name == "Other" }
            ?? categories.first
        guard let cat else { return false }
        addExpense(Expense(
            title:      parsed.title,
            amount:     parsed.amount,
            categoryId: cat.id,
            date:       parsed.date
        ))
        return true
    }

    // MARK: Budget

    func updateBudget(categoryId: UUID, newBudget: Double) {
        guard let i = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            categories[i].budget = newBudget
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

    // MARK: Private

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

    // MARK: Mock data

    init() { loadMockData() }

    private func loadMockData() {
        // Pastel colors calibrated for light backgrounds
        categories = [
            Category(name: "Food",          icon: "fork.knife",           budget: 3_000_000, spent: 2_100_000, colorHex: "E07A5F"),
            Category(name: "Transport",     icon: "car.fill",             budget: 1_500_000, spent: 890_000,   colorHex: "5B8DB8"),
            Category(name: "Shopping",      icon: "bag.fill",             budget: 2_000_000, spent: 2_350_000, colorHex: "9B84D0"),
            Category(name: "Bills",         icon: "bolt.fill",            budget: 2_500_000, spent: 1_200_000, colorHex: "D4A853"),
            Category(name: "Health",        icon: "heart.fill",           budget: 1_000_000, spent: 450_000,   colorHex: "5BA88C"),
            Category(name: "Entertainment", icon: "popcorn.fill",         budget: 1_000_000, spent: 800_000,   colorHex: "C97BA8"),
            Category(name: "Other",         icon: "ellipsis.circle.fill", budget: 500_000,   spent: 120_000,   colorHex: "8A95A8"),
        ]

        let now = Date()
        let cal = Calendar.current
        func ago(_ days: Int, hour: Int = 12) -> Date {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour; comps.minute = Int.random(in: 0...59)
            if let base = cal.date(from: comps) {
                return cal.date(byAdding: .day, value: -days, to: base) ?? now
            }
            return now
        }

        let items: [(String, Double, String, Int, Int)] = [
            ("Phở bò Quỳnh Anh",    55_000,  "Food",          0,  7),
            ("Grab Bike đi làm",     38_000,  "Transport",     0,  8),
            ("Cà phê sữa đá",        35_000,  "Food",          0,  8),
            ("Cơm trưa văn phòng",   55_000,  "Food",          0, 12),
            ("Grab về nhà",          42_000,  "Transport",     0, 18),
            ("Trà sữa Gong Cha",     65_000,  "Food",          0, 15),
            ("Dinner gia đình",     350_000,  "Food",          0, 19),
            ("Cà phê sáng",          40_000,  "Food",          1,  8),
            ("Xe bus",               10_000,  "Transport",     1,  7),
            ("Bún chả trưa",         60_000,  "Food",          1, 12),
            ("Áo thun Uniqlo",      350_000,  "Shopping",      2, 14),
            ("Grab chiều",           45_000,  "Transport",     2, 17),
            ("Điện tháng 4",        450_000,  "Bills",         3, 10),
            ("Wifi VNPT",           200_000,  "Bills",         3, 10),
            ("Bánh mì sáng",         25_000,  "Food",          3,  7),
            ("Gym tháng",           300_000,  "Health",        5, 18),
            ("Netflix Premium",     180_000,  "Entertainment", 5, 20),
            ("Vitamin C Kirkland",  150_000,  "Health",        7, 20),
            ("Giày Nike Air Max",   800_000,  "Shopping",      4, 15),
            ("Nước uống",            15_000,  "Food",          5, 14),
            ("Vé CGV Avengers",     120_000,  "Entertainment", 6, 19),
            ("Shopee order",      1_200_000,  "Shopping",      6, 11),
            ("Xăng xe máy",         200_000,  "Transport",     7,  8),
            ("Bún bò Huế",           60_000,  "Food",          8,  7),
            ("Khám sức khoẻ",       250_000,  "Health",        9, 10),
        ]

        expenses = items.compactMap { title, amount, catName, days, hour in
            guard let cat = categories.first(where: { $0.name == catName }) else { return nil }
            return Expense(title: title, amount: amount, categoryId: cat.id, date: ago(days, hour: hour))
        }
    }
}
