import SwiftUI
#if os(iOS)
import FinanceKit
import FinanceKitUI

// MARK: - ApplePayImportSheet
//
// Flow:
//  1. On appear → check FinanceKit availability → auto-open TransactionPicker
//  2. User selects transactions in Apple's native picker
//  3. On picker dismiss with selection → map to PendingImport list
//  4. User reviews, toggles items (duplicates shown with badge)
//  5. "Import N" → vm.addExpense() for each selected, dismiss

@available(iOS 18, *)
struct ApplePayImportSheet: View {

    @EnvironmentObject private var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: State

    private enum Phase {
        case checking
        case unavailable
        case picking
        case confirming([PendingImport])
        case empty
    }

    @State private var phase: Phase = .checking

    // Picker bindings
    @State private var showPicker          = false
    @State private var pickedTransactions: [FinanceKit.Transaction] = []

    // Confirmation selection
    @State private var selectedIDs: Set<UUID> = []

    private let service = FinanceKitService.shared

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .checking:
                    loadingView

                case .unavailable:
                    unavailableView

                case .picking:
                    // Transparent loading shown while the system picker is presenting
                    loadingView

                case .confirming(let imports):
                    confirmationList(imports)

                case .empty:
                    emptyView
                }
            }
            .navigationTitle(String(localized: "apple_pay_import_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .background(VeloceTheme.bg.ignoresSafeArea())
        }
        // Native transaction picker (FinanceKitUI, iOS 18+)
        .transactionPicker(isPresented: $showPicker, selection: $pickedTransactions)
        .onChange(of: pickedTransactions) { _, transactions in
            guard !transactions.isEmpty else { return }
            let imports = service.mapToPendingImports(
                transactions,
                categories: vm.categories,
                existingExpenses: vm.expenses
            )
            if imports.isEmpty {
                phase = .empty
            } else {
                selectedIDs = Set(imports.map(\.id))
                phase = .confirming(imports)
            }
        }
        .onChange(of: showPicker) { _, isShowing in
            // Picker dismissed without selecting anything → close sheet
            if !isShowing, pickedTransactions.isEmpty {
                if case .picking = phase { dismiss() }
            }
        }
        .task {
            await startFlow()
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(VeloceTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(VeloceTheme.textSecondary)

            Text(String(localized: "apple_pay_not_available"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)

            Text(String(localized: "apple_pay_not_available_desc"))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(VeloceTheme.textSecondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(VeloceTheme.textSecondary)

            Text(String(localized: "apple_pay_no_expenses"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)

            Text(String(localized: "apple_pay_no_expenses_desc"))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(VeloceTheme.textSecondary)
                .padding(.horizontal, 32)

            Button(String(localized: "apple_pay_try_again")) {
                pickedTransactions = []
                phase = .picking
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    showPicker = true
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(VeloceTheme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func confirmationList(_ imports: [PendingImport]) -> some View {
        List {
            // Select / deselect all
            Section {
                let allSelected = selectedIDs.count == imports.count
                Button(allSelected
                       ? String(localized: "apple_pay_deselect_all")
                       : String(localized: "apple_pay_select_all")
                ) {
                    if allSelected {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(imports.map(\.id))
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VeloceTheme.accent)
                .listRowBackground(VeloceTheme.surfaceRaised)
            }

            // Transaction rows
            Section {
                ForEach(imports) { item in
                    importRow(item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(VeloceTheme.bg)
    }

    @ViewBuilder
    private func importRow(_ item: PendingImport) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        let cat = vm.categories.first(where: { $0.id == item.expense.categoryId })

        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? VeloceTheme.accent : VeloceTheme.textSecondary)
                .animation(.easeInOut(duration: 0.15), value: isSelected)

            // Category badge
            if let cat {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: cat.colorHex).opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: cat.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: cat.colorHex))
                }
            }

            // Title + badges
            VStack(alignment: .leading, spacing: 3) {
                Text(item.expense.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let cat {
                        Text(cat.name)
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textSecondary)
                    }
                    if item.isDuplicate {
                        Text(String(localized: "apple_pay_already_imported"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                    }
                    if item.wasCurrencyConverted {
                        Text(String(format: String(localized: "apple_pay_converted_fmt"), item.originalCurrencyCode))
                            .font(.system(size: 10))
                            .foregroundStyle(VeloceTheme.textSecondary)
                    }
                }
            }

            Spacer()

            // Amount + date
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.expense.amount.toCompactCurrency())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text(item.expense.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(VeloceTheme.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(item.id) }
        .listRowBackground(VeloceTheme.surfaceRaised)
        .listRowSeparatorTint(VeloceTheme.divider)
        .opacity(isSelected ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "cancel")) { dismiss() }
                .foregroundStyle(VeloceTheme.textSecondary)
        }

        if case .confirming(let imports) = phase, !imports.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(format: String(localized: "apple_pay_import_btn_fmt"), selectedIDs.count)) {
                    importSelected(from: imports)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedIDs.isEmpty ? VeloceTheme.textSecondary : VeloceTheme.accent)
                .disabled(selectedIDs.isEmpty)
            }
        }
    }

    // MARK: - Logic

    private func startFlow() async {
        guard service.isAvailable else {
            phase = .unavailable
            return
        }
        phase = .picking
        // Small delay so the sheet finishes animating before the picker presents
        try? await Task.sleep(for: .milliseconds(350))
        showPicker = true
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    private func importSelected(from imports: [PendingImport]) {
        for item in imports where selectedIDs.contains(item.id) {
            vm.addExpense(item.expense)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
#endif
