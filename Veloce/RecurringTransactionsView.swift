import SwiftUI

// MARK: - Recurring Transactions View (Pro-only)

struct RecurringTransactionsView: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                if vm.recurringExpenses.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(vm.recurringExpenses) { item in
                                RecurringRow(item: item)
                                    .environmentObject(vm)
                                    .listRowBackground(VeloceTheme.surface)
                                    .listRowSeparatorTint(VeloceTheme.divider)
                            }
                            .onDelete { offsets in
                                for i in offsets {
                                    vm.deleteRecurring(vm.recurringExpenses[i])
                                }
                            }
                        } header: {
                            Text("recurring_auto_logged_hint")
                                .font(.system(size: 11))
                                .foregroundStyle(VeloceTheme.textTertiary)
                                .textCase(nil)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(String(localized: "Recurring"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VeloceTheme.accent)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAddSheet) {
            AddRecurringSheet()
                .environmentObject(vm)
                .environmentObject(subManager)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VeloceTheme.accentBg)
                    .frame(width: 72, height: 72)
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(VeloceTheme.accent)
            }
            VStack(spacing: 6) {
                Text("recurring_empty_title")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text("recurring_empty_hint")
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("recurring_add_btn")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(VeloceTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }
}

// MARK: - Recurring Row

private struct RecurringRow: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let item: RecurringExpense

    private var categoryColor: Color {
        guard let cat = vm.categories.first(where: { $0.id == item.categoryId }) else {
            return VeloceTheme.accent
        }
        return Color(hex: cat.colorHex)
    }

    private var categoryIcon: String {
        vm.categories.first(where: { $0.id == item.categoryId })?.icon ?? "folder.fill"
    }

    private var categoryName: String {
        vm.categories.first(where: { $0.id == item.categoryId })?.name ?? "—"
    }

    private var nextDueDateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(item.nextDueDate)     { return String(localized: "recurring_due_today") }
        if cal.isDateInTomorrow(item.nextDueDate)  { return String(localized: "recurring_due_tomorrow") }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: item.nextDueDate)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(categoryColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(categoryColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                HStack(spacing: 6) {
                    Image(systemName: item.frequency.sfSymbol)
                        .font(.system(size: 10))
                    Text(item.frequency.localizedLabel)
                        .font(.system(size: 12))
                    Text("·")
                        .foregroundStyle(VeloceTheme.textTertiary)
                    Text(nextDueDateLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(item.isDue ? VeloceTheme.over : VeloceTheme.textSecondary)
                }
                .foregroundStyle(VeloceTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.amount.toCompactCurrency())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text(categoryName)
                    .font(.system(size: 11))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Add Recurring Sheet

struct AddRecurringSheet: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var title          = ""
    @State private var amountText     = ""
    @State private var selectedCatId: UUID?
    @State private var frequency:     RecurringExpense.Frequency = .monthly
    @State private var startDate      = Date()
    @State private var note           = ""

    private var parsedAmount: Double? { Double(amountText.filter { $0.isNumber }) }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && (parsedAmount ?? 0) > 0
        && selectedCatId != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Amount hero
                        VStack(spacing: 6) {
                            Text("expense.amount")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(VeloceTheme.textSecondary)
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                if AppCurrency.current.symbolLeading {
                                    Text(AppCurrency.current.symbol)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(VeloceTheme.textTertiary)
                                        .offset(y: -3)
                                }
                                TextField("0", text: $amountText)
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(VeloceTheme.textPrimary)
                                    .tint(VeloceTheme.accent)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 200)
                                    .onChange(of: amountText) { _, v in
                                        let d = v.filter { $0.isNumber }
                                        let f = Double.formatAmountInput(d)
                                        if f != amountText { amountText = f }
                                    }
                                if !AppCurrency.current.symbolLeading {
                                    Text(AppCurrency.current.symbol)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(VeloceTheme.textTertiary)
                                        .offset(y: -3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .veloceCard(radius: 22)

                        // Details
                        VStack(spacing: 0) {
                            formRow("Title") {
                                TextField(String(localized: "recurring_title_placeholder"), text: $title)
                                    .font(.system(size: 15))
                                    .foregroundStyle(VeloceTheme.textPrimary)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                            }
                            thinDivider

                            formRow("Frequency") {
                                Picker("", selection: $frequency) {
                                    ForEach(RecurringExpense.Frequency.allCases, id: \.self) { f in
                                        Text(f.localizedLabel).tag(f)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 200)
                            }
                            thinDivider

                            formRow("First due") {
                                DatePicker("", selection: $startDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .tint(VeloceTheme.accent)
                            }
                            thinDivider

                            formRow("Category") { categoryScroll }
                        }
                        .veloceCard()

                        Button(action: save) {
                            Text("recurring_add_btn")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isValid ? VeloceTheme.accent : VeloceTheme.divider)
                                )
                        }
                        .disabled(!isValid)
                        .animation(.easeInOut(duration: 0.2), value: isValid)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(String(localized: "recurring_new_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .onAppear {
            selectedCatId = vm.categories.first?.id
        }
    }

    // MARK: - Helpers

    private var thinDivider: some View {
        VeloceTheme.divider.frame(height: 1).padding(.vertical, 12)
    }

    private func formRow<C: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(VeloceTheme.textSecondary)
            Spacer(minLength: 8)
            content()
        }
    }

    private var categoryScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.visibleCategories) { cat in
                    let selected = selectedCatId == cat.id
                    let col = Color(hex: cat.colorHex)
                    Button(action: { selectedCatId = cat.id }) {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon).font(.system(size: 11))
                            Text(cat.name).font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected ? col.opacity(0.18) : VeloceTheme.surfaceRaised, in: Capsule())
                        .foregroundStyle(selected ? col : VeloceTheme.textSecondary)
                        .overlay(Capsule().strokeBorder(selected ? col.opacity(0.4) : .clear, lineWidth: 1))
                    }
                    .animation(.spring(response: 0.25), value: selected)
                }
            }
        }
    }

    private func save() {
        guard isValid, let catId = selectedCatId, let amt = parsedAmount else { return }
        let item = RecurringExpense(
            title:       title.trimmingCharacters(in: .whitespaces),
            amount:      amt,
            categoryId:  catId,
            frequency:   frequency,
            nextDueDate: startDate,
            note:        note
        )
        vm.addRecurring(item)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    RecurringTransactionsView()
        .environmentObject(ExpenseViewModel())
        .environmentObject(SubscriptionManager.shared)
}
