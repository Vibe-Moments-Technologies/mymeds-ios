"""Эталон резолва дня. Семантика для Swift-порта; не продуктовый код."""
from dataclasses import dataclass
from datetime import date

@dataclass
class Plan:
    id: str
    medication_id: str
    start: date | None      # None = не начат
    duration: int
    schedule: dict[int, float]   # day -> dose; 0 или отсутствие = день без приёма
    stopped_at: date | None = None

@dataclass
class Entry:
    plan_id: str
    medication_id: str
    day: int
    dose: float
    on: date

def entries(plans: list[Plan], on: date) -> list[Entry]:
    """Все элементы приёма, назначенные на календарную дату `on`."""
    out: list[Entry] = []
    for p in plans:
        if p.start is None:
            continue
        if p.stopped_at is not None and on > p.stopped_at:
            continue                       # stoppedAt включительно
        n = (on - p.start).days + 1
        if n < 1 or n > p.duration:
            continue
        dose = p.schedule.get(n, 0)
        if dose <= 0:
            continue                       # день без приёма
        out.append(Entry(p.id, p.medication_id, n, dose, on))
    return out


def _ids(es: list[Entry]) -> set[str]:
    return {e.plan_id for e in es}


def _selftest() -> None:
    akn = Plan("p1", "akn", date(2026, 5, 17), 28,
               {d: (8 if d % 2 else 16) for d in range(1, 29)})
    vitd = Plan("p2", "vitd", date(2026, 6, 1), 90, {d: 2000 for d in range(1, 91)})
    stopped = Plan("p3", "ab", date(2026, 5, 1), 30, {d: 1 for d in range(1, 31)},
                   stopped_at=date(2026, 5, 10))
    draft = Plan("p4", "x", None, 10, {d: 1 for d in range(1, 11)})
    gap = Plan("p5", "y", date(2026, 5, 1), 10, {**{d: 5 for d in range(1, 11)}, 2: 0})
    ps = [akn, vitd, stopped, draft, gap]

    # 1. Разные даты старта склеиваются по календарной дате, а не по day_num.
    got = {(e.plan_id, e.day) for e in entries(ps, date(2026, 6, 1))}
    assert got == {("p1", 16), ("p2", 1)}, got

    # 2. До старта второго плана в агрегации только первый.
    day = entries(ps, date(2026, 5, 31))
    assert _ids(day) == {"p1"}, _ids(day)
    assert {e.day for e in day} == {15}

    # 3. Черновой план не появляется никогда.
    for d in (date(2026, 5, 5), date(2026, 6, 1), date(2026, 12, 1)):
        assert "p4" not in _ids(entries(ps, d)), d

    # 4. Остановленный план даёт элементы только до stoppedAt включительно.
    assert _ids(entries(ps, date(2026, 5, 10))) == {"p3", "p5"}
    assert _ids(entries(ps, date(2026, 5, 11))) == set()
    assert _ids(entries(ps, date(2026, 5, 20))) == {"p1"}

    # 5. День с нулевой дозой элемента не даёт; соседние дни дают.
    assert entries([gap], date(2026, 5, 2)) == []
    assert [e.dose for e in entries([gap], date(2026, 5, 1))] == [5]
    assert [e.dose for e in entries([gap], date(2026, 5, 3))] == [5]

    # 6. Границы диапазона плана.
    assert [e.day for e in entries([akn], date(2026, 5, 17))] == [1]
    assert [e.day for e in entries([akn], date(2026, 6, 13))] == [28]
    assert entries([akn], date(2026, 5, 16)) == []
    assert entries([akn], date(2026, 6, 14)) == []

    # 7. После завершения всех планов — пусто.
    assert entries(ps, date(2026, 12, 1)) == []

    # 8. Доза берётся из сетки дня, а не из дефолта.
    assert [e.dose for e in entries([akn], date(2026, 5, 17))] == [8]
    assert [e.dose for e in entries([akn], date(2026, 5, 18))] == [16]

    print("selftest OK")

if __name__ == "__main__":
    _selftest()

