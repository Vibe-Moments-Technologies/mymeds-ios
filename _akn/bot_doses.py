"""
Утилиты для работы с датами и расчётом дозировок по планам приёма.
"""
import json
from datetime import date

def get_course_day(start_date_str: str) -> int:
    """Вычислить реальный день относительно даты начала (1-indexed)."""
    if not start_date_str:
        return 1
    start = date.fromisoformat(start_date_str)
    diff = (date.today() - start).days + 1
    return max(1, diff)

def get_current_day(start_date_str: str, duration_days: int) -> int:
    """Вернуть относительный день, ограниченный длительностью плана."""
    return min(get_course_day(start_date_str), duration_days)

def get_plan_dose_info(plan: dict, day_num: int) -> dict:
    """
    Получить плановую дозировку основного препарата для конкретного дня плана.

    Возвращает:
    {
        "dose": int,          -- плановая доза в мг
        "title": str,         -- название основного препарата
        "block_day": int,     -- день внутри блока
        "block_days": int,    -- всего дней в блоке
        "plan_name": str      -- название плана (например, "Блок 2")
    }
    """
    try:
        sched = json.loads(plan["schedule_json"])
        med = next((m for m in sched.get("medications", []) if m["id"] == 'main'), None)
        if med:
            day_info = med.get("schedule", {}).get(str(day_num), {})
            dose = int(day_info.get("dose_mg", 16))
            title = med.get("title", "Акнекутан")
        else:
            dose = 16
            title = "Акнекутан"
        duration = int(sched.get("duration_days", 28))
    except Exception:
        dose = 16
        title = "Акнекутан"
        duration = 28

    return {
        "dose": dose,
        "title": title,
        "block_day": day_num,
        "block_days": duration,
        "plan_name": plan["name"]
    }

def get_medication_day_info(plan: dict, medication_id: str, day_num: int) -> dict | None:
    """Получить расписание доп. лекарства на конкретный день."""
    try:
        sched = json.loads(plan["schedule_json"])
        med = next((m for m in sched.get("medications", []) if m["id"] == medication_id), None)
        if not med:
            return None

        day_info = med.get("schedule", {}).get(str(day_num), {})
        # Проверяем, активно ли лекарство в этот день
        if not day_info.get("active"):
            return None

        return {
            "title": med["title"],
            "dose_text": med.get("dose_text", "1 капсула"),
            "notify_start_hour": int(day_info.get("notify_start_hour", 9)),
            "notify_end_hour": int(day_info.get("notify_end_hour", 12)),
            "notify_interval_min": int(day_info.get("notify_interval_min", 60)),
        }
    except Exception:
        return None

def get_plan_medications_for_day(plan: dict, day_num: int) -> list[dict]:
    """Получить список всех дополнительных лекарств, назначенных на указанный день плана."""
    try:
        sched = json.loads(plan["schedule_json"])
        meds = []
        for med in sched.get("medications", []):
            if med.get("type") == "main":
                continue
            day_info = get_medication_day_info(plan, med["id"], day_num)
            if day_info:
                day_info["id"] = med["id"]
                meds.append(day_info)
        return meds
    except Exception:
        return []
