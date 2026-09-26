# Мои Лекарства (MyMeds iOS)

Дневник приёма лекарств: планы по лекарствам, чередование доз, блоки, кумулятивная доза, напоминания, отчёт врачу. Нативное SwiftUI-приложение, данные локально в контейнере App Group, без бэкенда.

- **Спецификация:** [MED_APP_SPEC.md](MED_APP_SPEC.md) — источник истины по модели данных и семантике.
- **Эталон резолва дня:** `_akn/day_resolver_reference.py` (исполняемое определение; Swift-порт сверяется с ним тестом `DayResolverTests.testReferenceSelftest`).
- **Миграция:** `_akn/` — справочная копия кода Telegram-бота `aknekytan-bot`, с которого переносятся данные.

## Структура

| Что | Где |
|---|---|
| Ядро: модель, резолв дня, хранение, кодеки (общее для app / widget / intent) | `MyMedsCore/` — локальный SPM-пакет |
| Приложение: только экраны | `MyMeds/` |
| Xcode-проект | **генерируемый**: `xcodegen generate` (`project.yml` — источник истины, `.xcodeproj` не коммитится) |
| CI и версионирование | `.github/workflows/`, `tools/` |

## Локальная сборка

```bash
brew install xcodegen                  # один раз
xcodegen generate
open MyMeds.xcodeproj                  # схема MyMeds, iOS 17+
swift test --package-path MyMedsCore   # тесты ядра без Xcode
```

## Версионирование и CI

Порт механизма [krasava-app](https://github.com/Vibe-Moments-Technologies/krasava-app) без Android.

В репозитории живёт только линия разработки — `AppVersion.releaseVersion` (`YY.X`, сейчас `26.1`). Полную версию с суффиксом и числовой код сборки (`CFBundleVersion` = epoch-секунды, одно число на весь запуск — считается в resolve-джобе) подставляет CI; в коммиты они не попадают.

| Канал | Триггер | Версия | Результат |
|---|---|---|---|
| dev | push в `main` (код приложения) | `26.1-dev.N` | rolling prerelease `preview` + `apps.json` на gh-pages |
| beta / rc | тег `v26.1-beta.N` / `v26.1-rc.N` | `26.1-beta.N` | иммутабельный prerelease + `beta.json` |
| stable | тег `v26.1` / `v26.1.1` | `26.1` | иммутабельный release (latest) + `version.json` |
| contrib | ручной dispatch любой ветки | `26.1-contrib.N` | только Actions Artifacts |

Workflow: `build-mobile.yml` (теги), `preview-main.yml` (dev), `build-test-branch.yml` (contrib). Перед сборкой IPA прогоняются unit-тесты `MyMedsCore` (`swift test`).

IPA собирается **без подписи** (`CODE_SIGNING_ALLOWED=NO`) — для sideload-установки через GBox/AltStore-источник (`apps.json` на gh-pages). Публикация в App Store — отдельный процесс с подписью, CI его пока не трогает.

**Выпуск релиза:** поднять `AppVersion.releaseVersion` + обновить `changelog` → `git tag v26.1 && git push --tags`.
