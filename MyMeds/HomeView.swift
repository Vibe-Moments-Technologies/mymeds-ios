import SwiftUI
import MyMedsCore
import DesignSystem

/// Корень приложения (§12): один главный экран, настройки — шестерёнка сверху.
/// Dock не строим — экраны самодостаточны, TabView добавляется обёрткой.
struct HomeView: View {
    @Environment(DataStore.self) private var store
    @State private var showSettings = false
    @State private var detailItem: DataStore.DayItem?
    @State private var errorText: String?

    private var items: [DataStore.DayItem] { store.todaysItems() }
    private var takenCount: Int { items.filter { $0.status == .taken }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        if items.isEmpty {
                            emptyState
                        } else {
                            ForEach(items) { item in
                                IntakeRow(
                                    item: item,
                                    onDetail: { detailItem = item },
                                    onError: { errorText = $0 }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CalendarView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        MedicationsListView()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $detailItem) { DayDetailSheet(item: $0) }
            .onChange(of: store.data) { _, _ in
                // Любая мутация (отметка/доза/импорт/настройки) → перевзвод
                // скользящего окна уведомлений (§8: идемпотентный пересчёт).
                NotificationSetup.reschedule()
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    private var summaryCard: some View {
        GlassCard {
            HStack(spacing: 20) {
                GlassProgressRing(
                    progress: items.isEmpty ? 0 : Double(takenCount) / Double(items.count),
                    size: 72,
                    caption: "сегодня")
                VStack(alignment: .leading, spacing: 6) {
                    Text(CivilDate.today().humanText)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(items.isEmpty
                         ? " приёмов нет"
                         : "\(takenCount) из \(items.count) принято")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "cross.case")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("На сегодня приёмов нет")
                    .font(.system(.headline, design: .rounded))
                Text("Импортируйте план (medplan/1) или полную историю из бота: Настройки → Импорт данных")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Открыть настройки") { showSettings = true }
                    .buttonStyle(GlassButtonStyle(tint: Palette.primary, isProminent: true))
            }
            .padding(8)
        }
    }
}

/// Строка приёма = один Entry (§5). Один компонент на Home, календарь и
/// сетку плана (§12): отметка, сброс, детали/доза.
struct IntakeRow: View {
    let item: DataStore.DayItem
    var onDetail: () -> Void
    var onError: (String) -> Void

    @Environment(DataStore.self) private var store

    var body: some View {
        GlassCard(tint: item.medication.accent.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.medication.name)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(doseText(item.plannedDose, unit: item.medication.unit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(item.plan.name) · день \(item.entry.day)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassBadge(label: item.status.label, icon: item.status.icon,
                               color: item.status.color)
                }
                HStack(spacing: 10) {
                    markButton("Принял", icon: "checkmark", tint: .green, status: .taken)
                    markButton("Пропустил", icon: "xmark", tint: .orange, status: .skipped)
                    Spacer()
                    if item.intake?.status != nil {
                        Button {
                            do {
                                try store.resetMark(planId: item.entry.planId, day: item.entry.day)
                                HapticManager.shared.notifyWarning()
                            } catch {
                                onError(error.localizedDescription)
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                    Button(action: onDetail) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.medication.accent)
                            .padding(10)
                    }
                    .buttonStyle(GlassButtonStyle(tint: item.medication.accent))
                }
            }
        }
        .animation(Motion.statusChange, value: item.status)
    }

    private func markButton(_ title: String, icon: String, tint: Color,
                            status: Intake.Status) -> some View {
        Button {
            do {
                try store.mark(planId: item.entry.planId, day: item.entry.day, status: status)
                HapticManager.shared.notifySuccess()
            } catch {
                onError(error.localizedDescription)
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(GlassButtonStyle(tint: tint))
    }
}
