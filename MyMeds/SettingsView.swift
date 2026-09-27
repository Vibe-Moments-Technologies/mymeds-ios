import SwiftUI
import MyMedsCore
import DesignSystem
import UniformTypeIdentifiers
import UserNotifications

/// Настройки (§12): кнопка-шестерёнка сверху Home.
/// Данные: экспорт бэкапа, импорт medplan/1 (через предпросмотр) и
/// mymeds-backup/1 (полное восстановление с подтверждением).
/// Уведомления: окна на лекарство, бюджет «X из 64», горизонт дней (§8).
struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var shareURL: IdentifiableURL?
    @State private var backupToRestore: PendingBackup?
    @State private var planToImport: PendingPlan?
    @State private var errorText: String?
    @State private var editingMed: Medication?
    @State private var authStatus: UNAuthorizationStatus?

    struct PendingBackup: Identifiable {
        let id = UUID()
        let data: Data
        let preview: AppData
    }

    struct PendingPlan: Identifiable {
        let id = UUID()
        let data: Data
        let file: MedPlanFile
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                List {
                    Section("Данные") {
                        Button {
                            exportBackup()
                        } label: {
                            Label("Экспорт данных (JSON)", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Импорт плана или бэкапа", systemImage: "square.and.arrow.down")
                        }
                        LabeledContent("Лекарств") { Text("\(store.data.medications.count)") }
                        LabeledContent("Планов") { Text("\(store.data.plans.count)") }
                        LabeledContent("Отметок") { Text("\(store.data.intakes.count)") }
                    }
                    Section("Приложение") {
                        LabeledContent("Версия") { Text(AppVersion.versionName) }
                        LabeledContent("Сборка") {
                            Text("\(AppVersion.buildNumber) · \(AppVersion.buildChannel)")
                        }
                        LabeledContent("Коммит") { Text(AppVersion.commitSha) }
                    }
                    Section("Уведомления") {
                        LabeledContent("Запланировано") {
                            Text("\(notificationPlan.total) из \(NotificationPlanner.systemLimit)")
                        }
                        if notificationPlan.trimmed {
                            Label("Бюджет плотный — интервалы укрупнены",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        ForEach(store.data.medications) { med in
                            Button {
                                editingMed = med
                            } label: {
                                HStack {
                                    Text(med.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(medWindowText(med))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Stepper("Горизонт: \(store.data.settings.notifyHorizonDays) дн.",
                                value: horizonBinding, in: 1...7)
                        if let auth = authStatus, auth != .authorized, auth != .provisional {
                            Button("Разрешение не выдано — открыть настройки") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url.value])
            }
            .sheet(item: $planToImport) { pending in
                MedPlanImportSheet(file: pending.file, data: pending.data)
            }
            .sheet(item: $editingMed) { med in
                NotifySettingsSheet(medication: med)
            }
            .task {
                authStatus = await UNUserNotificationCenter.current()
                    .notificationSettings().authorizationStatus
            }
            .confirmationDialog(
                "Восстановить бэкап?",
                isPresented: Binding(get: { backupToRestore != nil },
                                     set: { if !$0 { backupToRestore = nil } }),
                titleVisibility: .visible
            ) {
                Button("Заменить ВСЕ данные", role: .destructive) {
                    restoreBackup()
                }
                Button("Отмена", role: .cancel) { backupToRestore = nil }
            } message: {
                if let pending = backupToRestore {
                    Text("Лекарств: \(pending.preview.medications.count), "
                         + "планов: \(pending.preview.plans.count), "
                         + "отметок: \(pending.preview.intakes.count). "
                         + "Текущие данные будут полностью заменены (не слияние).")
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var notificationPlan: NotificationPlan {
        NotificationPlanner.plan(data: store.data)
    }

    private var horizonBinding: Binding<Int> {
        Binding(get: { store.data.settings.notifyHorizonDays },
                set: { newValue in try? store.setNotifyHorizon(days: newValue) })
    }

    private func medWindowText(_ med: Medication) -> String {
        guard let w = med.notifyWindow else { return "выкл" }
        let slots = notificationPlan.perMedication[med.id] ?? 0
        return String(format: "%02d–%02d · %d мин · %d сл.",
                      w.startHour, w.endHour, w.intervalMinutes, slots)
    }

    private func exportBackup() {
        do {
            let data = try store.exportBackup()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mymeds_backup_\(CivilDate.today()).json")
            try data.write(to: url)
            shareURL = IdentifiableURL(value: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if let backup = try? MedPlanCodec.decodeBackup(data) {
                    backupToRestore = PendingBackup(data: data, preview: backup)
                } else if let file = try? MedPlanCodec.decodeFile(data) {
                    planToImport = PendingPlan(data: data, file: file)
                } else {
                    errorText = "Незнакомый файл: ожидается medplan/1 (план) или mymeds-backup/1 (бэкап)"
                }
            } catch {
                errorText = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let pending = backupToRestore else { return }
        backupToRestore = nil
        do {
            try store.importBackup(pending.data)
            HapticManager.shared.notifySuccess()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct IdentifiableURL: Identifiable {
    let value: URL
    var id: URL { value }
}

/// Share sheet (UIActivityViewController) — системный механизм, без зависимостей.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
