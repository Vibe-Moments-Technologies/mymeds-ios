import SwiftUI
import MyMedsCore
import DesignSystem

/// Окно напоминаний на лекарство (§8: гибкость per-med).
/// nil = уведомления лекарства выключены.
struct NotifySettingsSheet: View {
    let medication: Medication

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = true
    @State private var startHour = 20
    @State private var endHour = 23
    @State private var intervalIndex = 1
    @State private var errorText: String?

    private let intervals = [15, 30, 60, 120]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Form {
                    Section {
                        Toggle("Напоминания", isOn: $enabled)
                    }
                    if enabled {
                        Section("Окно") {
                            Stepper("С \(startHour):00", value: $startHour, in: 0...23)
                            Stepper("По \(endHour):00", value: $endHour, in: 0...23)
                            Picker("Интервал", selection: $intervalIndex) {
                                ForEach(intervals.indices, id: \.self) { idx in
                                    Text("\(intervals[idx]) мин").tag(idx)
                                }
                            }
                        }
                        Section {
                            let perDay = reminderCountPerDay
                            Text("≈ \(perDay) напоминаний в день на приём · слоты из 64 считаются в настройках")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(medication.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onAppear {
                if let w = medication.notifyWindow {
                    enabled = true
                    startHour = w.startHour
                    endHour = w.endHour
                    intervalIndex = intervals.firstIndex(of: w.intervalMinutes) ?? 1
                } else {
                    enabled = false
                }
            }
        }
    }

    private var reminderCountPerDay: Int {
        guard enabled, endHour >= startHour else { return 0 }
        let span = (endHour - startHour) * 60
        return span / max(1, intervals[intervalIndex]) + 1
    }

    private func save() {
        var window: NotifyWindow?
        if enabled {
            // endHour < startHour = пустое окно; не даём сохранить бессмыслицу
            window = NotifyWindow(startHour: startHour,
                                  endHour: max(endHour, startHour),
                                  intervalMinutes: intervals[intervalIndex])
        }
        do {
            try store.setNotifyWindow(window, medicationId: medication.id)
            HapticManager.shared.notifySuccess()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
