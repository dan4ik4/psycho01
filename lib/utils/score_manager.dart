import 'package:shared_preferences/shared_preferences.dart';

/// Менеджер очков с системой множителей за ежедневную активность.
///
/// Принцип работы:
/// - За каждый день, когда пользователь получает очки, фиксируется дата.
/// - Если между днями нет пропусков, серия продолжается.
/// - Каждые 5 дней множитель увеличивается на +1.
/// - Если пропущен хотя бы 1 день — серия и множитель сбрасываются.
/// - Очки начисляются с учётом текущего множителя.
///
/// Пример:
///   День 1–5 → множитель 1 (по 1 очку)
///   День 6–10 → множитель 2 (по 2 очка)
///   День 11–15 → множитель 3 (по 3 очка)
///   и т.д.
class ScoreManager {
  static const _keyScore = 'total_score';
  static const _keyLastDate = 'last_score_date';
  static const _keyStreak = 'streak_count';

  /// Возвращает общее количество очков.
  static Future<int> getScore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyScore) ?? 0;
  }

  /// Возвращает текущую серию подряд идущих дней.
  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyStreak) ?? 0;
  }

  /// Возвращает текущий множитель (на основе серии).
  static Future<int> getMultiplier() async {
    final streak = await getStreak();
    return (streak ~/ 5) + 1;
  }

  /// Добавляет очки с учётом множителя и обновляет серию.
  static Future<void> addPoints(int basePoints) async {
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final lastDateStr = prefs.getString(_keyLastDate);
    DateTime? lastDate;
    if (lastDateStr != null) {
      try {
        lastDate = DateTime.parse(lastDateStr);
      } catch (_) {}
    }

    int streak = prefs.getInt(_keyStreak) ?? 0;

    // Проверка серии: продолжается или сбрасывается
    if (lastDate != null) {
      final diff = today.difference(lastDate).inDays;
      if (diff == 1) {
        // серия продолжается
        streak += 1;
      } else if (diff > 1) {
        // пропущен день — сбрасываем
        streak = 1;
      }
    } else {
      streak = 1;
    }

    // сохраняем дату
    await prefs.setString(_keyLastDate, today.toIso8601String());
    await prefs.setInt(_keyStreak, streak);

    // вычисляем множитель
    final multiplier = (streak ~/ 5) + 1;
    final total = prefs.getInt(_keyScore) ?? 0;

    final earned = basePoints * multiplier;
    await prefs.setInt(_keyScore, total + earned);
  }

  /// Сбрасывает всё (для отладки или выхода из аккаунта).
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyScore);
    await prefs.remove(_keyLastDate);
    await prefs.remove(_keyStreak);
  }
}
