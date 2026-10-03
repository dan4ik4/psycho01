/// Конвертация даты и времени для взаимодействия с API[cite: 8]

String toApiUtc(DateTime value) => value.toUtc().toIso8601String();

DateTime fromApiInstant(Object? value) {
  if (value is! String) throw const FormatException('Expected ISO datetime string');
  return DateTime.parse(value).toUtc();
}

String encodeDateOnly(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}';
}

DateTime? decodeDateOnly(Object? value) {
  if (value == null) return null;
  final parts = (value as String).split('-');
  if (parts.length != 3) throw const FormatException('Expected YYYY-MM-DD');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}