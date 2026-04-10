import SwiftUI

// MARK: - CategoryColumnView
// Equatable → SwiftUI skips re-render when props haven't changed

struct CategoryColumnView: View, Equatable {
    let category:      Category
    let barRatio:      Double      // 0.0 – 1.0 (clamped)
    let categoryColor: Color
    let statusColor:   Color
    let isHighlighted: Bool

    var onTap:       () -> Void = {}
    var onLongPress: () -> Void = {}
    var onSwipeUp:   () -> Void = {}

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.category      == rhs.category   &&
        lhs.barRatio      == rhs.barRatio    &&
        lhs.isHighlighted == rhs.isHighlighted
    }

    // Layout constants
    private let colWidth:    CGFloat = 62
    private let maxBarH:     CGFloat = 200
    private let trackRadius: CGFloat = 14

    private var barHeight: CGFloat {
        let h = CGFloat(barRatio) * maxBarH
        return barRatio > 0 ? max(h, 6) : 0
    }

    var body: some View {
        VStack(spacing: 10) {
            barColumn
            nameLabel
            amountLabel
        }
        .frame(width: colWidth)
        // Slight lift when highlighted
        .scaleEffect(isHighlighted ? 1.05 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: isHighlighted)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.42) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            onLongPress()
        }
        .gesture(swipeUpGesture)
    }

    // MARK: - Bar

    private var barColumn: some View {
        ZStack(alignment: .bottom) {
            // Track
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(categoryColor.opacity(0.1))
                .frame(width: colWidth, height: maxBarH)

            // Filled bar — smooth spring animation on height
            if barHeight > 0 {
                RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                categoryColor.opacity(0.55),
                                categoryColor
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: colWidth, height: barHeight)
                    // Spring animation — the key performance-safe way to animate height
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.72, blendDuration: 0),
                        value: barHeight
                    )
                    .overlay(alignment: .top) {
                        // Icon cap — only render when bar is tall enough
                        if barHeight >= 44 {
                            Image(systemName: category.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 28, height: 28)
                                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(.top, 7)
                        }
                    }
            }

            // Status dot — replaces the aggressive % badge
            if category.spentRatio >= 0.7 {
                VStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.5), radius: 3)
                    Spacer()
                }
                .frame(height: maxBarH)
                .padding(.top, 8)
            }

            // Highlight ring
            if isHighlighted {
                RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                    .strokeBorder(categoryColor.opacity(0.7), lineWidth: 1.5)
                    .frame(width: colWidth, height: maxBarH)
            }
        }
        .frame(height: maxBarH)
        // drawingGroup() rasterises the subtree — critical for performance
        // when many columns animate simultaneously
        .drawingGroup()
    }

    private var nameLabel: some View {
        Text(category.name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(VeloceTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var amountLabel: some View {
        Text(category.spent.toCompactCurrency())
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(VeloceTheme.textPrimary)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.4), value: category.spent)
    }

    // MARK: - Swipe-up gesture (quick add)

    private var swipeUpGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { val in
                let dy = val.translation.height
                let dx = abs(val.translation.width)
                if dy < -44 && abs(dy) > dx * 1.2 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSwipeUp()
                }
            }
    }
}
