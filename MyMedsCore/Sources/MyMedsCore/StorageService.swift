import Foundation

/// Единственный писатель `mymeds_data.json` (MED_APP_SPEC.md §8–9).
/// Приложение и Intent Handler пишут только через него; виджет — только чтение.
/// Сохранение: validate → `.bak` → temp-файл → атомарная замена, всё под
/// NSFileCoordinator (общий контейнер App Group читают три процесса).
///
/// // ponytail: перезапись всего файла на каждую отметку — O(n); при ~1 МБ
/// // незаметно. Упрёмся — GRDB/SwiftData без изменения модели, только этот слой.
public final class StorageService: @unchecked Sendable {
    public static let appGroupID = "group.com.l1ratch.mymeds"
    public static let fileName = "mymeds_data.json"
    public static let backupName = "mymeds_data.bak"

    private let directory: URL
    private let coordinator = NSFileCoordinator()
    private let fm = FileManager.default

    /// - Parameter directory: только для тестов; в проде — контейнер App Group.
    public init(directory: URL? = nil) {
        self.directory = directory ?? StorageService.defaultDirectory()
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        #if os(iOS)
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        // Откат без entitlements (симулятор): виджет и Intent Handler эти данные
        // не увидят — на устройстве App Group обязателен (§8).
        #endif
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public var fileURL: URL { directory.appendingPathComponent(StorageService.fileName) }
    public var backupURL: URL { directory.appendingPathComponent(StorageService.backupName) }

    /// Текущие данные; при повреждении основного файла — из `.bak`; нет ни того — nil.
    public func load() -> AppData? {
        for url in [fileURL, backupURL] {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? appJSONDecoder.decode(AppData.self, from: data) else { continue }
            return decoded
        }
        return nil
    }

    /// Валидирует (§3) и атомарно сохраняет, обновляя `.bak`.
    /// Возвращает данные как сохранены (с проставленным exportedAt).
    @discardableResult
    public func save(_ data: AppData) throws -> AppData {
        var payload = data
        payload.exportedAt = Date()
        try payload.validate()
        let encoded = try appJSONEncoder.encode(payload)

        var coordinationError: NSError?
        var writeError: Error?
        let options: NSFileCoordinator.WritingOptions =
            fm.fileExists(atPath: fileURL.path) ? [.forReplacing] : []
        coordinator.coordinate(writingItemAt: fileURL, options: options, error: &coordinationError) { url in
            do {
                if self.fm.fileExists(atPath: url.path) {
                    if self.fm.fileExists(atPath: self.backupURL.path) {
                        try self.fm.removeItem(at: self.backupURL)
                    }
                    try self.fm.copyItem(at: url, to: self.backupURL)
                }
                let tmp = self.directory.appendingPathComponent(".\(StorageService.fileName).tmp")
                try encoded.write(to: tmp)
                if self.fm.fileExists(atPath: url.path) {
                    _ = try self.fm.replaceItemAt(url, withItemAt: tmp)
                } else {
                    try self.fm.moveItem(at: tmp, to: url)
                }
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        return payload
    }
}

// Общие кодеки модуля (ISO-8601 даты) — используются StorageService и MedPlanCodec.
let appJSONEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return e
}()

let appJSONDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()
