import SwiftUI
import MyMedsCore

@main
struct MyMedsApp: App {
    @State private var store = AppEnvironment.store
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationSetup.register()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .task {
                    NotificationSetup.requestAuthorization()
                    NotificationSetup.reschedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Перевзвод скользящего окна при выходе на foreground (§8);
            // reload — данные могла изменить отметка из уведомления в фоне.
            if phase == .active {
                store.reload()
                NotificationSetup.reschedule()
            }
        }
    }
}
