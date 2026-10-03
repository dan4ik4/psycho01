import '../../../core/api/api_client.dart';

class Specialist {
  final String id;
  final String name;
  final String spec;
  final String bio;
  final String price;
  final String image;
  final double rating;
  final List<String> categories;

  Specialist({
    required this.id,
    required this.name,
    required this.spec,
    required this.bio,
    required this.price,
    required this.image,
    required this.rating,
    required this.categories,
  });

  factory Specialist.fromJson(Map<String, dynamic> json) {
    return Specialist(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? json['full_name'] ?? 'Специалист',
      spec: json['spec'] ?? json['specialization'] ?? 'Психолог',
      bio: json['bio'] ?? '',
      price: json['price']?.toString() ?? '0',
      image: json['image'] ?? json['avatar_url'] ?? 'https://i.pravatar.cc/150',
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      categories: (json['categories'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
          ['Все'],
    );
  }
}

class SpecialistRepository {
  final ApiClient _apiClient;

  // Исправлено: требуем ApiClient извне, не создаем его по умолчанию без параметров
  SpecialistRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<List<Specialist>> fetchSpecialists() async {
    try {
      // Исправлено: обращаемся к .dio.get()
      final response = await _apiClient.dio.get('/specialists');
      if (response.data is List) {
        return (response.data as List)
            .map((json) => Specialist.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return [
      Specialist(
        id: "1",
        name: "Елена Маркова",
        spec: "Гештальт-терапевт",
        bio: "Специализируюсь на вопросах самооценки и выгорания.",
        price: "85",
        image: "https://i.pravatar.cc/150?img=32",
        rating: 4.9,
        categories: ["Все", "Выгорание"],
      ),
    ];
  }

  Future<bool> createSpecialistProfile(Map<String, dynamic> specialistData) async {
    try {
      // Исправлено: обращаемся к .dio.post()
      final response = await _apiClient.dio.post('/specialists', data: specialistData);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}