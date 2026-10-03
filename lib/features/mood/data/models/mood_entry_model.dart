import '../../../../core/utils/api_date.dart';

class MoodEntryModel {
  final String? id;
  final int score;
  final String? note;
  final List<String> tags;
  final DateTime date;

  MoodEntryModel({
    this.id,
    required this.score,
    this.note,
    this.tags = const [],
    required this.date,
  });

  factory MoodEntryModel.fromJson(Map<String, dynamic> json) {
    return MoodEntryModel(
      id: json['id']?.toString(),
      score: json['score'] ?? json['mood_level'] ?? 3,
      note: json['note'] ?? json['comment'],
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      date: ApiDate.parseApiDate(json['created_at'] ?? json['date']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'score': score,
      if (note != null) 'note': note,
      'tags': tags,
      'date': ApiDate.toApiString(date),
    };
  }
}