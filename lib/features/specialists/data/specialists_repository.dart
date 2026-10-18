import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

class Specialist {
  final String id;
  final String name;
  final String spec;
  final String bio;
  final String price;
  final double? priceRub;
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
    this.priceRub,
    this.experienceYears,
    required this.image,
    required this.rating,
    required this.categories,
  });

  factory Specialist.fromJson(Map<String, dynamic> json) {
    final rawMinorPrice = json['hourly_net_minor'];
    final rawPrice =
        json['price_rub'] ?? json['hourly_price_rub'] ?? json['price'];
    final parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '');
    final rawExperience = json['experience_years'] ?? json['experience'];
    final priceRub =
        parsedPrice ??
        (rawMinorPrice is num ? rawMinorPrice.toDouble() / 100 : null);
    return Specialist(
      id: json['id']?.toString() ?? '',
      name: [json['first_name'], json['last_name']]
          .where((part) => part != null && part.toString().trim().isNotEmpty)
          .join(' '),
      spec: json['specialization']?.toString() ?? 'Психолог',
      bio: json['bio'] ?? '',
      price: priceRub == null ? '—' : '${priceRub.toStringAsFixed(0)} ₽',
      priceRub: priceRub,
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
