import 'package:flutter/material.dart';

/// Validation and formatting for a psychologist's one-time calendar slot.
class OneOffSlotInterval {
  static const int minimumDurationMinutes = 15;

  static String validateAndFormat({
    required DateTime date,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required DateTime now,
    Iterable<String> existingIntervals = const [],
  }) {
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;

    if (endMinutes <= startMinutes) {
      throw const FormatException(
        'Время окончания должно быть позже времени начала в тот же день.',
      );
    }
    if (endMinutes - startMinutes < minimumDurationMinutes) {
      throw const FormatException('Слот должен длиться не менее 15 минут.');
    }

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );
    if (!start.isAfter(now)) {
      throw const FormatException('Начало слота должно быть в будущем.');
    }

    for (final interval in existingIntervals) {
      final existing = _parseInterval(interval);
      if (existing == null) continue;
      final overlaps = startMinutes < existing.$2 && endMinutes > existing.$1;
      if (overlaps) {
        throw const FormatException('Это время пересекается с другим слотом.');
      }
    }

    return '${_formatTime(startTime)} - ${_formatTime(endTime)}';
  }

  static (int, int)? _parseInterval(String value) {
    final parts = value.split(' - ');
    if (parts.length != 2) return null;
    final start = _parseTime(parts[0]);
    final end = _parseTime(parts[1]);
    if (start == null || end == null || end <= start) return null;
    return (start, end);
  }

  static int? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
