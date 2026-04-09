import SwiftUI

// MARK: - Expense Row (Equatable for performance)

struct ExpenseRowView: View, Equatable {
    let expense:  Expense
    let category: Category?
    var onDelete: () -> Void = {}
    var onEdit:   () -> Void = {}

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.expense  == rhs.expense &&
        lhs.category == rhs.category
    }

    var body: some View {
        HStack(spacing: 14) {
            categoryBadge
            details
            Spacer(minLength: 8)
            amountBlock
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(VeloceTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.02),  radius: 2, x: 0, y: 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(VeloceTheme.accent)
        }
    }

    // MARK: - Sub-views

    private var categoryBadge: some View {
        let hex  = category?.colorHex ?? "8A95A8"
        let icon = category?.icon     ?? "questionmark"
        let col  = Color(hex: hex)
        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(col.opacity(0.14))
                .frame(width: 42, height: 42)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(col)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(expense.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)
                .lineLimit(1)
            Text(expense.date.toRelativeDateString())
                .font(.system(size: 12))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    private var amountBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("-\(expense.amount.toCompactCurrency())")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(VeloceTheme.textPrimary)
            if let cat = category {
                Text(cat.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: cat.colorHex).opacity(0.8))
            }
        }
    }
}

