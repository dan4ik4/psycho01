import 'package:flutter_test/flutter_test.dart';
import 'package:god_save_this_shit_app/features/specialists/data/specialists_repository.dart';

void main() {
  group('Specialist.fromJson', () {
    test('reads a per-session USD price in minor units', () {
      final specialist = Specialist.fromJson({
        'id': 'psychologist-id',
        'first_name': 'Анна',
        'last_name': 'Иванова',
        'session_price_minor': 1250,
        'currency': 'USD',
        'average_rating': 4.5,
      });

      expect(specialist.name, 'Анна Иванова');
      expect(specialist.priceUsdPerSession, 12.5);
      expect(specialist.price, '\$12.50 / сеанс');
      expect(specialist.rating, 4.5);
    });

    test('does not mistake an hourly legacy amount for USD per session', () {
      final specialist = Specialist.fromJson({
        'id': 'psychologist-id',
        'hourly_net_minor': 5000,
      });

      expect(specialist.priceUsdPerSession, isNull);
      expect(specialist.price, '—');
    });

    test('does not show a minor-unit price unless the server says USD', () {
      final specialist = Specialist.fromJson({
        'id': 'psychologist-id',
        'session_price_minor': 1250,
        'currency': 'RUB',
      });

      expect(specialist.priceUsdPerSession, isNull);
      expect(specialist.price, '—');
    });

    test('reads an explicit decimal USD price', () {
      final specialist = Specialist.fromJson({
        'id': 'psychologist-id',
        'session_price_usd': 37.5,
      });

      expect(specialist.priceUsdPerSession, 37.5);
      expect(specialist.price, '\$37.50 / сеанс');
    });
  });
}
