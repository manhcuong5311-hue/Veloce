import Foundation

// MARK: - Core Data Models

struct Category: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var budget: Double
    var spent: Double
    var colorHex: String
    var isHidden: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        budget: Double,
        spent: Double = 0,
        colorHex: String = "7B6FF0",
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.budget = budget
        self.spent = spent
        self.colorHex = colorHex
        self.isHidden = isHidden
    }

    var spentRatio: Double {
        guard budget > 0 else { return 0 }
        return spent / budget
    }

    var remainingBudget: Double { max(0, budget - spent) }
    var isOverBudget: Bool { spent > budget }
}

struct Expense: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var amount: Double
    var categoryId: UUID
    var date: Date

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        categoryId: UUID,
        date: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.categoryId = categoryId
        self.date = date
    }
}

// MARK: - AI Types

struct ParsedExpense: Identifiable {
    let id = UUID()
    var title: String
    var amount: Double
    /// nil = no keyword matched — caller should ask user to pick a group
    var categoryName: String?
    var date: Date
}

struct AIInsight: Equatable {
    enum Kind { case warning, alert, positive, info }
    var message: String
    var kind: Kind
}

struct AIAdvice {
    var category: String
    var suggestion: String
    var potentialSaving: Double
}

// MARK: - Export / Import Envelope

struct VeloceExportData: Codable {
    let exportDate:    Date
    let version:       String
    let categories:    [Category]
    let expenses:      [Expense]
    let monthlyIncome: Double
    let savingGoal:    Double
}
