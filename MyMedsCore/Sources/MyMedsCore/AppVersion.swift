import Foundation

/// Единый источник версии (модель — порт krasava-app, см. tools/versioning.py).
///
/// В репозитории живёт ТОЛЬКО линия разработки `releaseVersion` (YY.X).
/// Полную версию с суффиксом (-dev.N / -beta.N / -rc.N / -contrib.N), канал,
/// числовой код сборки (epoch-секунды) и sha подставляет CI командой
/// `python3 tools/versioning.py prepare …` — эти значения не коммитятся.
public enum AppVersion {
    /// Линия разработки (YY.X). Поднимается при открытии новой линии релизов.
    public static let releaseVersion = "26.1"
    /// Полная версия. CI патчит на литерал, например "26.1-dev.3", "26.1-beta.1".
    public static let versionName = releaseVersion
    /// Канал сборки: stable | beta | rc | dev | contrib | local.
    public static let buildChannel = "local"
    /// Числовой код сборки (CFBundleVersion) — epoch-секунды. Патчится CI.
    public static let buildNumber = 0
    public static let commitSha = "local"
    public static let githubRepo = "Vibe-Moments-Technologies/mymeds-ios"
    /// «Что нового» — идёт в ноты GitHub Release и фиды обновлений.
    public static let changelog = """
    Первая dev-сборка: модель данных, резолв дня, хранение в App Group.
    """
    public static let isCritical = false
    public static let minSupportedBuild = 1
}
