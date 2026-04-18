import SwiftUI

// MARK: - BudgetEditColumnView
// Interactive column used in Edit Budget mode.
// Key design constraint: nothing must overflow the card's clipShape.
//   – scaleEffect on the whole VStack is banned (clips labels & bubble)
//   – the live bubble lives INSIDE the bar ZStack, offset above the bar top
//   – active feedback uses glow + border instead of scale

struct BudgetEditColumnView: View {

    // MARK: - Inputs
    let category:        Category
    let totalBudget:     Double      // frozen total – the fixed pie
    let categoryColor:   Color
    let isActive:        Bool        // this bar is being dragged
    let isAnyActive:     Bool        // any bar in the row is active
    let onBudgetChange:  (Double) -> Void
    let onDragStart:     () -> Void
    let onDragEnd:       () -> Void

    // MARK: - Layout constants
    private let colWidth:      CGFloat = 62
    private let maxBarH:       CGFloat = 260    // taller than normal (200) so section expands
    private let trackRadius:   CGFloat = 14
    // Snap increment: derived from the active currency so the gesture stays
    // usable after a currency switch (100_000 VND ≠ 100_000 USD).
    private var snapStep: Double { AppCurrency.current.budgetSnapStep }
    private let dragSensitivity: Double = 0.65  // < 1.0 → finger must travel further per snap
                                                 //   makes precise targeting easier

    // MARK: - Drag state
    @State private var isDragging:        Bool   = false
    @State private var baseBudget:        Double = 0
    @State private var dragDelta:         Double = 0
    @State private var lastSnappedBudget: Double = 0

    // MARK: - Derived display values (purely local – never relies on VM for live feedback)
    private var displayBudget: Double {
        guard isDragging else { return category.budget }
        return max(0, min(baseBudget + dragDelta, totalBudget))
    }

    private var displayBarH: CGFloat {
        guard totalBudget > 0 else { return 8 }
        return max(8, CGFloat(displayBudget / totalBudget) * maxBarH)
    }

    // Bubble sits just above the bar top, clamped so it never exits the ZStack frame
    private var bubbleOffsetY: CGFloat {
        let gap: CGFloat = 6
        // offset is from the bottom of the ZStack (alignment: .bottom)
        let raw = displayBarH + gap
        // clamp so the bubble (≈20 pt tall) stays inside the maxBarH frame
        return min(raw, maxBarH - 22)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            barStack          // bubble lives inside the ZStack – no overflow
            nameLabel
            budgetLabel
        }
        .frame(width: colWidth)
        // ⚠️  NO scaleEffect on the VStack – it would overflow clipShape and cut off labels/bubble.
        //     Active feedback is done with glow + border ring on the bar instead.
        .opacity(isAnyActive && !isActive ? 0.40 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.70), value: isAnyActive)
    }

    // MARK: - Bar ZStack

    private var barStack: some View {
        ZStack(alignment: .bottom) {

            // ── Soft glow halo (stays inside frame – just a blurred shape)
            if isActive {
                RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                    .fill(categoryColor.opacity(0.22))
                    .frame(width: colWidth, height: maxBarH)
                    .blur(radius: 10)
            }

            // ── Track background
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(categoryColor.opacity(0.10))
                .frame(width: colWidth, height: maxBarH)

            // ── Budget bar (height tracks finger in real-time)
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [categoryColor.opacity(0.50), categoryColor],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: colWidth, height: displayBarH)
                .animation(
                    isDragging
                        ? .interactiveSpring(response: 0.12, dampingFraction: 1.0)
                        : .spring(response: 0.46, dampingFraction: 0.78),
                    value: displayBarH
                )
                // Drag handle at the crown
                .overlay(alignment: .top) { dragHandle.padding(.top, 8) }
                // Category icon (only when bar is tall enough)
                .overlay(alignment: .top) {
                    if displayBarH >= 58 {
                        Image(systemName: category.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.22),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 32)
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }

            // ── Live value bubble – positioned INSIDE the ZStack so it never clips
            if isDragging {
                Text(displayBudget.toCompactCurrency())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor, in: Capsule())
                    .shadow(color: categoryColor.opacity(0.35), radius: 4, y: 2)
                    // Offset upward from ZStack bottom to sit just above the bar top
                    .offset(y: -bubbleOffsetY)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .animation(.spring(response: 0.20), value: bubbleOffsetY)
            }

            // ── Active highlight ring (no overflow – same frame as track)
            if isActive {
                RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                    .strokeBorder(categoryColor.opacity(0.60), lineWidth: 1.5)
                    .frame(width: colWidth, height: maxBarH)
            }
        }
        .frame(width: colWidth, height: maxBarH)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    // MARK: - Drag handle (3-pill grip)

    private var dragHandle: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(.white.opacity(isActive ? 0.88 : 0.50))
                    .frame(width: 3, height: 12)
            }
        }
        .animation(.spring(response: 0.22), value: isActive)
    }

    // MARK: - Labels

    @AppStorage("veloce_speech_language") private var speechLang: String = "en-US"

    private var nameLabel: some View {
        Text(CategoryLocalization.name(for: category.name, langCode: speechLang))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(VeloceTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var budgetLabel: some View {
        Text(displayBudget.toCompactCurrency())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isActive ? categoryColor : VeloceTheme.textPrimary)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.20), value: displayBudget)
    }

    // MARK: - Drag gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    baseBudget        = category.budget
                    lastSnappedBudget = category.budget
                    isDragging        = true
                    onDragStart()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                // Drag up (−Y) increases budget.
                // dragSensitivity < 1 means finger travels further per snap → easier precision.
                let budgetPerPoint = totalBudget / Double(maxBarH) * dragSensitivity
                dragDelta = -Double(value.translation.height) * budgetPerPoint

                // Snap then clamp
                let raw     = baseBudget + dragDelta
                let snapped = round(raw / snapStep) * snapStep
                let clamped = max(0, min(snapped, totalBudget))

                // Haptic tick on each boundary crossing
                if clamped != lastSnappedBudget {
                    UISelectionFeedbackGenerator().selectionChanged()
                    lastSnappedBudget = clamped
                }

                onBudgetChange(clamped)
            }
            .onEnded { _ in
                // Commit final value
                let raw     = baseBudget + dragDelta
                let snapped = round(raw / snapStep) * snapStep
                let clamped = max(0, min(snapped, totalBudget))
                onBudgetChange(clamped)

                dragDelta  = 0
                isDragging = false
                onDragEnd()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }
}
