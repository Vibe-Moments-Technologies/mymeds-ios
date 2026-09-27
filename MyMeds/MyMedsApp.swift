import SwiftUI
import MyMedsCore

@main
struct MyMedsApp: App {
    @State private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
        }
    }
}
