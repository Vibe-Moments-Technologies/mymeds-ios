#!/usr/bin/env python3
"""
tools/update_version_feed.py — генерация канальных фидов и IPA-источника на gh-pages.

Порт механизма krasava-app, только iOS (apk_url из фидов убран).

Каналы и файлы:
  --channel stable   : version.json (автообновление обычных пользователей) + apps.json
  --channel beta|rc  : beta.json (opt-in бета-канал в настройках приложения) + apps.json
  --channel preview  : apps.json только (rolling dev-сборка main)

apps.json — ЕДИНЫЙ GBox/AltStore-источник: список всех живых каналов
(стабильный, beta, rc, dev) — по одной свежайшей сборке на канал. Каждый
запуск скрипта обновляет запись своего канала, остальные подтягиваются
из уже опубликованного apps.json (fetch с gh-pages). apps-beta.json
оставлен алиасом того же содержимого.

Вызывается ТОЛЬКО из релизного и preview-воркфлоу. Деплой на gh-pages
выполняет workflow (peaceiris/actions-gh-pages, keep_files).
"""

import argparse
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

APP_VERSION_FILE = "MyMedsCore/Sources/MyMedsCore/AppVersion.swift"
DEFAULT_REPO = "Vibe-Moments-Technologies/mymeds-ios"
BUNDLE_ID = "com.l1ratch.mymeds"
DEVELOPER_NAME = "Vibe Moments Technologies"
TINT_COLOR = "0EA5E9"
APP_DESCRIPTION = (
    "Дневник приёма лекарств: планы и блоки, чередование доз, "
    "кумулятивная доза, напоминания и отчёт врачу."
)
# Иконки в репо пока нет — iconURL в записи источника не добавляем,
# чтобы не давать мёртвую ссылку. Появится AppIcon — вернуть поле:
#   "iconURL": f"https://raw.githubusercontent.com/{repo}/main/<путь к png 1024x1024>"

# Канал → имя записи в источнике (по нему запись заменяется при обновлении).
CHANNEL_APP_NAMES = {
    "stable": "Мои Лекарства",
    "beta": "Мои Лекарства (Beta)",
    "rc": "Мои Лекарства (RC)",
    "preview": "Мои Лекарства (Dev)",
}
# Порядок каналов в списке источника.
CHANNEL_ORDER = ["stable", "rc", "beta", "preview"]


def parse_app_version(path):
    content = Path(path).read_text(encoding="utf-8")
    m = re.search(r'static\s+let\s+githubRepo\s*=\s*"([^"]+)"', content)
    repo = m.group(1) if m else DEFAULT_REPO
    m = (re.search(r'static let changelog = """\s*\n([\s\S]*?)\n\s*"""', content)
         or re.search(r'static let changelog = "([^"]*)"', content))
    changelog = m.group(1).strip() if m else ""
    m = re.search(r'static\s+let\s+isCritical\s*=\s*(true|false)', content)
    critical = (m.group(1) == "true") if m else False
    m = re.search(r'static\s+let\s+minSupportedBuild\s*=\s*(\d+)', content)
    min_supported = int(m.group(1)) if m else 1
    return repo, changelog, critical, min_supported


def asset_urls(repo, channel, version):
    if channel == "stable":
        base = f"https://github.com/{repo}/releases"
        return {
            "download_url": f"{base}/latest",
            "ipa_url": f"{base}/latest/download/MyMeds.ipa",
        }
    if channel in ("beta", "rc"):
        base = f"https://github.com/{repo}/releases/download/v{version}"
        return {
            # Страница релиза, а не папка download/ (она отдаёт 404)
            "download_url": f"https://github.com/{repo}/releases/tag/v{version}",
            "ipa_url": f"{base}/MyMeds-v{version}.ipa",
        }
    # preview (rolling dev)
    base = f"https://github.com/{repo}/releases/download/preview"
    return {
        "download_url": f"{base}/MyMeds-preview.ipa",
        "ipa_url": f"{base}/MyMeds-preview.ipa",
    }


def build_app_entry(repo, channel, version, ipa_url):
    """Одна запись канала в едином AltStore-совместимом источнике."""
    now = datetime.now(timezone.utc)
    # В description дублируем версию и время — так в GBox видно, что установлено.
    description = (
        f"{APP_DESCRIPTION}\n\n"
        f"Канал: {channel}\n"
        f"Сборка: {version}\n"
        f"Обновлено: {now.strftime('%Y-%m-%d %H:%M UTC')}"
    )
    return {
        "name": CHANNEL_APP_NAMES[channel],
        "bundleIdentifier": BUNDLE_ID,
        "developerName": DEVELOPER_NAME,
        "localizedDescription": description,
        "version": version,
        "versionDate": now.isoformat(),
        "downloadURL": ipa_url,
        "tintColor": TINT_COLOR,
        # Не AltStore-поле, нужно только нам: по нему запись канала заменяется.
        "channel": channel,
    }


def fetch_published_apps(repo):
    """Текущий apps.json с gh-pages — чтобы не потерять чужие каналы."""
    url = f"https://raw.githubusercontent.com/{repo}/gh-pages/apps.json"
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            data = json.loads(r.read().decode("utf-8"))
        apps = data.get("apps", [])
        return apps if isinstance(apps, list) else []
    except Exception as e:
        print(f"WARN: cannot fetch published apps.json ({e}); starting fresh", file=sys.stderr)
        return []


def build_source(repo, channel, version, ipa_url):
    """Единый источник: свежайшая сборка каждого канала в одном списке."""
    entry = build_app_entry(repo, channel, version, ipa_url)
    apps = []
    for a in fetch_published_apps(repo):
        if (isinstance(a, dict)
                and a.get("channel") in CHANNEL_ORDER
                and a.get("channel") != channel
                and a.get("name") != entry["name"]):
            a = dict(a)
            a["bundleIdentifier"] = BUNDLE_ID
            a["developerName"] = DEVELOPER_NAME
            apps.append(a)
    apps.append(entry)
    apps.sort(key=lambda a: CHANNEL_ORDER.index(a.get("channel"))
              if a.get("channel") in CHANNEL_ORDER else len(CHANNEL_ORDER))
    return {
        "name": "Мои Лекарства",
        "identifier": "mymeds-unified",
        "sourceURL": f"https://raw.githubusercontent.com/{repo}/gh-pages/apps.json",
        "apps": apps,
    }


def main():
    ap = argparse.ArgumentParser(description="Генерация фидов версий и IPA-источников")
    ap.add_argument("--channel", required=True, choices=["stable", "beta", "rc", "preview"])
    ap.add_argument("--version", required=True, help="Версия из tools/versioning.py")
    ap.add_argument("--build-number", type=int, required=True, help="epoch-код сборки")
    ap.add_argument("--commit-sha", default="")
    ap.add_argument("--out-dir", default="dist_version")
    ap.add_argument("--app-version-file", default=APP_VERSION_FILE)
    args = ap.parse_args()

    repo, changelog, critical, min_supported = parse_app_version(args.app_version_file)
    channel = args.channel
    is_stable = channel == "stable"
    # beta и rc пишут один и тот же фид: бета-канал приложения читает beta.json
    is_beta = channel in ("beta", "rc")
    urls = asset_urls(repo, channel, args.version)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []

    # 1) Канальные фиды обновлений приложения
    if is_stable or is_beta:
        feed = {
            "version": args.version,
            "build": args.build_number,
            "critical": critical and is_stable,
            "min_supported_build": min_supported if is_stable else 1,
            "changelog": changelog,
            "download_url": urls["download_url"],
            "ipa_url": urls["ipa_url"],
            "channel": "stable" if is_stable else channel,
            "prerelease": not is_stable,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if args.commit_sha:
            feed["commit_sha"] = args.commit_sha
        feed_name = "version.json" if is_stable else "beta.json"
        (out_dir / feed_name).write_text(
            json.dumps(feed, indent=2, ensure_ascii=False), encoding="utf-8")
        written.append(feed_name)

    # 2) Единый GBox/AltStore-источник: apps.json (все каналы).
    #    apps-beta.json — алиас того же содержимого для старых подписок.
    source = build_source(repo, channel, args.version, urls["ipa_url"])
    source_json = json.dumps(source, indent=2, ensure_ascii=False)
    for filename in ("apps.json", "apps-beta.json"):
        (out_dir / filename).write_text(source_json, encoding="utf-8")
        written.append(filename)

    print(f"Generated in {out_dir}: {', '.join(written)}")


if __name__ == "__main__":
    main()
