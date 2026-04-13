import Foundation
import UserNotifications
import UIKit
import Combine

// MARK: - Notification Manager

@MainActor
final class NotificationManager: NSObject, ObservableObject {

    static let shared = NotificationManager()

    /// Explicit publisher — required when NSObject subclass + @MainActor prevents synthesis
    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: Published state

    @Published var authStatus: UNAuthorizationStatus = .notDetermined
    @Published var dailyStreak: Int = 0

    // MARK: Preferences (backed by UserDefaults, published via objectWillChange)

    var dailyEnabled: Bool {
        get { ud.bool(forKey: "notif_daily_enabled") }
        set { ud.set(newValue, forKey: "notif_daily_enabled"); objectWillChange.send(); rescheduleDaily() }
    }

    var budgetEnabled: Bool {
        get { ud.bool(forKey: "notif_budget_enabled") }
        set { ud.set(newValue, forKey: "notif_budget_enabled"); objectWillChange.send() }
    }

    var reminderHour: Int {
        get { ud.object(forKey: "notif_reminder_hour")   != nil ? ud.integer(forKey: "notif_reminder_hour")   : 20 }
        set { ud.set(newValue, forKey: "notif_reminder_hour");   objectWillChange.send(); rescheduleDaily() }
    }

    var reminderMinute: Int {
        get { ud.integer(forKey: "notif_reminder_minute") }
        set { ud.set(newValue, forKey: "notif_reminder_minute"); objectWillChange.send(); rescheduleDaily() }
    }

    // MARK: Private state

    private let ud     = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()

    private var lastLogDateStr: String {
        get { ud.string(forKey: "notif_last_log_date") ?? "" }
        set { ud.set(newValue, forKey: "notif_last_log_date") }
    }

    private var ignoreCount: Int {
        get { ud.integer(forKey: "notif_ignore_count") }
        set { ud.set(newValue, forKey: "notif_ignore_count") }
    }

    private var thresholdsJSON: String {
        get { ud.string(forKey: "notif_thresholds") ?? "[]" }
        set { ud.set(newValue, forKey: "notif_thresholds") }
    }

    // MARK: Content

    private let dailyMessages = [
        "Did you log your spending today?",
        "Quick check: any expenses to add?",
        "Stay consistent — log today's spending in 10 seconds.",
        "Don't forget today's expenses 💡",
        "A quick log keeps your budget on track.",
        "You're on a roll — keep your spending log updated 🚀",
    ]

    // MARK: Init

    override init() {
        super.init()
        center.delegate = self
        dailyStreak = ud.integer(forKey: "notif_streak")
        // Seed default preferences once
        if ud.object(forKey: "notif_daily_enabled")  == nil { ud.set(true, forKey: "notif_daily_enabled")  }
        if ud.object(forKey: "notif_budget_enabled") == nil { ud.set(true, forKey: "notif_budget_enabled") }
        // Fetch real permission status first, THEN schedule — avoids the race condition
        // where rescheduleDaily() runs before authStatus is known (status starts as .notDetermined).
        Task {
            await refreshStatus()
            rescheduleDaily()
        }
    }

    // MARK: - Permission

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            if granted { rescheduleDaily() }
            return granted
        } catch {
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Daily Reminder

    func rescheduleDaily() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        guard dailyEnabled, authStatus == .authorized else { return }
        guard !shouldReduceFrequency else { return }

        let body = dailyMessages.randomElement() ?? dailyMessages[0]

        let content        = UNMutableNotificationContent()
        content.title      = "Veloce"
        content.body       = body
        content.sound      = .default
        content.categoryIdentifier = "daily_reminder"

        // ±15 min jitter, clamped 06:00–21:59
        let jitter        = Int.random(in: -15...15)
        var total         = reminderHour * 60 + reminderMinute + jitter
        total             = max(6 * 60, min(total, 22 * 60 - 1))

        var comps         = DateComponents()
        comps.hour        = total / 60
        comps.minute      = total % 60
        comps.second      = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Log tracking + streak

    func recordExpenseLogged() {
        let cal   = Calendar.current
        let now   = cal.startOfDay(for: Date())
        let iso   = ISO8601DateFormatter()
        let today = iso.string(from: now)

        if lastLogDateStr == today { return }   // already counted today

        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let yStr      = iso.string(from: yesterday)

        if lastLogDateStr == yStr {
            dailyStreak += 1
        } else {
            dailyStreak = 1                     // streak broken
        }

        ud.set(dailyStreak, forKey: "notif_streak")
        lastLogDateStr = today

        // Cancel today's reminder — user already logged
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        rescheduleDaily()                       // repeats: true re-fires tomorrow

        // Streak milestone notifications
        let milestones = [3, 5, 7, 14, 21, 30]
        if milestones.contains(dailyStreak) {
            scheduleStreakNote(streak: dailyStreak)
        }
    }

    private func scheduleStreakNote(streak: Int) {
        guard authStatus == .authorized else { return }
        let content   = UNMutableNotificationContent()
        content.title = "Veloce 🔥"
        content.body  = "You've logged expenses \(streak) days in a row. Keep it up!"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "streak_\(streak)_\(Date().timeIntervalSince1970)",
            content: content, trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Budget threshold notifications

    func checkBudgetThreshold(for category: Category) {
        guard budgetEnabled, authStatus == .authorized else { return }
        guard category.budget > 0 else { return }
        guard !dailyCapReached() else { return }   // max 2 budget notes/day

        let ratio = category.spent / category.budget
        let mKey  = monthKey()

        if      ratio >= 1.00 { fire(.exceeded, category: category, monthKey: mKey) }
        else if ratio >= 0.80 { fire(.warning,  category: category, monthKey: mKey) }
        else if ratio >= 0.50 { fire(.half,     category: category, monthKey: mKey) }
    }

    private enum Threshold: String { case half = "50", warning = "80", exceeded = "100" }

    private func fire(_ t: Threshold, category: Category, monthKey: String) {
        let key   = "\(category.id.uuidString)_\(monthKey)_\(t.rawValue)"
        var fired = firedSet()
        guard !fired.contains(key) else { return }
        fired.insert(key)
        saveFiredSet(fired)
        incrementDailyCap()

        let content   = UNMutableNotificationContent()
        content.sound = .default
        switch t {
        case .half:
            content.title = "Halfway there"
            content.body  = "You're halfway through your \(category.name) budget this month."
        case .warning:
            content.title = "Budget alert"
            content.body  = "Careful — you're close to your \(category.name) limit."
        case .exceeded:
            content.title = "Budget exceeded"
            content.body  = "You've exceeded your \(category.name) budget."
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "budget_\(key)", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Daily cap (max 2 budget notes/day)

    private func dailyCapReached() -> Bool {
        let key = "notif_cap_\(todayStr())"
        return ud.integer(forKey: key) >= 2
    }

    private func incrementDailyCap() {
        let key = "notif_cap_\(todayStr())"
        ud.set(ud.integer(forKey: key) + 1, forKey: key)
    }

    // MARK: - Test Notification

    /// Fires a visible notification in ~2 seconds. Use in Settings to verify the pipeline works.
    func sendTestNotification() {
        guard authStatus == .authorized else { return }
        let content       = UNMutableNotificationContent()
        content.title     = "Veloce"
        content.body      = "Notifications are working correctly. You're all set!"
        content.sound     = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "veloce_test_\(Int(Date().timeIntervalSince1970))",
            content: content, trigger: trigger
        )
        center.add(request) { error in
            if let error { print("[NotificationManager] Test notification error: \(error)") }
        }
    }

    /// Returns how many notifications are currently pending (useful for debugging).
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    // MARK: - Adaptive

    /// If user has dismissed ≥5 notifications without opening app, back off
    var shouldReduceFrequency: Bool { ignoreCount >= 5 }

    func noteIgnored() { ignoreCount += 1 }

    // MARK: - Helpers

    private func monthKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: Date())
    }

    private func todayStr() -> String {
        ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
    }

    private func firedSet() -> Set<String> {
        guard let data = thresholdsJSON.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    private func saveFiredSet(_ set: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(set)),
           let str  = String(data: data, encoding: .utf8) {
            thresholdsJSON = str
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Allow notifications to show as banners while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Subtle haptic when user opens app from a notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        completionHandler()
    }
}
