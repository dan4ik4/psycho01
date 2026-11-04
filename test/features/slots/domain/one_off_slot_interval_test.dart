import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:god_save_this_shit_app/features/slots/domain/one_off_slot_interval.dart';

void main() {
  final date = DateTime(2026, 11, 5);
  final now = DateTime(2026, 11, 5, 8);

  group('OneOffSlotInterval.validateAndFormat', () {
    test('formats a future slot with a zero-padded time', () {
      final interval = OneOffSlotInterval.validateAndFormat(
        date: date,
        startTime: const TimeOfDay(hour: 9, minute: 5),
        endTime: const TimeOfDay(hour: 10, minute: 5),
        now: now,
      );

      expect(interval, '09:05 - 10:05');
    });

    test('accepts the server minimum duration of 15 minutes', () {
      final interval = OneOffSlotInterval.validateAndFormat(
        date: date,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 9, minute: 15),
        now: now,
      );

      expect(interval, '09:00 - 09:15');
    });

    test('rejects a duration shorter than 15 minutes', () {
      expect(
        () => OneOffSlotInterval.validateAndFormat(
          date: date,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 14),
          now: now,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an end time that is not later than the start', () {
      expect(
        () => OneOffSlotInterval.validateAndFormat(
          date: date,
          startTime: const TimeOfDay(hour: 10, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
          now: now,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a start time in the past', () {
      expect(
        () => OneOffSlotInterval.validateAndFormat(
          date: date,
          startTime: const TimeOfDay(hour: 7, minute: 0),
          endTime: const TimeOfDay(hour: 8, minute: 0),
          now: now,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects overlapping slots', () {
      expect(
        () => OneOffSlotInterval.validateAndFormat(
          date: date,
          startTime: const TimeOfDay(hour: 9, minute: 30),
          endTime: const TimeOfDay(hour: 10, minute: 30),
          now: now,
          existingIntervals: const ['09:00 - 10:00'],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('allows adjacent slots without treating them as overlapping', () {
      final interval = OneOffSlotInterval.validateAndFormat(
        date: date,
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
        now: now,
        existingIntervals: const ['09:00 - 10:00'],
      );

      expect(interval, '10:00 - 11:00');
    });
  });
}
