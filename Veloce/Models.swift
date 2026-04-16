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
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        categoryId: UUID,
        date: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.categoryId = categoryId
        self.date = date
        self.note = note
    }

    // Custom decoder for backward compatibility — old exports lack `note`
    enum CodingKeys: String, CodingKey { case id, title, amount, categoryId, date, note }

    init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        amount     = try c.decode(Double.self, forKey: .amount)
        categoryId = try c.decode(UUID.self,   forKey: .categoryId)
        date       = try c.decode(Date.self,   forKey: .date)
        note       = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
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

// MARK: - Recurring Transactions

struct RecurringExpense: Codable, Identifiable {

    enum Frequency: String, Codable, CaseIterable {
        case daily, weekly, monthly

        var label: String {
            switch self {
            case .daily:   return "Daily"
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            }
        }

        var sfSymbol: String {
            switch self {
            case .daily:   return "sun.max.fill"
            case .weekly:  return "calendar.badge.clock"
            case .monthly: return "calendar"
            }
        }
    }

    var id: UUID
    var title: String
    var amount: Double
    var categoryId: UUID
    var frequency: Frequency
    var nextDueDate: Date
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        categoryId: UUID,
        frequency: Frequency = .monthly,
        nextDueDate: Date = Date(),
        note: String = ""
    ) {
        self.id          = id
        self.title       = title
        self.amount      = amount
        self.categoryId  = categoryId
        self.frequency   = frequency
        self.nextDueDate = nextDueDate
        self.note        = note
    }

    var isDue: Bool { nextDueDate <= Date() }

    /// Advance nextDueDate by one frequency period.
    mutating func advance() {
        let cal = Calendar.current
        switch frequency {
        case .daily:
            nextDueDate = cal.date(byAdding: .day,        value: 1, to: nextDueDate) ?? nextDueDate
        case .weekly:
            nextDueDate = cal.date(byAdding: .weekOfYear, value: 1, to: nextDueDate) ?? nextDueDate
        case .monthly:
            nextDueDate = cal.date(byAdding: .month,      value: 1, to: nextDueDate) ?? nextDueDate
        }
    }
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
