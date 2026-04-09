import SwiftUI

struct CategoryDetailSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    let category: Category

    @State private var editingBudget  = false
    @State private var budgetInput    = ""
    @State private var editingExpense: Expense? = nil

    private var live: Category {
        vm.categories.first { $0.id == category.id } ?? category
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        categoryHeader
                        budgetCard
                        if let insight = vm.insight(for: live) {
                            insightBanner(insight)
                        }
                        transactionsSection
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(live.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        moveBtn(-1, "chevron.left")
                        moveBtn(+1, "chevron.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .sheet(item: $editingExpense) { exp in
            EditExpenseSheet(expense: exp).environmentObject(vm)
        }
    }

    // MARK: - Header

    private var categoryHeader: some View {
        HStack(spacing: 16) {
            let col = Color(hex: live.colorHex)
            ZStack {
                Circle()
                    .fill(col.opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: live.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(col)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(live.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text("\(vm.expenses(for: live.id).count) transactions this month")
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textSecondary)
            }
            Spacer()
        }
        .veloceCard()
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spent")
                        .font(.system(size: 12)).foregroundStyle(VeloceTheme.textSecondary)
                    Text(live.spent.toCurrencyString())
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: live.spent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Text("Budget")
                            .font(.system(size: 12)).foregroundStyle(VeloceTheme.textSecondary)
                        Button(action: startBudgetEdit) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(VeloceTheme.accent)
                        }
                    }
                    if editingBudget {
                        HStack(spacing: 6) {
                            TextField("", text: $budgetInput)
                                .keyboardType(.numberPad)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(VeloceTheme.accent)
                                .frame(maxWidth: 110)
                                .multilineTextAlignment(.trailing)
                            Button(action: saveBudget) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(VeloceTheme.ok)
                            }
                        }
                    } else {
                        Text(live.budget.toCurrencyString())
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(VeloceTheme.textPrimary)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(VeloceTheme.divider)
                    Capsule()
                        .fill(vm.statusColor(for: live))
                        .frame(width: geo.size.width * CGFloat(min(live.spentRatio, 1.0)))
                        .animation(.spring(response: 0.5), value: live.spentRatio)
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            // Stats row
            HStack {
                miniStat("Remaining", live.remainingBudget.toCompactCurrency(),
                         live.isOverBudget ? VeloceTheme.over : VeloceTheme.ok)
                Spacer()
                miniStat("Used", "\(Int(min(live.spentRatio, 9.99) * 100))%",
                         vm.statusColor(for: live))
                Spacer()
                miniStat("Txns", "\(vm.expenses(for: live.id).count)",
                         VeloceTheme.textSecondary)
            }
        }
        .veloceCard()
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(VeloceTheme.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    // MARK: - Insight Banner

    private func insightBanner(_ insight: AIInsight) -> some View {
        let (icon, color): (String, Color) = {
            switch insight.kind {
            case .positive: return ("checkmark.circle.fill", VeloceTheme.ok)
            case .alert:    return ("exclamationmark.triangle.fill", VeloceTheme.over)
            case .warning:  return ("exclamationmark.circle.fill", VeloceTheme.caution)
            case .info:     return ("info.circle.fill", VeloceTheme.accent)
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(insight.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VeloceTheme.textPrimary)
            Spacer()
        }
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transactions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)

            let items = vm.expenses(for: live.id)
            if items.isEmpty {
                Text("No expenses recorded yet")
                    .font(.system(size: 14))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { expense in
                        ExpenseRowView(
                            expense:  expense,
                            category: live,
                            onDelete: { vm.deleteExpense(expense) },
                            onEdit:   { editingExpense = expense }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Reorder

    private func moveBtn(_ dir: Int, _ icon: String) -> some View {
        Button(action: { vm.moveCategory(id: live.id, by: dir) }) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VeloceTheme.accent)
                .frame(width: 30, height: 30)
                .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Budget edit

    private func startBudgetEdit() {
        budgetInput = "\(Int(live.budget))"
        withAnimation(.spring(response: 0.3)) { editingBudget = true }
    }

    private func saveBudget() {
        let cleaned = budgetInput.filter { $0.isNumber }
        if let val = Double(cleaned), val > 0 {
            vm.updateBudget(categoryId: live.id, newBudget: val)
        }
        withAnimation(.spring(response: 0.3)) { editingBudget = false }
    }
}
