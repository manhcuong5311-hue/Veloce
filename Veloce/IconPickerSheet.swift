import SwiftUI

// MARK: - Icon Picker Sheet
// Bottom sheet showing a categorized grid of SF Symbols.
// The selected icon gets an accent ring + checkmark; tapping any other dismisses.

struct IconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    // MARK: - Icon catalog (SF Symbol names grouped by category)

    private let groups: [(title: String, icons: [String])] = [
        ("Food & Drink", [
            "fork.knife", "cup.and.saucer.fill", "mug.fill", "wineglass.fill",
            "birthday.cake.fill", "popcorn.fill", "leaf.fill", "flame.fill",
            "cart.fill", "basket.fill"
        ]),
        ("Transport", [
            "car.fill", "bus.fill", "tram.fill", "airplane",
            "bicycle", "fuelpump.fill", "figure.walk", "scooter",
            "sailboat.fill", "train.side.front.car"
        ]),
        ("Shopping", [
            "bag.fill", "gift.fill", "tag.fill", "archivebox.fill",
            "handbag.fill", "creditcard.fill", "barcode", "storefront.fill"
        ]),
        ("Bills & Home", [
            "bolt.fill", "wifi", "house.fill", "phone.fill",
            "drop.fill", "building.2.fill", "tv.fill", "antenna.radiowaves.left.and.right"
        ]),
        ("Health & Fitness", [
            "heart.fill", "pills.fill", "cross.circle.fill", "figure.run",
            "stethoscope", "dumbbell.fill", "bandage.fill", "figure.yoga"
        ]),
        ("Entertainment", [
            "gamecontroller.fill", "film.fill", "music.note", "headphones",
            "theatermasks.fill", "book.fill", "paintbrush.fill", "camera.fill"
        ]),
        ("Education", [
            "graduationcap.fill", "pencil", "folder.fill", "backpack.fill",
            "text.book.closed.fill", "globe", "lightbulb.fill", "chart.bar.fill"
        ]),
        ("Travel", [
            "suitcase.fill", "map.fill", "tent.fill", "mountain.2.fill",
            "binoculars.fill", "beach.umbrella.fill", "compass.drawing", "ferry.fill"
        ]),
        ("Finance", [
            "banknote.fill", "dollarsign.circle.fill", "chart.line.uptrend.xyaxis",
            "wallet.pass.fill", "building.columns.fill", "arrow.up.arrow.down.circle.fill",
            "percent", "chart.pie.fill"
        ]),
        ("General", [
            "star.fill", "flag.fill", "bell.fill", "person.fill",
            "pawprint.fill", "sun.max.fill", "moon.fill", "sparkles",
            "clock.fill", "calendar", "location.fill", "shield.fill"
        ]),
    ]

    // Flattened & filtered list used when searching
    private var filteredGroups: [(title: String, icons: [String])] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groups }
        let matched = groups.compactMap { group -> (title: String, icons: [String])? in
            let hits = group.icons.filter { $0.lowercased().contains(q) }
            return hits.isEmpty ? nil : (group.title, hits)
        }
        return matched
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if filteredGroups.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredGroups, id: \.title) { group in
                                iconGroup(group)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search icons…")
            .toolbar {
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
        .preferredColorScheme(.light)
    }

    // MARK: - Icon group section

    private func iconGroup(_ group: (title: String, icons: [String])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(group.title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VeloceTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                spacing: 10
            ) {
                ForEach(group.icons, id: \.self) { symbol in
                    iconCell(symbol: symbol)
                }
            }
        }
    }

    // MARK: - Single icon cell

    private func iconCell(symbol: String) -> some View {
        let isSelected = symbol == selectedIcon
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.70)) {
                selectedIcon = symbol
            }
            // Auto-dismiss after a short moment so the user sees the selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { dismiss() }
        } label: {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? VeloceTheme.accentBg : VeloceTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? VeloceTheme.accent : VeloceTheme.divider,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? VeloceTheme.accent : VeloceTheme.textSecondary)
                    .scaleEffect(isSelected ? 1.08 : 1.0)

                // Checkmark badge
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(VeloceTheme.accent)
                                .background(Circle().fill(.white).padding(1))
                                .offset(x: 4, y: -4)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.70), value: isSelected)
    }

    // MARK: - Empty search state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(VeloceTheme.textTertiary)
            Text("No icons match \"\(searchText)\"")
                .font(.system(size: 14))
                .foregroundStyle(VeloceTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
