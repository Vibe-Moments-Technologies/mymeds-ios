#!/usr/bin/env python3
"""
tools/migrate_from_bot.py — разовый конвертер aknekytan.db → mymeds-backup/1.

Реализует маппинг MED_APP_SPEC.md §10. Запуск:
    python tools/migrate_from_bot.py migration/aknekytan.db -o migration/mymeds_backup.json

Выход содержит ЛИЧНЫЕ данные — в git не коммитится (migration/ в .gitignore).
БД однопользовательская (бот личный): user_settings берутся для единственного user_id.

Ключевые решения маппинга:
- main-препарат → одна общая Medication (unit mg) + по Plan на каждый блок бота;
- additional → отдельные Medication + Plan на каждый блок, где у лекарства есть
  активные дни; dose_text парсится в (dose, unit) — «1 капсула» → 1.0/capsule;
- notify_* additional-лекарств одинаковы во все дни → сворачиваем на Medication (§13.3);
- auto_skipped НЕ импортируется — на устройстве станет производным missed (§6);
- not_marked → status null + doseOverride (§10);
- actualDose: dose_mg бота, а для additional (где dose_mg NULL) — доза из сетки
  дня: повторяет правило приложения «actualDose наследует дозу расписания» (§3).
"""

import argparse
import json
import re
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

# Порядок важен: «мкг» проверяется раньше «мг».
UNIT_PATTERNS = [
    (re.compile(r"мкг", re.I), "mcg"),
    (re.compile(r"мг", re.I), "mg"),
    (re.compile(r"\bме\b", re.I), "iu"),
    (re.compile(r"капсул", re.I), "capsule"),
    (re.compile(r"таблет", re.I), "tablet"),
    (re.compile(r"капл", re.I), "drop"),
    (re.compile(r"мл", re.I), "ml"),
]


def parse_dose_text(text):
    """«1 капсула» → (1.0, 'capsule'); «2000 МЕ» → (2000.0, 'iu'). Без числа → 1."""
    if not text or not text.strip():
        raise ValueError("пустой dose_text")
    m = re.match(r"\s*(\d+(?:[.,]\d+)?)?\s*(.*)", text)
    num = float(m.group(1).replace(",", ".")) if m and m.group(1) else 1.0
    rest = m.group(2) or text
    for rx, unit in UNIT_PATTERNS:
        if rx.search(rest):
            return num, unit
    raise ValueError(f"не могу разобрать dose_text: {text!r}")


def to_iso(text):
    """sqlite 'YYYY-MM-DD HH:MM:SS' (UTC, datetime('now')) → 'YYYY-MM-DDTHH:MM:SSZ'."""
    if not text:
        return None
    t = text.strip().replace(" ", "T")
    return t if t.endswith("Z") else t + "Z"


def main():
    ap = argparse.ArgumentParser(description="aknekytan.db → mymeds-backup/1")
    ap.add_argument("db", help="путь к aknekytan.db")
    ap.add_argument("-o", "--out", default="migration/mymeds_backup.json")
    ap.add_argument("--main-only", action="store_true",
                    help="только основной препарат (Акнекутан): additional-лекарства не импортируются")
    args = ap.parse_args()

    db = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row

    users = [r["user_id"] for r in db.execute("SELECT user_id FROM users")]
    if len(users) != 1:
        sys.exit(f"Ожидалась однопользовательская БД, users: {users}")
    user_id = users[0]

    main_window = None
    srow = db.execute("SELECT * FROM user_settings WHERE user_id=?", (user_id,)).fetchone()
    if srow:
        main_window = {
            "startHour": srow["notify_start_hour"],
            "endHour": srow["notify_end_hour"],
            "intervalMinutes": srow["notify_interval_min"],
        }

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    medications = {}   # bot med id → app Medication dict
    plans_out = []
    plan_map = {}      # (bot plan_id, bot med id) → (app plan uuid, {day: dose})
    stats = {"blocks": 0, "additional_plans": 0, "intakes_by_status": {},
             "dropped_auto_skipped": 0, "not_marked": 0, "orphan_marks": 0}

    def med_for(bot_id, title, unit, form=None, notify=None):
        m = medications.get(bot_id)
        if m is None:
            m = {"id": str(uuid.uuid4()), "name": title, "unit": unit, "createdAt": now_iso}
            if form:
                m["form"] = form
            if notify:
                m["notifyWindow"] = notify
            medications[bot_id] = m
        else:
            if m["name"] != title:
                print(f"WARN: у лекарства {bot_id} разные названия: {m['name']!r} vs {title!r}", file=sys.stderr)
            if notify and not m.get("notifyWindow"):
                m["notifyWindow"] = notify
        return m

    for prow in db.execute("SELECT * FROM plans ORDER BY id"):
        sched = json.loads(prow["schedule_json"])
        duration = int(sched["duration_days"])
        meds = sched.get("medications", [])
        main = next((m for m in meds if m.get("id") == "main" or m.get("type") == "main"), None)
        if main is None:
            print(f"WARN: план {prow['id']} без main-лекарства — пропущен", file=sys.stderr)
            continue

        main_med = med_for("main", main.get("title", ""), "mg", notify=main_window)
        grid = {}
        for d, slot in main.get("schedule", {}).items():
            dose = slot.get("dose_mg")
            if dose is None:
                continue
            grid[str(int(d))] = {"dose": float(dose), "times": 1}
        app_plan = {
            "id": str(uuid.uuid4()),
            "medicationId": main_med["id"],
            "name": prow["name"],
            "startDate": prow["start_date"] or None,
            "durationDays": duration,
            "schedule": grid,
            "stoppedAt": None,
            "createdAt": to_iso(prow["created_at"]) or now_iso,
            "updatedAt": to_iso(prow["updated_at"]) or now_iso,
        }
        plans_out.append(app_plan)
        plan_map[(prow["id"], "main")] = (app_plan["id"], {int(k): v["dose"] for k, v in grid.items()})
        stats["blocks"] += 1

        for m in meds:
            if m.get("id") == "main" or m.get("type") == "main":
                continue
            if args.main_only:
                continue
            dose_val, unit = parse_dose_text(m.get("dose_text", ""))
            active_days, notify_variants = {}, set()
            for d, slot in m.get("schedule", {}).items():
                if slot.get("active"):
                    active_days[str(int(d))] = {"dose": dose_val, "times": 1}
                    nh = (slot.get("notify_start_hour"), slot.get("notify_end_hour"),
                          slot.get("notify_interval_min"))
                    if all(v is not None for v in nh):
                        notify_variants.add(nh)
            if not active_days:
                continue  # в этом блоке у лекарства нет активных дней
            if len(notify_variants) > 1:
                print(f"WARN: {m['id']}: разные окна уведомлений по дням: {notify_variants}", file=sys.stderr)
            notify = None
            if notify_variants:
                s, e, i = next(iter(notify_variants))
                notify = {"startHour": s, "endHour": e, "intervalMinutes": i}
            app_med = med_for(m["id"], m.get("title", m["id"]), unit,
                              form=m.get("dose_text"), notify=notify)
            app_plan = {
                "id": str(uuid.uuid4()),
                "medicationId": app_med["id"],
                "name": f"{prow['name']} · {app_med['name']}",
                "startDate": prow["start_date"] or None,
                "durationDays": duration,
                "schedule": active_days,
                "stoppedAt": None,
                "createdAt": to_iso(prow["created_at"]) or now_iso,
                "updatedAt": to_iso(prow["updated_at"]) or now_iso,
            }
            plans_out.append(app_plan)
            plan_map[(prow["id"], m["id"])] = (
                app_plan["id"], {int(k): v["dose"] for k, v in active_days.items()})
            stats["additional_plans"] += 1

    intakes_out = []
    seen = set()
    for irow in db.execute("SELECT * FROM plan_intakes ORDER BY id"):
        st = irow["status"]
        stats["intakes_by_status"][st] = stats["intakes_by_status"].get(st, 0) + 1
        if st == "auto_skipped":
            stats["dropped_auto_skipped"] += 1
            continue  # станет производным missed (§6)
        key = (irow["plan_id"], irow["medication_id"])
        if key not in plan_map:
            print(f"WARN: intake plan_id={key[0]} med={key[1]} day={irow['day_num']} — "
                  f"нет такого плана в маппинге, пропущен", file=sys.stderr)
            continue
        app_plan_id, doses = plan_map[key]
        day = int(irow["day_num"])
        dose_mg = irow["dose_mg"]
        if st == "not_marked":
            status, taken_at, actual = None, None, None
            dose_override = float(dose_mg) if dose_mg is not None else None
            stats["not_marked"] += 1
        else:
            status, dose_override = st, None
            actual = float(dose_mg) if dose_mg is not None else doses.get(day)
            taken_at = to_iso(irow["taken_at"])
            if actual is None:
                stats["orphan_marks"] += 1
                print(f"WARN: отметка {st} в дне {day} вне активных дней — actualDose=None", file=sys.stderr)
        uk = (app_plan_id, day)
        if uk in seen:
            print(f"WARN: дубль intake {uk} — пропущен", file=sys.stderr)
            continue
        seen.add(uk)
        intakes_out.append({
            "id": str(uuid.uuid4()),
            "planId": app_plan_id,
            "day": day,
            "status": status,
            "actualDose": actual,
            "takenAt": taken_at,
            "doseOverride": dose_override,
        })

    # ---- валидация: зеркало AppData.validate() (MED_APP_SPEC.md §3) ----
    errors = []
    med_uuids = {m["id"] for m in medications.values()}
    plan_by_uuid = {p["id"]: p for p in plans_out}
    for p in plans_out:
        if p["durationDays"] <= 0:
            errors.append(f"план {p['name']}: durationDays <= 0")
        if p["medicationId"] not in med_uuids:
            errors.append(f"план {p['name']}: medicationId не существует")
        for d, slot in p["schedule"].items():
            if not 1 <= int(d) <= p["durationDays"]:
                errors.append(f"план {p['name']}: день {d} вне 1..{p['durationDays']}")
            if slot["dose"] < 0 or slot["times"] < 1:
                errors.append(f"план {p['name']}: некорректный слот дня {d}")
    for i in intakes_out:
        p = plan_by_uuid.get(i["planId"])
        if p is None:
            errors.append("intake без плана")
            continue
        if not 1 <= i["day"] <= p["durationDays"]:
            errors.append(f"intake день {i['day']} вне диапазона плана {p['name']}")
        if i["status"] and not i["takenAt"]:
            errors.append(f"intake (day {i['day']}): status без takenAt")
    if errors:
        for e in errors:
            print("ERROR:", e, file=sys.stderr)
        sys.exit(f"валидация не прошла: {len(errors)} ошибок — файл НЕ записан")

    # ---- контрольные суммы: должны сойтись с ботом (/stats, get_plan_stats) ----
    main_uuid = medications["main"]["id"]
    main_plan_ids = {p["id"] for p in plans_out if p["medicationId"] == main_uuid}
    taken = [i for i in intakes_out if i["status"] == "taken" and i["planId"] in main_plan_ids]
    total_mg = sum(i["actualDose"] or 0 for i in taken)
    src = db.execute("SELECT COUNT(*), COALESCE(SUM(dose_mg),0) FROM plan_intakes "
                     "WHERE medication_id='main' AND status='taken'").fetchone()
    print(f"main taken: app={len(taken)} bot={src[0]} · total mg: app={total_mg:g} bot={src[1]}")
    if len(taken) != src[0] or abs(total_mg - src[1]) > 1e-9:
        sys.exit("КОНТРОЛЬ НЕ СОШЁЛСЯ с ботом — миграция прервана")
    src_sk = db.execute("SELECT COUNT(*) FROM plan_intakes "
                        "WHERE medication_id='main' AND status='skipped'").fetchone()[0]
    app_sk = len([i for i in intakes_out if i["status"] == "skipped" and i["planId"] in main_plan_ids])
    print(f"main skipped: app={app_sk} bot={src_sk}")
    if app_sk != src_sk:
        sys.exit("КОНТРОЛЬ skipped НЕ СОШЁЛСЯ — миграция прервана")

    print("\nper-plan (bot get_plan_stats, main):")
    for prow in db.execute("SELECT id, name FROM plans ORDER BY id"):
        rows = {r["status"]: (r["n"], r["mg"]) for r in db.execute(
            "SELECT status, COUNT(*) n, COALESCE(SUM(dose_mg),0) mg FROM plan_intakes "
            "WHERE plan_id=? AND medication_id='main' GROUP BY status", (prow["id"],))}
        bot_taken = rows.get("taken", (0, 0))
        app_p = plan_map[(prow["id"], "main")][0]
        app_taken = [i for i in intakes_out if i["planId"] == app_p and i["status"] == "taken"]
        app_mg = sum(i["actualDose"] or 0 for i in app_taken)
        flag = "OK" if (len(app_taken), app_mg) == (bot_taken[0], float(bot_taken[1])) else "MISMATCH"
        print(f"  {prow['name']}: bot taken={bot_taken[0]} mg={bot_taken[1]} · "
              f"app taken={len(app_taken)} mg={app_mg:g} [{flag}]")
        if flag == "MISMATCH":
            sys.exit("per-plan контроль не сошёлся")

    data = {
        "format": "mymeds-backup/1",
        "version": 1,
        "medications": list(medications.values()),
        "plans": plans_out,
        "intakes": intakes_out,
        "settings": {"notifyHorizonDays": 3},
        "exportedAt": now_iso,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # interaction_events → архивный экспорт (§10: не для рантайма)
    events = [dict(r) for r in db.execute("SELECT * FROM interaction_events ORDER BY event_at")]
    if events:
        ev = out.parent / "interaction_events.json"
        ev.write_text(json.dumps(events, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"\ninteraction_events: {len(events)} -> {ev}")

    print(f"\nИТОГ: лекарств={len(medications)} планов={len(plans_out)} "
          f"(блоков={stats['blocks']}, доп={stats['additional_plans']}) отметок={len(intakes_out)}")
    print(f"  статусы бота: {stats['intakes_by_status']}")
    print(f"  auto_skipped отброшено (станет производным missed): {stats['dropped_auto_skipped']}")
    print(f"  not_marked -> doseOverride: {stats['not_marked']}; отметок вне активных дней: {stats['orphan_marks']}")
    print(f"  записано: {out}")


if __name__ == "__main__":
    main()
