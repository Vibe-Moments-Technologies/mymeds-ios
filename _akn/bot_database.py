"""
Работа с базой данных SQLite через aiosqlite (динамическая модель планов).
"""
import aiosqlite
import os
import json
from datetime import date, datetime, timedelta
import pytz

from bot.config import (
    DB_PATH,
    TZ,
)

def _now_iso() -> str:
    return datetime.now(pytz.timezone(TZ)).isoformat(timespec="seconds")

async def init_db():
    """Инициализация базы данных и создание всех таблиц."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

    async with aiosqlite.connect(DB_PATH) as db:
        # Таблица пользователей
        await db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                user_id     INTEGER PRIMARY KEY,
                username    TEXT,
                first_name  TEXT,
                tz          TEXT DEFAULT 'Europe/Moscow',
                created_at  TEXT DEFAULT (datetime('now'))
            )
        """)

        # Новая таблица динамических планов приёма (блоков)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS plans (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id         INTEGER NOT NULL REFERENCES users(user_id),
                name            TEXT NOT NULL,
                start_date      TEXT, -- дата начала YYYY-MM-DD
                status          TEXT NOT NULL, -- 'active', 'completed', 'future'
                schedule_json   TEXT NOT NULL,
                created_at      TEXT DEFAULT (datetime('now')),
                updated_at      TEXT DEFAULT (datetime('now'))
            )
        """)

        # Новая таблица отметок приёма лекарств (общая для всех препаратов)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS plan_intakes (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                plan_id         INTEGER NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
                day_num         INTEGER NOT NULL,
                medication_id   TEXT NOT NULL, -- 'main' (Акнекутан) или id доп. лекарства
                status          TEXT NOT NULL, -- 'taken', 'skipped', 'auto_skipped', 'not_marked'; auto_skipped is system-only, not a factual mark
                dose_mg         INTEGER, -- доза в мг (для основного препарата)
                taken_at        TEXT DEFAULT (datetime('now')),
                UNIQUE(plan_id, medication_id, day_num)
            )
        """)

        # Таблица зрителей (врачей)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS viewers (
                user_id     INTEGER PRIMARY KEY,
                username    TEXT,
                first_name  TEXT,
                granted_by  INTEGER,
                granted_at  TEXT DEFAULT (datetime('now'))
            )
        """)

        # Лог напоминаний по планам
        await db.execute("""
            CREATE TABLE IF NOT EXISTS reminder_log (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id         INTEGER NOT NULL,
                plan_id         INTEGER NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
                day_num         INTEGER NOT NULL,
                medication_id   TEXT NOT NULL DEFAULT 'main',
                sent_at         TEXT DEFAULT (datetime('now')),
                reminder_date   TEXT NOT NULL
            )
        """)

        # Миграция колонок для reminder_log (добавление medication_id)
        cursor = await db.execute("PRAGMA table_info(reminder_log)")
        columns = [row[1] for row in await cursor.fetchall()]
        if columns and "medication_id" not in columns:
            await db.execute("ALTER TABLE reminder_log ADD COLUMN medication_id TEXT NOT NULL DEFAULT 'main'")

        # Пользовательские настройки уведомлений и бэкапов
        await db.execute("""
            CREATE TABLE IF NOT EXISTS user_settings (
                user_id             INTEGER PRIMARY KEY REFERENCES users(user_id),
                notify_start_hour   INTEGER NOT NULL DEFAULT 20,
                notify_end_hour     INTEGER NOT NULL DEFAULT 23,
                notify_end_minute   INTEGER NOT NULL DEFAULT 0,
                notify_interval_min INTEGER NOT NULL DEFAULT 30,
                auto_skip_hour      INTEGER NOT NULL DEFAULT 23,
                auto_skip_minute    INTEGER NOT NULL DEFAULT 59,
                backup_enabled      INTEGER NOT NULL DEFAULT 1,
                backup_hour         INTEGER NOT NULL DEFAULT 3,
                backup_minute       INTEGER NOT NULL DEFAULT 30,
                updated_at          TEXT DEFAULT (datetime('now'))
            )
        """)

        # Журнал действий
        await db.execute("""
            CREATE TABLE IF NOT EXISTS interaction_events (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id     INTEGER NOT NULL,
                plan_id     INTEGER,
                day_num     INTEGER,
                event_type  TEXT NOT NULL,
                source      TEXT,
                event_at    TEXT NOT NULL,
                metadata    TEXT
            )
        """)

        # Миграция колонок для interaction_events (cycle_id -> plan_id)
        cursor = await db.execute("PRAGMA table_info(interaction_events)")
        columns = [row[1] for row in await cursor.fetchall()]
        if columns and "cycle_id" in columns and "plan_id" not in columns:
            await db.execute("ALTER TABLE interaction_events RENAME COLUMN cycle_id TO plan_id")

        # Лог бэкапов
        await db.execute("""
            CREATE TABLE IF NOT EXISTS backup_log (
                backup_date TEXT PRIMARY KEY,
                sent_at     TEXT NOT NULL
            )
        """)

        # Выполняем миграцию старых данных, если необходимо
        await _migrate_old_data(db)

        await db.commit()


async def _migrate_old_data(db):
    """Миграция данных из старой БД (cycles, intakes, med_intakes) в plans и plan_intakes."""
    # Проверяем, есть ли старые таблицы в базе
    cursor = await db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cycles'")
    old_table_exists = await cursor.fetchone()
    if not old_table_exists:
        return

    # Проверяем, пуста ли таблица новых планов
    cursor = await db.execute("SELECT COUNT(*) FROM plans")
    new_plans_count = await cursor.fetchone()
    if new_plans_count and new_plans_count[0] > 0:
        return

    # Проверяем, есть ли старые циклы
    cursor = await db.execute("SELECT COUNT(*) FROM cycles")
    old_cycles_count = await cursor.fetchone()
    if not old_cycles_count or old_cycles_count[0] == 0:
        return

    print("Запуск миграции старой БД в новую динамическую структуру планов...")

    # Считываем старый цикл
    db.row_factory = aiosqlite.Row
    cursor = await db.execute("SELECT * FROM cycles WHERE finished=0 ORDER BY id DESC LIMIT 1")
    old_cycle = await cursor.fetchone()
    if not old_cycle:
        # Если нет активных, возьмём последний завершённый для миграции
        cursor = await db.execute("SELECT * FROM cycles ORDER BY id DESC LIMIT 1")
        old_cycle = await cursor.fetchone()

    if not old_cycle:
        return

    user_id = old_cycle["user_id"]
    start_date_str = old_cycle["start_date"] or "2026-05-17"
    start_date = date.fromisoformat(start_date_str)

    # 1. Формируем schedule_json для Блока 1 (дни 1-28)
    block1_main_sched = {}
    for d in range(1, 29):
        # Дни 1-14: чередование 8/16
        if d <= 14:
            dose = 8 if d % 2 != 0 else 16
        # Дни 15-21: 16
        elif d <= 21:
            dose = 16
        # Дни 22-28: чередование 16/24
        else:
            dose = 16 if d % 2 != 0 else 24
        block1_main_sched[str(d)] = {"dose_mg": dose}

    # Витамин E начался 11 июня 2026 г.
    # 11 июня — это 26-й день Блока 1 (17.05 + 25 дней)
    block1_vit_sched = {}
    for d in [26, 27, 28]:
        block1_vit_sched[str(d)] = {
            "active": 1,
            "notify_start_hour": 9,
            "notify_end_hour": 12,
            "notify_interval_min": 60
        }

    block1_json = json.dumps({
        "name": "Блок 1",
        "duration_days": 28,
        "medications": [
            {
                "id": "main",
                "title": "Акнекутан",
                "type": "main",
                "schedule": block1_main_sched
            },
            {
                "id": "vitamin_e",
                "title": "Витамин E",
                "type": "additional",
                "dose_text": "1 капсула",
                "schedule": block1_vit_sched
            }
        ]
    }, ensure_ascii=False)

    # 2. Формируем schedule_json для Блока 2 (дни 1-28)
    block2_main_sched = {}
    for d in range(1, 29):
        # Дни 1-7: 24
        if d <= 7:
            dose = 24
        # Дни 8-21: 32
        elif d <= 21:
            dose = 32
        # Дни 22-28: чередование 32/40
        else:
            dose = 32 if d % 2 != 0 else 40
        block2_main_sched[str(d)] = {"dose_mg": dose}

    # Витамин E в Блоке 2 активен с 1-го дня по 27-й день (завершение курса 30 дней)
    block2_vit_sched = {}
    for d in range(1, 28):
        block2_vit_sched[str(d)] = {
            "active": 1,
            "notify_start_hour": 9,
            "notify_end_hour": 12,
            "notify_interval_min": 60
        }

    block2_json = json.dumps({
        "name": "Блок 2",
        "duration_days": 28,
        "medications": [
            {
                "id": "main",
                "title": "Акнекутан",
                "type": "main",
                "schedule": block2_main_sched
            },
            {
                "id": "vitamin_e",
                "title": "Витамин E",
                "type": "additional",
                "dose_text": "1 капсула",
                "schedule": block2_vit_sched
            }
        ]
    }, ensure_ascii=False)

    # Создаём План 1 (Блок 1) - Завершённый
    cursor1 = await db.execute(
        """
        INSERT INTO plans (user_id, name, start_date, status, schedule_json, created_at)
        VALUES (?, ?, ?, 'completed', ?, ?)
        """,
        (user_id, "Блок 1", start_date_str, block1_json, old_cycle["created_at"])
    )
    plan1_id = cursor1.lastrowid

    # Создаём План 2 (Блок 2) - Активный
    block2_start_date = (start_date + timedelta(days=28)).isoformat()
    cursor2 = await db.execute(
        """
        INSERT INTO plans (user_id, name, start_date, status, schedule_json, created_at)
        VALUES (?, ?, ?, 'active', ?, ?)
        """,
        (user_id, "Блок 2", block2_start_date, block2_json, old_cycle["created_at"])
    )
    plan2_id = cursor2.lastrowid

    # Переносим отметки Акнекутана
    cursor = await db.execute("SELECT * FROM intakes WHERE cycle_id=?", (old_cycle["id"],))
    old_intakes = await cursor.fetchall()
    for row in old_intakes:
        day_num = row["day_num"]
        # Совместимость с NULL-дозами
        dose_mg = row["dose_mg"]
        if dose_mg is None:
            # Вычисляем по старому плану
            if day_num <= 14:
                dose_mg = 8 if day_num % 2 != 0 else 16
            elif day_num <= 21:
                dose_mg = 16
            elif day_num <= 28:
                dose_mg = 16 if day_num % 2 != 0 else 24
            elif day_num <= 35:
                dose_mg = 24
            elif day_num <= 49:
                dose_mg = 32
            else:
                dose_mg = 32 if day_num % 2 != 0 else 40

        if day_num <= 28:
            await db.execute(
                """
                INSERT INTO plan_intakes (plan_id, day_num, medication_id, status, dose_mg, taken_at)
                VALUES (?, ?, 'main', ?, ?, ?)
                """,
                (plan1_id, day_num, row["status"], dose_mg, row["taken_at"])
            )
        else:
            await db.execute(
                """
                INSERT INTO plan_intakes (plan_id, day_num, medication_id, status, dose_mg, taken_at)
                VALUES (?, ?, 'main', ?, ?, ?)
                """,
                (plan2_id, day_num - 28, row["status"], dose_mg, row["taken_at"])
            )

    # Переносим отметки Витамина Е
    cursor = await db.execute("SELECT * FROM med_intakes WHERE medication_id='vitamin_e'")
    old_med_intakes = await cursor.fetchall()
    for row in old_med_intakes:
        vit_day = row["day_num"]
        # Дата приёма Витамина Е: 11.06.2026 + (vit_day - 1)
        vit_date = date.fromisoformat("2026-06-11") + timedelta(days=vit_day - 1)
        
        # Определяем, в какой блок попадает дата
        if vit_date <= (start_date + timedelta(days=27)): # Блок 1
            days_diff = (vit_date - start_date).days + 1
            await db.execute(
                """
                INSERT OR IGNORE INTO plan_intakes (plan_id, day_num, medication_id, status, dose_mg, taken_at)
                VALUES (?, ?, 'vitamin_e', ?, NULL, ?)
                """,
                (plan1_id, days_diff, row["status"], row["taken_at"])
            )
        else: # Блок 2
            days_diff = (vit_date - date.fromisoformat(block2_start_date)).days + 1
            await db.execute(
                """
                INSERT OR IGNORE INTO plan_intakes (plan_id, day_num, medication_id, status, dose_mg, taken_at)
                VALUES (?, ?, 'vitamin_e', ?, NULL, ?)
                """,
                (plan2_id, days_diff, row["status"], row["taken_at"])
            )

    # Переименовываем старые таблицы, чтобы скрыть их и не мешать
    await db.execute("ALTER TABLE cycles RENAME TO archive_cycles")
    await db.execute("ALTER TABLE intakes RENAME TO archive_intakes")
    await db.execute("ALTER TABLE medications RENAME TO archive_medications")
    await db.execute("ALTER TABLE med_intakes RENAME TO archive_med_intakes")
    # Переименуем другие неиспользуемые старые таблицы, если они есть
    try:
        await db.execute("ALTER TABLE med_reminder_log RENAME TO archive_med_reminder_log")
        await db.execute("ALTER TABLE course_blocks RENAME TO archive_course_blocks")
        await db.execute("ALTER TABLE dose_schemes RENAME TO archive_dose_schemes")
    except Exception:
        pass

    print("Миграция данных успешно завершена!")


# ============ CRUD для users ============

async def get_or_create_user(user_id: int, username: str, first_name: str) -> dict:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM users WHERE user_id=?", (user_id,))
        row = await cursor.fetchone()
        if row:
            return dict(row)
        await db.execute(
            "INSERT INTO users (user_id, username, first_name) VALUES (?, ?, ?)",
            (user_id, username, first_name)
        )
        await db.commit()
        cursor = await db.execute("SELECT * FROM users WHERE user_id=?", (user_id,))
        row = await cursor.fetchone()
        return dict(row)


# ============ CRUD для plans ============

async def get_active_plan(user_id: int) -> dict | None:
    """Получить текущий активный план приёма."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM plans WHERE user_id=? AND status='active' ORDER BY id DESC LIMIT 1",
            (user_id,)
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

async def get_plan(plan_id: int) -> dict | None:
    """Получить конкретный план по ID."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM plans WHERE id=?", (plan_id,))
        row = await cursor.fetchone()
        return dict(row) if row else None

async def get_plans(user_id: int) -> list[dict]:
    """Получить список всех планов пользователя."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM plans WHERE user_id=? ORDER BY id ASC",
            (user_id,)
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]

async def create_plan(user_id: int, name: str, duration_days: int, schedule_json: str, status: str = 'future') -> int:
    """Создать новый план (по умолчанию будущий)."""
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute(
            """
            INSERT INTO plans (user_id, name, status, schedule_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (user_id, name, status, schedule_json, _now_iso(), _now_iso())
        )
        await db.commit()
        return cursor.lastrowid

async def activate_plan(plan_id: int, start_date_str: str):
    """Активировать план с заданной даты, переведя предыдущий активный в completed."""
    plan = await get_plan(plan_id)
    if not plan:
        return

    async with aiosqlite.connect(DB_PATH) as db:
        # 1. Завершить предыдущий активный план
        await db.execute(
            "UPDATE plans SET status='completed', updated_at=? WHERE user_id=? AND status='active'",
            (_now_iso(), plan["user_id"])
        )
        # 2. Активировать новый план
        await db.execute(
            "UPDATE plans SET status='active', start_date=?, updated_at=? WHERE id=?",
            (start_date_str, _now_iso(), plan_id)
        )
        await db.commit()

async def delete_plan(plan_id: int) -> bool:
    """Удалить план (только если его статус 'future' или 'draft')."""
    plan = await get_plan(plan_id)
    if not plan or plan["status"] not in ("future", "draft"):
        return False

    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("DELETE FROM plans WHERE id=?", (plan_id,))
        await db.commit()
    return True

async def update_plan_start_date(plan_id: int, start_date_str: str):
    """Изменить дату старта плана."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "UPDATE plans SET start_date=?, updated_at=? WHERE id=?",
            (start_date_str, _now_iso(), plan_id)
        )
        await db.commit()

async def update_plan_schedule(plan_id: int, schedule_json: str, name: str | None = None):
    """Обновить структуру schedule_json у существующего плана без отката от отметок."""
    async with aiosqlite.connect(DB_PATH) as db:
        if name:
            await db.execute(
                "UPDATE plans SET schedule_json=?, name=?, updated_at=? WHERE id=?",
                (schedule_json, name, _now_iso(), plan_id)
            )
        else:
            await db.execute(
                "UPDATE plans SET schedule_json=?, updated_at=? WHERE id=?",
                (schedule_json, _now_iso(), plan_id)
            )
        await db.commit()

async def save_draft_to_queue(plan_id: int):
    """Перевести черновик в статус будущего плана в очереди."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "UPDATE plans SET status='future', updated_at=? WHERE id=? AND status='draft'",
            (_now_iso(), plan_id)
        )
        await db.commit()

async def complete_plan(plan_id: int):
    """Принудительно перевести план в завершенные."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "UPDATE plans SET status='completed', updated_at=? WHERE id=?",
            (_now_iso(), plan_id)
        )
        await db.commit()

async def auto_complete_and_activate_next(plan_id: int, today_str: str) -> dict | None:
    """Завершить текущий план и автоматически активировать следующий будущий план, если он есть."""
    plan = await get_plan(plan_id)
    if not plan:
        return None

    async with aiosqlite.connect(DB_PATH) as db:
        # 1. Помечаем текущий как завершённый
        await db.execute(
            "UPDATE plans SET status='completed', updated_at=? WHERE id=?",
            (_now_iso(), plan_id)
        )
        
        # 2. Ищем первый будущий план для этого же пользователя
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM plans WHERE user_id=? AND status='future' ORDER BY id ASC LIMIT 1",
            (plan["user_id"],)
        )
        next_plan = await cursor.fetchone()
        
        if next_plan:
            next_plan_id = next_plan["id"]
            # 3. Активируем его с сегодняшнего дня
            await db.execute(
                "UPDATE plans SET status='active', start_date=?, updated_at=? WHERE id=?",
                (today_str, _now_iso(), next_plan_id)
            )
            await db.commit()
            
            # Возвращаем информацию о новом плане
            cursor = await db.execute("SELECT * FROM plans WHERE id=?", (next_plan_id,))
            updated_next = await cursor.fetchone()
            return dict(updated_next)
            
        await db.commit()
        return None

async def get_total_taken_dose_all_time(user_id: int) -> int:
    """Получить сумму всей принятой дозы основного препарата (Акнекутана) по всем блокам."""
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute(
            """
            SELECT SUM(dose_mg) 
            FROM plan_intakes 
            WHERE plan_id IN (SELECT id FROM plans WHERE user_id = ?) 
              AND status = 'taken' 
              AND medication_id = 'main'
            """,
            (user_id,)
        )
        row = await cursor.fetchone()
        return row[0] if row and row[0] is not None else 0

async def get_all_interaction_events(user_id: int) -> list[dict]:
    """Получить весь лог событий пользователя для экспорта."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM interaction_events WHERE user_id=? ORDER BY event_at DESC",
            (user_id,)
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]



# ============ CRUD для plan_intakes ============

async def get_plan_intake(plan_id: int, day_num: int, medication_id: str = 'main') -> dict | None:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM plan_intakes WHERE plan_id=? AND day_num=? AND medication_id=?",
            (plan_id, day_num, medication_id)
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

async def mark_plan_intake(plan_id: int, day_num: int, medication_id: str, status: str, dose_mg: int | None = None):
    """Отметить приём лекарства."""
    if dose_mg is None and medication_id == 'main':
        existing = await get_plan_intake(plan_id, day_num, medication_id)
        if existing and existing.get("dose_mg") is not None:
            dose_mg = existing["dose_mg"]
        else:
            # Подгружаем плановую дозу из схемы
            plan = await get_plan(plan_id)
            if plan:
                try:
                    sched = json.loads(plan["schedule_json"])
                    med = next((m for m in sched.get("medications", []) if m["id"] == 'main'), None)
                    if med:
                        day_sched = med.get("schedule", {}).get(str(day_num), {})
                        dose_mg = day_sched.get("dose_mg", 16)
                except Exception:
                    dose_mg = 16
            else:
                dose_mg = 16

    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            INSERT OR REPLACE INTO plan_intakes (plan_id, day_num, medication_id, status, dose_mg, taken_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (plan_id, day_num, medication_id, status, dose_mg, _now_iso())
        )
        await db.commit()

async def delete_plan_intake(plan_id: int, day_num: int, medication_id: str):
    """Удалить/очистить отметку приёма."""
    existing = await get_plan_intake(plan_id, day_num, medication_id)
    if not existing:
        return

    async with aiosqlite.connect(DB_PATH) as db:
        if medication_id == 'main' and existing.get("dose_mg") is not None:
            # Оставляем запись со статусом not_marked для сохранения дозы
            await db.execute(
                "UPDATE plan_intakes SET status='not_marked', taken_at=? WHERE plan_id=? AND day_num=? AND medication_id=?",
                (_now_iso(), plan_id, day_num, medication_id)
            )
        else:
            await db.execute(
                "DELETE FROM plan_intakes WHERE plan_id=? AND day_num=? AND medication_id=?",
                (plan_id, day_num, medication_id)
            )
        await db.commit()

async def update_plan_intake_dose(plan_id: int, day_num: int, medication_id: str, dose_mg: int):
    """Изменить дозу препарата за конкретный день (даже если день ещё не отмечен)."""
    intake = await get_plan_intake(plan_id, day_num, medication_id)

    async with aiosqlite.connect(DB_PATH) as db:
        if intake:
            await db.execute(
                "UPDATE plan_intakes SET dose_mg=? WHERE plan_id=? AND day_num=? AND medication_id=?",
                (dose_mg, plan_id, day_num, medication_id)
            )
        else:
            await db.execute(
                """
                INSERT INTO plan_intakes (plan_id, day_num, medication_id, status, dose_mg, taken_at)
                VALUES (?, ?, ?, 'not_marked', ?, ?)
                """,
                (plan_id, day_num, medication_id, dose_mg, _now_iso())
            )
        await db.commit()

async def list_plan_intakes(plan_id: int) -> list[dict]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM plan_intakes WHERE plan_id=? ORDER BY day_num, medication_id",
            (plan_id,)
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]

async def get_plan_stats(plan_id: int) -> dict:
    """Вычислить детальную статистику по конкретному плану."""
    plan = await get_plan(plan_id)
    if not plan:
        return {"taken": 0, "skipped": 0, "auto_skipped": 0, "total_mg": 0}

    try:
        sched = json.loads(plan["schedule_json"])
        duration = int(sched.get("duration_days", 28))
    except Exception:
        duration = 28

    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT status, COUNT(*) as cnt FROM plan_intakes WHERE plan_id=? AND medication_id='main' GROUP BY status",
            (plan_id,)
        )
        rows = await cursor.fetchall()

        taken = 0
        skipped = 0
        auto_skipped = 0
        for row in rows:
            if row["status"] == "taken":
                taken = row["cnt"]
            elif row["status"] == "skipped":
                skipped = row["cnt"]
            elif row["status"] == "auto_skipped":
                auto_skipped = row["cnt"]

        # Подсчёт принятых мг
        cursor = await db.execute(
            "SELECT dose_mg FROM plan_intakes WHERE plan_id=? AND medication_id='main' AND status='taken'",
            (plan_id,)
        )
        taken_rows = await cursor.fetchall()
        total_mg = sum(row["dose_mg"] or 0 for row in taken_rows)

        return {
            "taken": taken,
            "skipped": skipped,
            "auto_skipped": auto_skipped,
            "total_mg": total_mg,
            "duration": duration,
        }


# ============ Настройки пользователя ============

def default_settings(user_id: int) -> dict:
    return {
        "user_id": user_id,
        "notify_start_hour": 20,
        "notify_end_hour": 23,
        "notify_end_minute": 0,
        "notify_interval_min": 30,
        "auto_skip_hour": 23,
        "auto_skip_minute": 59,
        "backup_enabled": 1,
        "backup_hour": 3,
        "backup_minute": 30,
    }

async def get_user_settings(user_id: int) -> dict:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM user_settings WHERE user_id=?", (user_id,))
        row = await cursor.fetchone()
        if row:
            return dict(row)

        settings = default_settings(user_id)
        await db.execute(
            """
            INSERT INTO user_settings (
                user_id, notify_start_hour, notify_end_hour, notify_end_minute, notify_interval_min,
                auto_skip_hour, auto_skip_minute, backup_enabled, backup_hour, backup_minute
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id, settings["notify_start_hour"], settings["notify_end_hour"], settings["notify_end_minute"],
                settings["notify_interval_min"], settings["auto_skip_hour"], settings["auto_skip_minute"],
                settings["backup_enabled"], settings["backup_hour"], settings["backup_minute"]
            )
        )
        await db.commit()
        return settings

async def update_user_settings(user_id: int, **values):
    if not values:
        return

    await get_user_settings(user_id)
    allowed = {
        "notify_start_hour", "notify_end_hour", "notify_end_minute", "notify_interval_min",
        "auto_skip_hour", "auto_skip_minute", "backup_enabled", "backup_hour", "backup_minute"
    }
    updates = {key: value for key, value in values.items() if key in allowed}
    if not updates:
        return

    set_clause = ", ".join(f"{key}=?" for key in updates)
    params = list(updates.values()) + [user_id]
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(f"UPDATE user_settings SET {set_clause} WHERE user_id=?", params)
        await db.commit()


# ============ Журнал действий ============

async def log_event(
    user_id: int,
    event_type: str,
    plan_id: int | None = None,
    day_num: int | None = None,
    source: str | None = None,
    metadata: dict | None = None,
):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            INSERT INTO interaction_events (
                user_id, plan_id, day_num, event_type, source, event_at, metadata
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id, plan_id, day_num, event_type, source, _now_iso(),
                json.dumps(metadata or {}, ensure_ascii=False)
            )
        )
        await db.commit()


# ============ Бэкапы ============

async def backup_sent_today(date_str: str) -> bool:
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute("SELECT 1 FROM backup_log WHERE backup_date=?", (date_str,))
        row = await cursor.fetchone()
        return row is not None

async def log_backup_sent(date_str: str):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("INSERT OR REPLACE INTO backup_log (backup_date, sent_at) VALUES (?, ?)", (date_str, _now_iso()))
        await db.commit()


# ============ CRUD для reminder_log ============

async def count_reminders_today(user_id: int, date_str: str, medication_id: str = 'main') -> int:
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute(
            "SELECT COUNT(*) FROM reminder_log WHERE user_id=? AND reminder_date=? AND medication_id=?",
            (user_id, date_str, medication_id)
        )
        row = await cursor.fetchone()
        return row[0] if row else 0

async def log_reminder(user_id: int, plan_id: int, day_num: int, date_str: str, medication_id: str = 'main'):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            INSERT INTO reminder_log (user_id, plan_id, day_num, medication_id, reminder_date)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, plan_id, day_num, medication_id, date_str)
        )
        await db.commit()


# ============ CRUD для viewers ============

async def add_viewer(user_id: int, username: str | None, first_name: str | None):
    from bot.config import ADMIN_ID
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "INSERT OR REPLACE INTO viewers (user_id, username, first_name, granted_by) VALUES (?, ?, ?, ?)",
            (user_id, username, first_name, ADMIN_ID)
        )
        await db.commit()

async def remove_viewer(user_id: int):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("DELETE FROM viewers WHERE user_id=?", (user_id,))
        await db.commit()

async def is_viewer(user_id: int) -> bool:
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute("SELECT 1 FROM viewers WHERE user_id=?", (user_id,))
        row = await cursor.fetchone()
        return row is not None

async def list_viewers() -> list[dict]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM viewers ORDER BY granted_at")
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]

async def get_today_meds_status(plan: dict, day_num: int) -> list[dict]:
    """Сформировать статус всех лекарств на сегодня (для клавиатур и текстов)."""
    from bot.doses import get_plan_dose_info, get_plan_medications_for_day
    meds_status = []
    
    # 1. Основное лекарство (Акнекутан)
    main_intake = await get_plan_intake(plan["id"], day_num, "main")
    dose_info = get_plan_dose_info(plan, day_num)
    meds_status.append({
        "id": "main",
        "title": "Акнекутан",
        "dose_mg": main_intake["dose_mg"] if main_intake and main_intake.get("dose_mg") is not None else dose_info["dose"],
        "taken": bool(main_intake and main_intake["status"] in {"taken", "skipped"}),
        "status": main_intake["status"] if main_intake else "not_marked"
    })
    
    # 2. Дополнительные лекарства, назначенные на сегодня
    meds = get_plan_medications_for_day(plan, day_num)
    for med in meds:
        intake = await get_plan_intake(plan["id"], day_num, med["id"])
        meds_status.append({
            "id": med["id"],
            "title": med["title"],
            "dose_text": med["dose_text"],
            "taken": bool(intake and intake["status"] in {"taken", "skipped"}),
            "status": intake["status"] if intake else "not_marked"
        })
        
    return meds_status
