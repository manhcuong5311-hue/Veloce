import SwiftUI

// MARK: - Add Expense

struct AddExpenseSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    var preselectedCategoryId: UUID? = nil

    @State private var title              = ""
    @State private var amountText         = ""
    @State private var note               = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var date               = Date()
    @FocusState private var amountFocused: Bool

    private var parsedAmount: Double? {
        Double(amountText.filter { $0.isNumber })
    }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && (parsedAmount ?? 0) > 0
        && selectedCategoryId != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        amountHero
                        detailsCard
                        saveButton
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .onAppear {
            selectedCategoryId = preselectedCategoryId ?? vm.categories.first?.id
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                amountFocused = true
            }
        }
    }

    // MARK: - Amount hero

    private var amountHero: some View {
        VStack(spacing: 6) {
            Text("Amount")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
                .tracking(0.3)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if AppCurrency.current.symbolLeading {
                    Text(AppCurrency.current.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .offset(y: -4)
                }

                TextField("0", text: $amountText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                    .frame(maxWidth: 220)
                    .onChange(of: amountText) { _, newVal in
                        let digits    = newVal.filter { $0.isNumber }
                        let formatted = Double.formatAmountInput(digits)
                        if formatted != amountText { amountText = formatted }
                    }

                if !AppCurrency.current.symbolLeading {
                    Text(AppCurrency.current.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .offset(y: -4)
                }
            }

            if let amt = parsedAmount, amt > 0 {
                Text(amt.toCurrencyString())
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .veloceCard(radius: 22)
        .animation(.spring(response: 0.3), value: parsedAmount != nil)
    }

    // MARK: - Details card

    private var detailsCard: some View {
        VStack(spacing: 0) {
            formRow("Title") {
                TextField("What did you spend on?", text: $title)
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            thinDivider

            formRow("Note") {
                TextField("Optional note…", text: $note)
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            thinDivider

            formRow("Category") { categoryScroll }

            thinDivider

            formRow("Date") {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(VeloceTheme.accent)
            }
        }
        .veloceCard()
    }

    private var thinDivider: some View {
        VeloceTheme.divider
            .frame(height: 1)
            .padding(.vertical, 12)
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
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
                ForEach(vm.categories) { cat in
                    let selected = selectedCategoryId == cat.id
                    let col = Color(hex: cat.colorHex)
                    Button(action: { selectedCategoryId = cat.id }) {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11))
                            Text(cat.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? col.opacity(0.18) : VeloceTheme.surfaceRaised,
                                    in: Capsule())
                        .foregroundStyle(selected ? col : VeloceTheme.textSecondary)
                        .overlay(Capsule().strokeBorder(selected ? col.opacity(0.4) : Color.clear, lineWidth: 1))
                    }
                    .animation(.spring(response: 0.25), value: selected)
                }
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button(action: save) {
            Text("Add Expense")
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

    private func save() {
        guard isValid, let catId = selectedCategoryId, let amt = parsedAmount else { return }
        vm.addExpense(Expense(
            title:      title.trimmingCharacters(in: .whitespaces),
            amount:     amt,
            categoryId: catId,
            date:       date,
            note:       note.trimmingCharacters(in: .whitespaces)
        ))
        dismiss()
    }
}

// MARK: - Edit Expense

struct EditExpenseSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    let expense: Expense

    @State private var title:              String
    @State private var amountText:         String
    @State private var note:               String
    @State private var selectedCategoryId: UUID
    @State private var date:               Date
    @FocusState private var amountFocused: Bool

    init(expense: Expense) {
        self.expense = expense
        _title              = State(initialValue: expense.title)
        _amountText         = State(initialValue: Double.formatAmountInput("\(Int(expense.amount))"))
        _note               = State(initialValue: expense.note)
        _selectedCategoryId = State(initialValue: expense.categoryId)
        _date               = State(initialValue: expense.date)
    }

    private var parsedAmount: Double? { Double(amountText.filter { $0.isNumber }) }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        amountHero
                        detailsCard
                        saveButton
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                amountFocused = true
            }
        }
    }

    // MARK: - Amount hero

    private var amountHero: some View {
        VStack(spacing: 6) {
            Text("Amount")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
                .tracking(0.3)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if AppCurrency.current.symbolLeading {
                    Text(AppCurrency.current.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .offset(y: -4)
                }

                TextField("0", text: $amountText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                    .frame(maxWidth: 220)
                    .onChange(of: amountText) { _, newVal in
                        let digits    = newVal.filter { $0.isNumber }
                        let formatted = Double.formatAmountInput(digits)
                        if formatted != amountText { amountText = formatted }
                    }

                if !AppCurrency.current.symbolLeading {
                    Text(AppCurrency.current.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .offset(y: -4)
                }
            }

            if let amt = parsedAmount, amt > 0 {
                Text(amt.toCurrencyString())
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .veloceCard(radius: 22)
        .animation(.spring(response: 0.3), value: parsedAmount != nil)
    }

    // MARK: - Details card

    private var detailsCard: some View {
        VStack(spacing: 0) {
            formRow("Title") {
                TextField("What did you spend on?", text: $title)
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            thinDivider

            formRow("Note") {
                TextField("Optional note…", text: $note)
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            thinDivider

            formRow("Category") { categoryScroll }

            thinDivider

            formRow("Date") {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(VeloceTheme.accent)
            }
        }
        .veloceCard()
    }

    private var thinDivider: some View {
        VeloceTheme.divider
            .frame(height: 1)
            .padding(.vertical, 12)
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
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
                ForEach(vm.categories) { cat in
                    let selected = selectedCategoryId == cat.id
                    let col = Color(hex: cat.colorHex)
                    Button(action: { selectedCategoryId = cat.id }) {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11))
                            Text(cat.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? col.opacity(0.18) : VeloceTheme.surfaceRaised,
                                    in: Capsule())
                        .foregroundStyle(selected ? col : VeloceTheme.textSecondary)
                        .overlay(Capsule().strokeBorder(selected ? col.opacity(0.4) : Color.clear, lineWidth: 1))
                    }
                    .animation(.spring(response: 0.25), value: selected)
                }
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button(action: save) {
            Text("Save Changes")
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

    private func save() {
        guard isValid, let amt = parsedAmount else { return }
        var updated = expense
        updated.title      = title.trimmingCharacters(in: .whitespaces)
        updated.amount     = amt
        updated.note       = note.trimmingCharacters(in: .whitespaces)
        updated.categoryId = selectedCategoryId
        updated.date       = date
        vm.updateExpense(updated, replacing: expense)
        dismiss()
    }
}
