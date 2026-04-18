import Foundation
import StoreKit
import UIKit
import Combine

// MARK: - Rating Manager

/// Manages the in-app review prompt lifecycle.
/// Follows Apple's best practices: max 3 prompts/year, only after positive actions.

@MainActor
final class RatingManager: ObservableObject {

    static let shared = RatingManager()

    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: Published

    @Published var showSoftPrompt = false

    // MARK: Persistence

    private let ud = UserDefaults.standard

    private var promptCount: Int {
        get { ud.integer(forKey: "rating_prompt_count") }
        set { ud.set(newValue, forKey: "rating_prompt_count") }
    }

    private var lastPromptDateStr: String {
        get { ud.string(forKey: "rating_last_prompt_date") ?? "" }
        set { ud.set(newValue, forKey: "rating_last_prompt_date") }
    }

    private var firstTransactionDateStr: String {
        get { ud.string(forKey: "rating_first_txn_date") ?? "" }
        set { ud.set(newValue, forKey: "rating_first_txn_date") }
    }

    private var activeDaysJSON: String {
        get { ud.string(forKey: "rating_active_days") ?? "[]" }
        set { ud.set(newValue, forKey: "rating_active_days") }
    }

    // MARK: Constants

    private let maxPromptsPerYear = 3
    private let iso = ISO8601DateFormatter()

    // MARK: Init

    private init() {}

    // MARK: - Usage tracking

    func recordActiveDay() {
        let today = iso.string(from: Calendar.current.startOfDay(for: Date()))
        var days  = loadActiveDays()
        guard !days.contains(today) else { return }
        days.append(today)
        saveActiveDays(days)
    }

    func recordFirstTransaction() {
        guard firstTransactionDateStr.isEmpty else { return }
        firstTransactionDateStr = iso.string(from: Date())
    }

    // MARK: - Trigger evaluation

    /// Call this after a positive user action (e.g., saving an expense).
    func evaluateAfterPositiveAction() {
        guard !showSoftPrompt else { return }
        guard shouldPrompt()  else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                self?.showSoftPrompt = true
            }
        }
    }

    // MARK: - User responses

    func userTappedRate() {
        showSoftPrompt    = false
        promptCount      += 1
        lastPromptDateStr = iso.string(from: Date())
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Request native review dialog
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            Task { await AppStore.requestReview(in: scene) }
        }
    }

    func userTappedLater() {
        withAnimation(.easeInOut(duration: 0.2)) { showSoftPrompt = false }
        promptCount      += 1
        lastPromptDateStr = iso.string(from: Date())
    }

    // MARK: - Logic

    private func shouldPrompt() -> Bool {
        // Hard cap: 3 per year
        let yearPromptCount = promptCount  // simplified: track total, Apple enforces per-year internally
        guard yearPromptCount < maxPromptsPerYear else { return false }

        // Min 14 days since last prompt
        if !lastPromptDateStr.isEmpty,
           let last = iso.date(from: lastPromptDateStr) {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= 14 else { return false }
        }

        let activeDays   = loadActiveDays().count
        let hasFirstTxn  = !firstTransactionDateStr.isEmpty

        // First prompt: ≥3 active days AND has logged at least one transaction
        if promptCount == 0 {
            return hasFirstTxn && activeDays >= 3
        }

        // Second prompt: ≥10 active days
        if promptCount == 1 {
            return activeDays >= 10
        }

        // Third prompt: ≥30 active days
        return activeDays >= 30
    }

    // MARK: - Active days persistence

    private func loadActiveDays() -> [String] {
        guard let data = activeDaysJSON.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    private func saveActiveDays(_ days: [String]) {
        if let data = try? JSONEncoder().encode(days),
           let str  = String(data: data, encoding: .utf8) {
            activeDaysJSON = str
        }
    }
}

// MARK: - Soft Prompt Overlay View

import SwiftUI

struct RatingSoftPromptView: View {
    @ObservedObject var ratingManager = RatingManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            if ratingManager.showSoftPrompt {
                // Scrim
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { ratingManager.userTappedLater() }
                    .transition(.opacity)

                // Card
                promptCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: ratingManager.showSoftPrompt)
    }

    private var promptCard: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(VeloceTheme.divider)
                .frame(width: 36, height: 4)
                .padding(.top, 4)

            // Stars
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color(hex: "F9C74F"))
                        .scaleEffect(ratingManager.showSoftPrompt ? 1 : 0.4)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.65)
                                .delay(Double(i) * 0.06),
                            value: ratingManager.showSoftPrompt
                        )
                }
            }

            // Copy
            VStack(spacing: 6) {
                Text("rating_prompt_title")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text("rating_prompt_subtitle")
                    .font(.system(size: 14))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Buttons
            VStack(spacing: 10) {
                Button(action: { ratingManager.userTappedRate() }) {
                    Text("rating_rate_now")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(VeloceTheme.accent)
                        )
                }

                Button(action: { ratingManager.userTappedLater() }) {
                    Text("rating_maybe_later")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(VeloceTheme.bg)
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: -4)
        )
    }
}
