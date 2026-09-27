import SwiftUI

/// Единый набор токенов анимаций (MED_APP_SPEC.md §12).
/// Правило: никакой ad-hoc анимации внутри экранов — только токены отсюда.
/// Вторая копия анимации в экране = вынести сюда новым токеном.
public enum Motion {
    /// Нажатие кнопок и контролов.
    public static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
    /// Смена статуса отметки (принял/пропустил/сброс).
    public static let statusChange = Animation.spring(response: 0.45, dampingFraction: 0.8)
    /// Прогресс (кольцо, полоса).
    public static let progress = Animation.spring(response: 0.5, dampingFraction: 0.75)
    /// Празднование (уровень streak, цель достигнута) — на этапе 5.
    public static let celebrate = Animation.spring(response: 0.6, dampingFraction: 0.55)
    /// Фоновое свечение — медленное, бесконечное.
    public static let ambient = Animation.easeInOut(duration: 8.0).repeatForever(autoreverses: true)
}
