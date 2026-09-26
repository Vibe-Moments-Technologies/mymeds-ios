import SwiftUI
import MyMedsCore

// Заглушка этапа 1: доказывает, что Core подключён, а хранилище открывается.
// Home — этап 2 (MED_APP_SPEC.md §14).
struct ContentView: View {
    private let storage = StorageService()
    @State private var data: AppData?

    var body: some View {
        VStack(spacing: 12) {
            Text("Мои Лекарства")
                .font(.title2.bold())
            Text("v\(AppVersion.versionName) · \(AppVersion.buildChannel) · build \(AppVersion.buildNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let data {
                Text("Лекарств: \(data.medications.count) · Планов: \(data.plans.count)")
                    .font(.subheadline)
            } else {
                Text("Данных пока нет — этап 2 принесёт Home и отметки")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { data = storage.load() }
    }
}
