import Foundation
import UserNotifications
import MyMedsCore

/// Единственный экземпляр DataStore на процесс (§8: единственный писатель):
/// UI и делегат уведомлений используют один инстанс — нет расхождения
/// памяти и диска внутри процесса.
enum AppEnvironment {
    static let store = DataStore()
}

/// Категории, планировщик и делегат локальных уведомлений (§8).
///
/// // ponytail: отметка из уведомления идёт через didReceive (система будит
/// // процесс приложения в фоне) — на iOS нет AppIntent-backed действий для
/// // обычных локальных уведомлений; App Intents понадобятся на этапе 6 для
/// // кнопок Live Activity (Button(intent:)) — тогда добавим отдельным файлом.
enum NotificationSetup {
    static let categoryID = "INTAKE"
    static let tookAction = "TOOK"
    static let skippedAction = "SKIPPED"

    static func register() {
        let center = UNUserNotificationCenter.current()
        let took = UNNotificationAction(identifier: tookAction, title: "Принял", options: [])
        let skipped = UNNotificationAction(identifier: skippedAction, title: "Пропустил", options: [])
        let category = UNNotificationCategory(
            identifier: categoryID, actions: [took, skipped], intentIdentifiers: [])
        center.setNotificationCategories([category])
        center.delegate = IntakeNotificationDelegate.shared
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Скользящее окно (§8): отменить все pending → пересчитать из entries →
    /// поставить. Идемпотентно, без состояния «что уже запланировано».
    /// Вызывается при: запуске, foreground, отметке приёма, правках данных.
    static func reschedule() {
        let plan = NotificationPlanner.plan(data: AppEnvironment.store.data)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for item in plan.items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.userInfo = [
                "planId": item.planId.uuidString,
                "day": item.day,
            ]
            var comps = DateComponents()
            comps.year = item.date.year
            comps.month = item.date.month
            comps.day = item.date.day
            comps.hour = item.hour
            comps.minute = item.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}

/// Обработчик кнопок уведомления: пишет через тот же StorageService
/// (App Group + NSFileCoordinator + атомарная замена — протокол §8).
final class IntakeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IntakeNotificationDelegate()

    // Баннер даже когда приложение в foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let planIdString = userInfo["planId"] as? String,
              let planId = UUID(uuidString: planIdString),
              let day = userInfo["day"] as? Int else { return }

        let status: Intake.Status
        switch response.actionIdentifier {
        case NotificationSetup.tookAction: status = .taken
        case NotificationSetup.skippedAction: status = .skipped
        default: return   // открытие приложения — не отметка
        }
        do {
            try AppEnvironment.store.mark(planId: planId, day: day, status: status)
            NotificationSetup.reschedule()
        } catch {
            // В фоне UI не показать; при следующем открытии данные перечитаются.
        }
    }
}
