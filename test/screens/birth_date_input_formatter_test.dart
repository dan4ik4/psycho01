import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:god_save_this_shit_app/screens/auth_screen.dart';

void main() {
  group('BirthDateInputFormatter', () {
    final formatter = BirthDateInputFormatter();

    test('inserts dots while typing eight digits', () {
      final formatted = formatter.formatEditUpdate(
        const TextEditingValue(),
        const TextEditingValue(text: '01022000'),
      );

      expect(formatted.text, '01.02.2000');
      expect(formatted.selection.extentOffset, formatted.text.length);
    });

    test('accepts pasted date with separators', () {
      final formatted = formatter.formatEditUpdate(
        const TextEditingValue(),
        const TextEditingValue(text: '01.02.2000'),
      );

      expect(formatted.text, '01.02.2000');
    });
  });
}
