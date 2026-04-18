import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Context passed to the Cloud Function

struct AppContext: Encodable {
    let monthlyIncome:  Double
    let savingGoal:     Double
    let totalSpent:     Double
    let totalBudget:    Double
    let categories:     [CategoryContext]
    /// Last 60 transactions newest-first. Gives the LLM real data to reason
    /// about instead of only monthly aggregates — unlocks answers like
    /// "what did I spend on food this week?" or "my biggest single expense".
    let recentExpenses: [RecentExpense]
}

struct CategoryContext: Encodable {
    let name:       String
    let spent:      Double
    let budget:     Double
    let spentRatio: Double
}

struct RecentExpense: Encodable {
    let title:        String
    let amount:       Double
    let categoryName: String
    let date:         String   // ISO 8601, e.g. "2026-04-16T09:30:00Z"
}

// MARK: - Message model

struct OpenAIMessage: Codable {
    let role:    String   // "user" | "assistant"
    let content: String
}

// MARK: - Structured action the AI can suggest

/// Mirrors the `AIAction` object emitted by the `suggest_action` tool in
/// the Cloud Function. The iOS client renders these as tappable buttons
/// inside the assistant's chat bubble.
struct AIAction: Codable, Equatable, Hashable {
    let type:            String    // "adjust_budget" | "open_category"
    let categoryName:    String?
    let suggestedAmount: Double?
    let reason:          String?
}

// MARK: - Response from chatWithAI

struct AIResponse {
    let content: String
    let actions: [AIAction]   // may be empty when the model suggests no action
}

// MARK: - Firebase-backed Chat Service

enum OpenAIService {

    // MARK: Chat

    static func chat(
        messages: [OpenAIMessage],
        context:  AppContext
    ) async throws -> AIResponse {
        // Force-refresh ID token so Firebase Functions always receives a valid auth header
        if let user = Auth.auth().currentUser {
            _ = try? await user.getIDToken(forcingRefresh: true)
        }

        let callable = Functions.functions().httpsCallable("chatWithAI")

        let payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "context":  (try? context.asDictionary()) ?? [:]
        ]

        let result = try await callable.call(payload)

        guard let data    = result.data as? [String: Any],
              let content = data["content"] as? String else {
            throw OpenAIError.emptyResponse
        }

        // Decode the optional actions array returned by the suggest_action tool.
        var actions: [AIAction] = []
        if let rawActions = data["actions"] as? [[String: Any]] {
            actions = rawActions.compactMap { dict in
                guard let type = dict["type"] as? String else { return nil }
                return AIAction(
                    type:            type,
                    categoryName:    dict["categoryName"]    as? String,
                    suggestedAmount: dict["suggestedAmount"] as? Double,
                    reason:          dict["reason"]          as? String
                )
            }
        }

        return AIResponse(content: content, actions: actions)
    }

    // MARK: Parse expense

    /// Sends `text` to the `parseExpense` Cloud Function and maps the result
    /// back to a `ParsedExpense` that the rest of the app already understands.
    ///
    /// Throws on network error or when the model can't extract an amount.
    /// The caller should fall back to `AIService.parseExpense()` on any throw.
    static func parseExpense(
        text:          String,
        categoryNames: [String],
        categories:    [Category]
    ) async throws -> ParsedExpense {
        if let user = Auth.auth().currentUser {
            _ = try? await user.getIDToken(forcingRefresh: false)
        }

        let callable = Functions.functions().httpsCallable("parseExpense")
        let payload: [String: Any] = [
            "text":          text,
            "categoryNames": categoryNames
        ]

        let result = try await callable.call(payload)

        guard let data   = result.data as? [String: Any],
              let title  = data["title"]  as? String,
              let amount = data["amount"] as? Double,
              amount > 0
        else {
            throw OpenAIError.emptyResponse
        }

        let confidence   = data["confidence"] as? Double ?? 0.5
        // Server sends category name in the "categoryId" field.
        // Only trust the match when confidence is ≥ 0.5.
        let rawCatName   = data["categoryId"] as? String
        let resolvedName: String? = (confidence >= 0.5) ? rawCatName : nil

        return ParsedExpense(
            title:        title,
            amount:       amount,
            categoryName: resolvedName,
            date:         Date()
        )
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case emptyResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:     return String(localized: "openai_error_empty_response")
        case .apiError(let msg): return msg
        }
    }
}

// MARK: - Encodable helper

private extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
