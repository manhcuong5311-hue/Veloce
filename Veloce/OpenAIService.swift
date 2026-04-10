import Foundation
import FirebaseFunctions

// MARK: - Context passed to the Cloud Function

struct AppContext: Encodable {
    let monthlyIncome: Double
    let savingGoal:    Double
    let totalSpent:    Double
    let totalBudget:   Double
    let categories:    [CategoryContext]
}

struct CategoryContext: Encodable {
    let name:       String
    let spent:      Double
    let budget:     Double
    let spentRatio: Double
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
