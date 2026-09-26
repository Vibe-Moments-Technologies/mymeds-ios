"""
Планировщик уведомлений, автопропуска и бэкапов.
"""
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime, time, date
import pytz
import logging
import os
import json

from aiogram.types import FSInputFile, InlineKeyboardMarkup, InlineKeyboardButton

from bot.config import (
    ADMIN_ID,
    DB_PATH,
    TZ,
)
from bot.database import (
    backup_sent_today,
    get_active_plan,
    get_plan_intake,
    get_user_settings,
    log_backup_sent,
    log_event,
    log_reminder,
    mark_plan_intake,
    count_reminders_today,
    complete_plan,
    auto_complete_and_activate_next,
    get_today_meds_status,
)
from bot.doses import (
    get_course_day,
    get_current_day,
    get_plan_dose_info,
    get_plan_medications_for_day,
)
from bot.keyboards import today_keyboard, med_reminder_keyboard

logger = logging.getLogger(__name__)
MOSCOW_TZ = pytz.timezone(TZ)


def _within_window(now: datetime, start_hour: int, end_hour: int, end_minute: int = 0) -> bool:
    notify_start = time(start_hour, 0)
    notify_end = time(end_hour, end_minute)
    return notify_start <= now.time() <= notify_end


def _is_reminder_slot(now: datetime, start_hour: int, interval_min: int) -> bool:
    start_minutes = start_hour * 60
    now_minutes = now.hour * 60 + now.minute
    return (now_minutes - start_minutes) % interval_min == 0


async def check_and_remind(bot):
    """Фоновая рассылка напоминаний для основного препарата."""
    now = datetime.now(MOSCOW_TZ)
    user_id = ADMIN_ID
    settings = await get_user_settings(user_id)

    plan = await get_active_plan(user_id)
    if not plan or not plan["start_date"]:
        return

    duration = 28
    try:
        sched = json.loads(plan["schedule_json"])
        duration = int(sched.get("duration_days", 28))
    except Exception:
        pass

    real_day = get_course_day(plan["start_date"])
    
    # Если курс по датам уже завершён, переводим план в completed и пробуем активировать следующий
    if real_day > duration:
        today_str = date.today().isoformat()
        next_plan = await auto_complete_and_activate_next(plan["id"], today_str)
        await log_event(user_id, "plan_completed_auto", plan["id"], source="scheduler")
        
        if next_plan:
            await log_event(user_id, "plan_activated_auto", next_plan["id"], source="scheduler")
            try:
                await bot.send_message(
                    user_id,
                    f"🎉 Блок «{plan['name']}» успешно завершился (все {duration} дней пройдены)!\n\n"
                    f"🚀 <b>Автоматически активирован следующий блок</b> из очереди:\n"
                    f"📦 <b>{next_plan['name']}</b> (день 1)\n\n"
                    f"Все новые напоминания будут приходить по расписанию этого блока."
                )
            except Exception as e:
                logger.error("Ошибка отправки уведомления об автопереходе на новый план: %s", e)
        else:
            try:
                await bot.send_message(
                    user_id,
                    f"🎉 План «{plan['name']}» подошёл к концу! Все {duration} дней пройдены.\n\n"
                    f"⚠️ В очереди нет будущих блоков. Пожалуйста, соберите новую схему в конструкторе и загрузите её в бота."
                )
            except Exception as e:
                logger.error("Ошибка отправки уведомления об автозавершении плана: %s", e)
        return

    # Проверка окна и интервала напоминаний основного препарата
    if not _within_window(now, settings["notify_start_hour"], settings["notify_end_hour"], settings["notify_end_minute"]) or \
       not _is_reminder_slot(now, settings["notify_start_hour"], settings["notify_interval_min"]):
        return

    day_num = get_current_day(plan["start_date"], duration)

    # Проверяем, есть ли уже отметка за сегодня
    intake = await get_plan_intake(plan["id"], day_num, "main")
    if intake and intake["status"] != "not_marked":
        return

    dose_info = get_plan_dose_info(plan, day_num)
    dose_mg = intake["dose_mg"] if intake and intake.get("dose_mg") is not None else dose_info["dose"]
    today_str = now.date().isoformat()
    reminder_count = await count_reminders_today(user_id, today_str, "main")

    if reminder_count == 0:
        text = (
            f"⏰ Время приёма препарата\n\n"
            f"📅 {plan['name']} · день {day_num}/{duration}\n"
            f"💊 Сегодня: {dose_mg} мг ({dose_info['title']})\n"
            f"🍽 Принимать за ужином с жирной едой\n\n"
            f"Окно отметки: {settings['notify_start_hour']:02d}:00–"
            f"{settings['notify_end_hour']:02d}:{settings['notify_end_minute']:02d}"
        )
    else:
        text = (
            f"🔔 Напоминание #{reminder_count + 1}\n\n"
            f"💊 {plan['name']} · день {day_num} — {dose_mg} мг\n"
            f"Если уже приняли — просто нажмите кнопку, чтобы отключить напоминания на сегодня."
        )

    # Проверка приближения к концу блока при отсутствии следующего в очереди
    if duration - day_num <= 2:
        from bot.database import get_plans
        all_plans = await get_plans(user_id)
        future_plans = [p for p in all_plans if p["status"] == "future"]
        if not future_plans:
            days_left = duration - day_num
            if days_left == 0:
                text += "\n\n⚠️ <b>Внимание:</b> ваш текущий блок завершается СЕГОДНЯ! В очереди нет будущих планов. Пожалуйста, соберите новую схему в конструкторе и загрузите её."
            else:
                text += f"\n\n⚠️ <b>Внимание:</b> ваш текущий блок завершается через {days_left + 1} дн.! В очереди нет будущих планов. Пожалуйста, соберите новую схему в конструкторе и загрузите её."

    try:
        meds_status = await get_today_meds_status(plan, day_num)
        await bot.send_message(
            user_id,
            text,
            reply_markup=today_keyboard(plan["id"], day_num, meds_status)
        )
        await log_reminder(user_id, plan["id"], day_num, today_str, "main")
        await log_event(
            user_id,
            "reminder_sent",
            plan["id"],
            day_num,
            "scheduler",
            {"count": reminder_count + 1, "medication_id": "main"},
        )
        logger.info(f"Отправлено напоминание #{reminder_count + 1} по Акнекутану")
    except Exception as e:
        logger.error(f"Ошибка отправки напоминания по Акнекутану: {e}")


async def auto_skip_check(bot):
    """Автоматически закрыть неотмеченные препараты как пропуск."""
    now = datetime.now(MOSCOW_TZ)
    user_id = ADMIN_ID
    settings = await get_user_settings(user_id)

    if now.hour != settings["auto_skip_hour"] or now.minute != settings["auto_skip_minute"]:
        return

    plan = await get_active_plan(user_id)
    if not plan or not plan["start_date"]:
        return

    duration = 28
    try:
        sched = json.loads(plan["schedule_json"])
        duration = int(sched.get("duration_days", 28))
    except Exception:
        pass

    if get_course_day(plan["start_date"]) > duration:
        return

    day_num = get_current_day(plan["start_date"], duration)
    auto_skipped = []

    # Автопропуск не заменяет фактическую отметку: он записывается отдельным статусом.
    main_intake = await get_plan_intake(plan["id"], day_num, "main")
    if not main_intake or main_intake["status"] == "not_marked":
        await mark_plan_intake(plan["id"], day_num, "main", "auto_skipped")
        await log_event(user_id, "auto_skipped", plan["id"], day_num, "scheduler")
        auto_skipped.append("Акнекутан")

    # Дополнительные лекарства имеют тот же статусный переход.
    for med in get_plan_medications_for_day(plan, day_num):
        intake = await get_plan_intake(plan["id"], day_num, med["id"])
        if intake and intake["status"] != "not_marked":
            continue

        await mark_plan_intake(plan["id"], day_num, med["id"], "auto_skipped")
        await log_event(
            user_id,
            f"auto_skipped_{med['id']}",
            plan["id"],
            day_num,
            "scheduler",
            {"medication_id": med["id"]},
        )
        auto_skipped.append(med["title"])

    if not auto_skipped:
        return

    try:
        meds_status = await get_today_meds_status(plan, day_num)
        listed = "\n".join(f"• {title}" for title in auto_skipped)
        await bot.send_message(
            user_id,
            f"😴 <b>Автопропуск · {plan['name']} · день {day_num}</b>\n\n"
            f"Без фактической отметки закрыты:\n{listed}\n\n"
            "Автопропуск считается пропуском в статистике, но не заменяет фактический приём.\n"
            "Если вы приняли лекарство позже, нажмите ✅ ниже — обычная отметка заменит автопропуск.",
            reply_markup=today_keyboard(plan["id"], day_num, meds_status),
        )
        logger.info(
            "Автопропуск дня %s для плана %s: %s",
            day_num,
            plan["id"],
            ", ".join(auto_skipped),
        )
    except Exception as e:
        logger.error("Ошибка отправки сообщения об автопропуске: %s", e)

async def check_medication_reminders(bot):
    """Фоновые напоминания для дополнительных препаратов, привязанных к текущему дню плана."""
    now = datetime.now(MOSCOW_TZ)
    today_str = now.date().isoformat()
    user_id = ADMIN_ID

    plan = await get_active_plan(user_id)
    if not plan or not plan["start_date"]:
        return

    duration = 28
    try:
        sched = json.loads(plan["schedule_json"])
        duration = int(sched.get("duration_days", 28))
    except Exception:
        pass

    day_num = get_current_day(plan["start_date"], duration)
    if day_num > duration:
        return

    # Находим все доп. лекарства, назначенные на сегодня
    meds = get_plan_medications_for_day(plan, day_num)
    for med in meds:
        # Проверяем, есть ли уже отметка приёма за этот день
        intake = await get_plan_intake(plan["id"], day_num, med["id"])
        if intake and intake["status"] in {"taken", "skipped", "auto_skipped"}:
            continue

        # Проверяем временное окно для этого конкретного лекарства
        if not _within_window(now, med["notify_start_hour"], med["notify_end_hour"]) or \
           not _is_reminder_slot(now, med["notify_start_hour"], med["notify_interval_min"]):
            continue

        reminder_count = await count_reminders_today(user_id, today_str, med["id"])
        text = (
            f"🌿 Напоминание: {med['title']}\n\n"
            f"📅 {plan['name']} · день {day_num}/{duration}\n"
            f"💊 Доза: {med['dose_text']}\n"
            f"⏰ Окно: {med['notify_start_hour']:02d}:00–{med['notify_end_hour']:02d}:00\n\n"
            f"Нажмите кнопку ниже, чтобы отметить приём."
        )

        try:
            await bot.send_message(
                user_id,
                text,
                reply_markup=med_reminder_keyboard(plan["id"], day_num, med["id"], med["title"])
            )
            await log_reminder(user_id, plan["id"], day_num, today_str, med["id"])
            await log_event(
                user_id,
                "med_reminder_sent",
                plan["id"],
                day_num,
                "scheduler",
                {"medication_id": med["id"], "count": reminder_count + 1},
            )
            logger.info("Отправлено напоминание по доп. лекарству %s", med["id"])
        except Exception as e:
            logger.error("Ошибка отправки напоминания по %s: %s", med["id"], e)


async def send_db_backup(bot):
    """Отправить ежедневный бэкап SQLite в Telegram владельцу."""
    now = datetime.now(MOSCOW_TZ)
    user_id = ADMIN_ID
    settings = await get_user_settings(user_id)

    if not settings.get("backup_enabled"):
        return

    if now.hour != settings["backup_hour"] or now.minute != settings["backup_minute"]:
        return

    backup_date = now.date().isoformat()
    if await backup_sent_today(backup_date):
        return

    if not os.path.exists(DB_PATH):
        logger.warning("Бэкап БД не отправлен: файл не найден: %s", DB_PATH)
        return

    try:
        await bot.send_document(
            user_id,
            FSInputFile(DB_PATH, filename=f"aknekytan_{backup_date}.db"),
            caption=f"💾 Ежедневный бэкап базы за {backup_date}"
        )
        await log_backup_sent(backup_date)
        await log_event(user_id, "db_backup_sent", source="scheduler", metadata={"date": backup_date})
        logger.info("Бэкап БД отправлен за %s", backup_date)
    except Exception as e:
        logger.error("Ошибка отправки бэкапа БД: %s", e)


def setup_scheduler(scheduler: AsyncIOScheduler, bot):
    """Настроить все регулярные задачи."""
    # Проверка каждые 5 минут для основного препарата
    scheduler.add_job(
        check_and_remind,
        CronTrigger(minute="*/5", timezone=MOSCOW_TZ),
        id="remind_main",
        kwargs={"bot": bot},
        replace_existing=True
    )

    # Проверка каждую минуту для автопропуска, лекарств и бэкапов
    scheduler.add_job(
        auto_skip_check,
        CronTrigger(minute="*", timezone=MOSCOW_TZ),
        id="auto_skip",
        kwargs={"bot": bot},
        replace_existing=True
    )

    scheduler.add_job(
        send_db_backup,
        CronTrigger(minute="*", timezone=MOSCOW_TZ),
        id="db_backup",
        kwargs={"bot": bot},
        replace_existing=True
    )

    scheduler.add_job(
        check_medication_reminders,
        CronTrigger(minute="*", timezone=MOSCOW_TZ),
        id="med_reminders",
        kwargs={"bot": bot},
        replace_existing=True
    )

    logger.info("Планировщик перенастроен на динамическую логику планов приёма")
