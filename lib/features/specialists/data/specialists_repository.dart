import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

class Specialist {
  final String id;
  final String name;
  final String spec;
  final String bio;
  final String price;
  final double? priceUsdPerSession;
  final int? experienceYears;
  final String image;
  final double rating;
  final List<String> categories;

  Specialist({
    required this.id,
    required this.name,
    required this.spec,
    required this.bio,
    required this.price,
    this.priceUsdPerSession,
    this.experienceYears,
    required this.image,
    required this.rating,
    required this.categories,
  });

  factory Specialist.fromJson(Map<String, dynamic> json) {
    final currency = (json['currency'] ?? json['session_price_currency'])
        ?.toString()
        .toUpperCase();
    final rawMinorPrice = currency == 'USD'
        ? json['session_price_minor']
        : null;
    final rawUsdPrice = json['session_price_usd'] ?? json['price_usd'];
    final usdPrice = rawUsdPrice is num
        ? rawUsdPrice.toDouble()
        : double.tryParse(rawUsdPrice?.toString() ?? '');
    final rawExperience = json['experience_years'] ?? json['experience'];
    final priceUsdPerSession =
        usdPrice ??
        (rawMinorPrice is num ? rawMinorPrice.toDouble() / 100 : null);
    return Specialist(
      id: json['id']?.toString() ?? '',
      name: [json['first_name'], json['last_name']]
          .where((part) => part != null && part.toString().trim().isNotEmpty)
          .join(' '),
      spec: json['specialization']?.toString() ?? 'Психолог',
      bio: json['bio'] ?? '',
      price: priceUsdPerSession == null
          ? '—'
          : '\$${priceUsdPerSession.toStringAsFixed(2)} / сеанс',
      priceUsdPerSession: priceUsdPerSession,
      experienceYears: rawExperience is num
          ? rawExperience.toInt()
          : int.tryParse(rawExperience?.toString() ?? ''),
      image:
          (json['photo_url'] ?? json['avatar_url'] ?? json['image_url'] ?? '')
              .toString(),
      rating: (json['average_rating'] as num?)?.toDouble() ?? 0,
      categories: const ['Все'],
    );
  }
}

class SpecialistRepository {
  final ApiClient _apiClient;

  // Исправлено: требуем ApiClient извне, не создаем его по умолчанию без параметров
  SpecialistRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<Specialist>> fetchSpecialists() async {
    return apiGuard(() async {
      final response = await _apiClient.dio.get('/psychologists');
      final data = response.data;
      if (data is! List)
        throw const FormatException('Ожидался список психологов от API');
      return data
          .map(
            (item) =>
                Specialist.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    });
  }
}
