import WidgetKit
import SwiftUI
import AppIntents
import MyMedsCore

// Виджет (§12): entries(on: .now) из App Group, только чтение; отметка —
// через AppIntents-кнопки (единственный писатель StorageService, §8).
//
// // ponytail: Live Activity (живое окно напоминаний на локскрине) не делаем —
// // отметка с экрана блокировки достигается интерактивным виджетом; Activity
// // добавим, когда появится сценарий «активное окно 20:00–23:00», требующий
// // старта Activity из приложения и его остановки.

@main
struct MyMedsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

// MARK: - Timeline

struct TodayTimelineEntry: TimelineEntry {
    let date: Date
    let items: [DataStore.DayItem]
}

struct TodayProvider: TimelineProvider {
    private func loadItems() -> [DataStore.DayItem] {
        DataStore().items(on: .today())
    }

    func placeholder(in context: Context) -> TodayTimelineEntry {
        TodayTimelineEntry(date: .now, items: loadItems())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTimelineEntry) -> Void) {
        completion(TodayTimelineEntry(date: .now, items: loadItems()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTimelineEntry>) -> Void) {
        let entry = TodayTimelineEntry(date: .now, items: loadItems())
        // Отметки дёргают reload сами (интент); здесь подстраховка:
        // обновить после полуночи, но не позже чем через 6 часов.
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let midnight = calendar.startOfDay(for: tomorrow)
        let refresh = min(midnight, Date.now.addingTimeInterval(6 * 3600))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyMedsToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground).opacity(0.92)
                }
        }
        .configurationDisplayName("Сегодня")
        .description("Приёмы дня и отметки с экрана блокировки")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - UI

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayTimelineEntry

    var body: some View {
        if family == .systemSmall {
            smallView
        } else {
            mediumView
        }
    }

    private var smallView: some View {
        let taken = entry.items.filter { $0.status == .taken }.count
        return VStack(spacing: 6) {
            Text("\(taken)/\(entry.items.count)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("принято сегодня")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        VStack(spacing: 6) {
            if entry.items.isEmpty {
                Text("На сегодня приёмов нет")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.items.prefix(4))) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(item.status))
                            .frame(width: 8, height: 8)
                        Text(item.medication.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(doseText(item.plannedDose, unit: item.medication.unit))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        markButton(item, .taken, "checkmark", .green)
                        markButton(item, .skipped, "xmark", .orange)
                    }
                }
            }
        }
    }

    /// Кнопка-отметка: Intent выполняется в процессе расширения, пишет через
    /// тот же StorageService (App Group + NSFileCoordinator — §8).
    private func markButton(_ item: DataStore.DayItem, _ status: Intake.Status,
                            _ icon: String, _ color: Color) -> some View {
        // item.status — производный IntakeStatus, status — сохраняемый Intake.Status;
        // raw values совпадают ("taken"/"skipped")
        let selected = item.status == IntakeStatus(rawValue: status.rawValue)
        return Button(intent: MarkIntakeIntent(planId: item.entry.planId.uuidString,
                                                day: item.entry.day,
                                                status: status)) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? Color.white : color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(selected ? color : color.opacity(0.18)))
        }
        .buttonStyle(.borderless)
    }

    private func statusColor(_ status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .missed: return .red
        case .pending: return .cyan
        case .scheduled: return .gray
        }
    }
}

// MARK: - App Intents (отметка с экрана блокировки)

struct MarkIntakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить приём"

    @Parameter(title: "План", default: "")
    var planId: String

    @Parameter(title: "День", default: 0)
    var day: Int

    @Parameter(title: "Статус", default: "taken")
    var statusString: String

    init() {}

    init(planId: String, day: Int, status: Intake.Status) {
        self.planId = planId
        self.day = day
        self.statusString = status.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: planId),
              let status = Intake.Status(rawValue: statusString) else {
            return .result()
        }
        let store = DataStore()
        try? store.mark(planId: id, day: day, status: status)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
