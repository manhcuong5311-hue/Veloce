import SwiftUI

struct CategoryDetailSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let initialCategory: Category
    @State private var currentId: UUID

    init(category: Category) {
        self.initialCategory = category
        self._currentId = State(initialValue: category.id)
    }

    @State private var editingBudget  = false
    @State private var budgetInput    = ""
    @State private var editingExpense: Expense? = nil
    @State private var showPaywall    = false

    private let budgetPresets: [(label: String, value: Double)] = [
        ("500K",   500_000),
        ("1 tr",   1_000_000),
        ("1.5 tr", 1_500_000),
        ("2 tr",   2_000_000),
        ("3 tr",   3_000_000),
        ("5 tr",   5_000_000),
        ("10 tr",  10_000_000),
    ]

    private var live: Category {
        vm.categories.first { $0.id == currentId } ?? initialCategory
    }

    // Visible categories for prev/next navigation
    private var navIndex: Int? {
        vm.visibleCategories.firstIndex { $0.id == currentId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        categoryHeader
                        budgetCard
                        if subManager.isProUser {
                            if let insight = vm.insight(for: live) {
                                insightBanner(insight)
                            }
                        } else {
                            lockedInsightBanner
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
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
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

            // Budget preset chips (shown while editing)
            if editingBudget {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(budgetPresets, id: \.label) { preset in
                            let isSel = budgetInput == "\(Int(preset.value))"
                            Button {
                                budgetInput = "\(Int(preset.value))"
                            } label: {
                                Text(preset.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSel ? .white : VeloceTheme.textPrimary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(isSel ? VeloceTheme.accent : VeloceTheme.surfaceRaised)
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(
                                                        isSel ? VeloceTheme.accent : VeloceTheme.divider,
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.spring(response: 0.2), value: isSel)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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

    // MARK: - Locked Insight (non-pro)

    private var lockedInsightBanner: some View {
        Button(action: { showPaywall = true }) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Insight available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textPrimary)
                    Text("Upgrade to Pro to unlock")
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
                Spacer()
                Text("Unlock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(VeloceTheme.accent, in: Capsule())
            }
            .padding(14)
            .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(VeloceTheme.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - Prev / Next navigation within visible categories

    private func moveBtn(_ dir: Int, _ icon: String) -> some View {
        let cats    = vm.visibleCategories
        let idx     = navIndex ?? -1
        let target  = idx + dir
        let enabled = target >= 0 && target < cats.count
        return Button {
            guard enabled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                currentId    = cats[target].id
                editingBudget = false   // reset inline budget edit on switch
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? VeloceTheme.accent : VeloceTheme.textTertiary)
                .frame(width: 30, height: 30)
                .background(
                    enabled ? VeloceTheme.accentBg : VeloceTheme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .disabled(!enabled)
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
