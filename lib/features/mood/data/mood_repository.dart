import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/api_date.dart';
import 'models/mood_entry_model.dart';

class MoodRepository {
  final ApiClient _apiClient;

  MoodRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Загрузка от меток настроения за выбранный месяц
  Future<List<MoodEntryModel>> getMonthlyMoods(DateTime month) async {
    try {
      final formattedDate = ApiDate.toDateOnlyString(month);
      final response = await _apiClient.dio.get(
        '/mood/month',
        queryParameters: {'date': formattedDate},
      );

      final List data = response.data ?? [];
      return data.map((json) => MoodEntryModel.fromJson(json)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e); // Исправлено: fromDio
    }
  }

  /// Создание или обновление записи настроения/дневника
  Future<MoodEntryModel> saveMoodEntry({
    required int score,
    String? note,
    List<String> tags = const [],
    required DateTime date,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/mood',
        data: {
          'score': score,
          'note': note,
          'tags': tags,
          'date': ApiDate.toApiString(date),
        },
      );
      return MoodEntryModel.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e); // Исправлено: fromDio
    }
  }
}