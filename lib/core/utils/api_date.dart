class ApiDate {
  /// Конвертирует локальную дату/время в ISO 8601 UTC для отправки на бэкенд
  static String toApiString(DateTime date) {
    return date.toUtc().toIso8601String();
  }

  /// Парсит строку ISO 8601 от бэкенда и приводит ее к локальному времени устройства
  static DateTime parseApiDate(String dateStr) {
    return DateTime.parse(dateStr).toLocal();
  }

  /// Возвращает дату в формате YYYY-MM-DD (для эндпоинтов выборок календаря)
  static String toDateOnlyString(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}