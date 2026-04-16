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
    let role:    String   // "system" | "user" | "assistant"
    let content: String
}

// MARK: - Firebase-backed Chat Service

enum OpenAIService {

    static func chat(
        messages: [OpenAIMessage],
        context:  AppContext
    ) async throws -> String {
        // Force-refresh ID token so Firebase Functions always receives a valid auth header
        if let user = Auth.auth().currentUser {
            _ = try? await user.getIDToken(forcingRefresh: true)
        }

        let fn       = Functions.functions()
        let callable = fn.httpsCallable("chatWithAI")

        let payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "context":  (try? context.asDictionary()) ?? [:]
        ]

        let result = try await callable.call(payload)

        guard let data    = result.data as? [String: Any],
              let content = data["content"] as? String else {
            throw OpenAIError.emptyResponse
        }
        return content
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case emptyResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:     return "AI returned an empty response. Please try again."
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
