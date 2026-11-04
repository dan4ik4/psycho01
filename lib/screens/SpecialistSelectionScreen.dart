import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/widgets/oakle_notice.dart';
import '../features/specialists/data/specialists_repository.dart'
    show Specialist, SpecialistRepository;
import '../features/slots/data/slots_repository.dart';

enum SortType { none, rating }

String _ratingFailureMessage(Object error) {
  final statusCode = error is DioException
      ? error.response?.statusCode
      : (error is ApiException ? error.statusCode : null);
  if (statusCode == 403) {
    return 'Сервер запретил отправить оценку. Попросите коллегу проверить права клиента на оценку психолога.';
  }
  return friendlyApiError(error);
}

const Color kDeepPurple = Color(0xFFB0A6E8);
const Color kAccentPurple = Color(0xFF7862D6);
const Color kWarmWhite = Color(0xFFF6F8FD);
const Color kTextPrimary = Color(0xFF323045);
const Color kTextSecondary = Color(0xFF706D8C);
const Color kWeekendRed = Color(0xFFFF8A80);

// ==========================================
// 3. Главный экран списка специалистов
// ==========================================
class SpecialistListScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Function(Map<String, dynamic>)? onBookingConfirmed;

  const SpecialistListScreen({
    super.key,
    required this.apiClient,
    this.onBookingConfirmed,
  });

  @override
  _SpecialistListScreenState createState() => _SpecialistListScreenState();
}

class _SpecialistListScreenState extends State<SpecialistListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final SpecialistRepository _repository = SpecialistRepository(
    apiClient: widget.apiClient,
  );

  String selectedCategory = "Все";
  SortType activeSort = SortType.none;
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final TextEditingController _minExperienceController =
      TextEditingController();
  List<Specialist> specialists = [];
  List<Specialist> filteredSpecialists = [];
  List<String> favoriteIds = [];
  SharedPreferences? _prefs;
  bool isLoading = true;
  String? _loadError;

  Map<String, dynamic>? myAssignment;

  List<String> get allCategories {
    final values =
        specialists
            .map((item) => item.spec.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['Все', '❤️ Избранные', ...values];
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _loadData();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();

    List<Specialist> loadedSpecialists;
    try {
      loadedSpecialists = await _repository.fetchSpecialists();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _loadError =
            'Не удалось загрузить специалистов. Проверьте подключение и попробуйте ещё раз.';
      });
      return;
    }

    Map<String, dynamic>? loadedAssignment;
    try {
      final assignmentResponse = await widget.apiClient.dio.get(
        '/patient-assignments/my',
      );
      final assignment = assignmentResponse.data;
      if (assignment is Map) {
        final data = Map<String, dynamic>.from(assignment);
        final event = Map<String, dynamic>.from(
          data['latest_event'] as Map? ?? const {},
        );
        Specialist? specialist;
        for (final item in loadedSpecialists) {
          if (item.id == data['psychologist_id']) specialist = item;
        }
        loadedAssignment = {
          'id': data['id'],
          'psychologistId': data['psychologist_id'],
          'psychologistName': specialist?.name ?? 'Психолог',
          'status':
              event['event_type']?.toString().toLowerCase() ?? 'requested',
          'requestComment': event['comment'] ?? '',
        };
      }
    } catch (_) {
      // Keep the directory usable if assignment status is temporarily unavailable.
    }

    if (!mounted) return;
    setState(() {
      specialists = loadedSpecialists;
      favoriteIds = _prefs?.getStringList('favorite_psychologists') ?? [];
      myAssignment = loadedAssignment;

      isLoading = false;
      _loadError = null;
      _applyFilters();
    });
  }

  Future<bool> _updateAssignmentStatus(
    String status, {
    String? commentField,
    String? commentValue,
    bool cancelOnServer = false,
  }) async {
    if (myAssignment != null) {
      if (cancelOnServer) {
        try {
          final id = myAssignment!['id']?.toString();
          if (id == null) throw StateError('Не найден номер заявки');
          final isActive = myAssignment!['status'] == 'accepted';
          await widget.apiClient.dio.post(
            '/patient-assignments/$id/${isActive ? 'finish' : 'cancel'}',
            data: {
              'comment': commentValue?.trim().isNotEmpty == true
                  ? commentValue!.trim()
                  : 'Заявка отменена клиентом',
            },
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyApiError(
                    error,
                    fallback:
                        'Не удалось обновить заявку. Обновите экран и попробуйте снова.',
                  ),
                ),
              ),
            );
          }
          return false;
        }
      }
      myAssignment!['status'] = status;
      if (commentField != null && commentValue != null) {
        myAssignment![commentField] = commentValue;
      }
      if (status == 'none') {
        await _prefs?.remove('client_assignment');
        myAssignment = null;
      } else {
        await _prefs?.setString('client_assignment', jsonEncode(myAssignment));
      }
      setState(() {
        _applyFilters();
      });
      return true;
    }
    return false;
  }

  Future<bool> _hasCompletedSession(String psychologistId) async {
    try {
      final response = await widget.apiClient.dio.get('/slots/history');
      final rows = response.data;
      if (rows is! List) return false;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final slot = Map<String, dynamic>.from(raw);
        if (slot['psychologist_id']?.toString() != psychologistId) continue;
        if (slot['event_type']?.toString() == 'completed') return true;
        final latest = slot['latest_event'];
        if (latest is Map && latest['event_type']?.toString() == 'completed') {
          return true;
        }
        final events = slot['events'];
        if (events is List &&
            events.any(
              (event) =>
                  event is Map &&
                  event['event_type']?.toString() == 'completed',
            ))
          return true;
      }
    } catch (_) {}
    return false;
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (favoriteIds.contains(id)) {
        favoriteIds.remove(id);
      } else {
        favoriteIds.add(id);
      }
      _prefs?.setStringList('favorite_psychologists', favoriteIds);
      _applyFilters();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minExperienceController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      String? activeSpecId;
      if (myAssignment != null &&
          (myAssignment!['status'] == 'requested' ||
              myAssignment!['status'] == 'accepted')) {
        activeSpecId = myAssignment!['psychologistId'];
      }

      filteredSpecialists = specialists.where((s) {
        if (s.id == activeSpecId) return false;

        final nameMatch = s.name.toLowerCase().contains(
          _searchController.text.toLowerCase(),
        );
        bool categoryMatch = (selectedCategory == "❤️ Избранные")
            ? favoriteIds.contains(s.id)
            : (selectedCategory == "Все" || s.spec.trim() == selectedCategory);

        final minPrice = double.tryParse(_minPriceController.text.trim());
        final maxPrice = double.tryParse(_maxPriceController.text.trim());
        if (minPrice != null &&
            (s.priceUsdPerSession == null ||
                s.priceUsdPerSession! < minPrice)) {
          return false;
        }
        if (maxPrice != null &&
            (s.priceUsdPerSession == null ||
                s.priceUsdPerSession! > maxPrice)) {
          return false;
        }
        final minExperience = int.tryParse(
          _minExperienceController.text.trim(),
        );
        if (minExperience != null &&
            (s.experienceYears == null || s.experienceYears! < minExperience)) {
          return false;
        }
        return nameMatch && categoryMatch;
      }).toList();

      if (activeSort == SortType.rating) {
        filteredSpecialists.sort((a, b) => b.rating.compareTo(a.rating));
      }
    });
  }

  void _resetFilters() {
    _searchController.removeListener(_applyFilters);
    _searchController.clear();
    _searchController.addListener(_applyFilters);
    setState(() {
      selectedCategory = "Все";
      activeSort = SortType.none;
      _minPriceController.clear();
      _maxPriceController.clear();
      _minExperienceController.clear();
    });
    _applyFilters();
  }

  void _showFilterSheet() {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: kDeepPurple,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: kWarmWhite.withOpacity(0.8),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 30,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          _resetFilters();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.refresh, color: kTextSecondary),
                        label: const Text(
                          "Сбросить",
                          style: TextStyle(color: kTextSecondary),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.check_circle,
                          color: kAccentPurple,
                          size: 35,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    "Сортировать",
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _sortChip(
                          "Рейтинг: сначала высокий",
                          SortType.rating,
                          setModalState,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'Цена за сеанс, USD',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (specialists.any(
                    (item) => item.priceUsdPerSession != null,
                  ))
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'От',
                              suffixText: '\$',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) {
                              setModalState(() {});
                              _applyFilters();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _maxPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'До',
                              suffixText: '\$',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) {
                              setModalState(() {});
                              _applyFilters();
                            },
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'Сервер пока не передаёт цены психологов. Фильтр заработает, когда цена появится в списке специалистов.',
                      style: TextStyle(color: kTextSecondary),
                    ),
                  const SizedBox(height: 25),
                  const Text(
                    'Опыт работы, лет',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _minExperienceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Минимальный опыт',
                      suffixText: 'лет',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      setModalState(() {});
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "Специализация",
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allCategories
                        .map(
                          (c) => ChoiceChip(
                            label: Text(
                              c,
                              style: TextStyle(
                                color: selectedCategory == c
                                    ? kWarmWhite
                                    : kTextPrimary,
                                fontWeight: selectedCategory == c
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: selectedCategory == c,
                            selectedColor: kAccentPurple,
                            backgroundColor: kAccentPurple.withOpacity(0.1),
                            onSelected: (v) {
                              setModalState(() => selectedCategory = c);
                              _applyFilters();
                            },
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, SortType type, StateSetter setModalState) {
    final isSelected = activeSort == type;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? kWarmWhite : kTextPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: kAccentPurple,
      backgroundColor: kAccentPurple.withOpacity(0.1),
      onSelected: (v) {
        setModalState(() => activeSort = v ? type : SortType.none);
        _applyFilters();
      },
    );
  }

  void _showRatingDialogForSpecialist(Specialist spec) {
    showDialog(
      context: context,
      builder: (context) {
        int selectedStars = spec.rating.round();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kWarmWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                "Оцените специалиста\n${spec.name}",
                style: const TextStyle(color: kTextPrimary),
                textAlign: TextAlign.center,
              ),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      index < selectedStars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 42,
                    ),
                    onPressed: () {
                      setDialogState(() => selectedStars = index + 1);
                    },
                  );
                }),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Пропустить",
                    style: TextStyle(color: kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await widget.apiClient.dio.put(
                        '/psychologists_rating/${spec.id}/rating',
                        data: {'rating': selectedStars},
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      await _loadData();
                      if (mounted)
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Спасибо за вашу оценку!'),
                          ),
                        );
                    } catch (error) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Не удалось отправить оценку. ${_ratingFailureMessage(error)}',
                            ),
                          ),
                        );
                    }
                  },
                  child: const Text(
                    "Оценить",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCancelOrFinishDialog(bool isCancel) async {
    TextEditingController commentCtrl = TextEditingController();

    final List<String> finishReplies = [
      "Терапия успешно завершена",
      "Цели терапии достигнуты",
      "Решил(а) приостановить работу",
      "Проблема решена, прогресс стабилен",
    ];

    final List<String> cancelReplies = [
      "Передумал(а)",
      "Выбрал(а) другого специалиста",
      "Не подходит время/цена",
    ];

    final currentReplies = isCancel ? cancelReplies : finishReplies;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Container(
            decoration: const BoxDecoration(
              color: kDeepPurple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: kWarmWhite.withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCancel ? "Отмена заявки" : "Завершение терапии",
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isCancel
                        ? "Укажите причину отмены:"
                        : "Оставьте финальный отзыв или комментарий:",
                    style: const TextStyle(color: kTextSecondary),
                  ),
                  const SizedBox(height: 15),

                  Wrap(
                    spacing: 8.0,
                    runSpacing: 10.0,
                    children: currentReplies
                        .map(
                          (reply) => GestureDetector(
                            onTap: () {
                              commentCtrl.text = reply;
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isCancel
                                    ? kWeekendRed.withOpacity(0.1)
                                    : kAccentPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCancel
                                      ? kWeekendRed.withOpacity(0.3)
                                      : kAccentPurple.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                reply,
                                style: TextStyle(
                                  color: isCancel ? kWeekendRed : kAccentPurple,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: kTextPrimary),
                    decoration: InputDecoration(
                      hintText: "Напишите здесь или выберите вариант выше...",
                      filled: true,
                      fillColor: kDeepPurple.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCancel ? kWeekendRed : kAccentPurple,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () async {
                        if (isCancel) {
                          final updated = await _updateAssignmentStatus(
                            'none',
                            cancelOnServer: true,
                            commentValue: 'Клиент отменил заявку',
                          );
                          if (updated && ctx.mounted) Navigator.pop(ctx);
                        } else {
                          String? specId = myAssignment?['psychologistId'];
                          Specialist? specToRate;
                          if (specId != null) {
                            try {
                              specToRate = specialists.firstWhere(
                                (s) => s.id == specId,
                              );
                            } catch (_) {}
                          }

                          final updated = await _updateAssignmentStatus(
                            'none',
                            cancelOnServer: true,
                            commentValue: 'Клиент завершил работу',
                          );
                          if (!updated) return;
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (specToRate != null &&
                              await _hasCompletedSession(specToRate.id)) {
                            _showRatingDialogForSpecialist(specToRate);
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Оценка появится после завершённого сеанса',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: Text(
                        isCancel ? "Отменить заявку" : "Завершить работу",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedDoctorCard() {
    if (myAssignment == null) return const SizedBox.shrink();

    String status = myAssignment!['status'];

    if (status == 'rejected' || status == 'finished') {
      IconData icon = status == 'rejected'
          ? Icons.cancel_outlined
          : Icons.flag_circle_outlined;
      String title = status == 'rejected'
          ? "Заявка отклонена"
          : "Работа завершена";
      String sub = status == 'rejected'
          ? "Причина: ${myAssignment!['rejectComment'] ?? 'Нет мест'}"
          : "Психолог завершил терапию.";

      return Container(
        margin: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kWarmWhite.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccentPurple.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: kAccentPurple, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _updateAssignmentStatus('none'),
              child: const Text("Ок", style: TextStyle(color: kTextPrimary)),
            ),
          ],
        ),
      );
    }

    String specId = myAssignment!['psychologistId'];
    Specialist? doc;
    try {
      doc = specialists.firstWhere((s) => s.id == specId);
    } catch (e) {
      return const SizedBox.shrink();
    }

    bool isFav = favoriteIds.contains(doc.id);
    bool isRequested = status == 'requested';

    return GestureDetector(
      onTap: () {
        _searchFocusNode.unfocus();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => SpecialistProfileScreen(
              specialist: doc!,
              isFavorite: isFav,
              currentAssignment: myAssignment,
              onFavoriteToggle: () => _toggleFavorite(doc!.id),
              onBooking: widget.onBookingConfirmed,
              onRatingUpdated: () => _loadData(),
              onRequestAssignment: () => _loadData(),
              apiClient: widget.apiClient,
            ),
          ),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kWarmWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kAccentPurple, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: kAccentPurple.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isRequested
                      ? Icons.hourglass_empty
                      : Icons.check_circle_outline,
                  color: kAccentPurple,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isRequested
                      ? "Ожидание ответа специалиста"
                      : "Ваш активный психолог",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kAccentPurple,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showCancelOrFinishDialog(isRequested),
                  child: Text(
                    isRequested ? "Отменить" : "Завершить",
                    style: TextStyle(
                      color: isRequested ? kWeekendRed : kTextSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: Colors.black12),
            ),
            Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFFE8E4F7),
                  backgroundImage: doc.image.isEmpty
                      ? null
                      : NetworkImage(doc.image),
                  child: doc.image.isEmpty
                      ? const Icon(Icons.person_outline, size: 40)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: kTextPrimary,
                        ),
                      ),
                      Text(
                        doc.spec,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kAccentPurple,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                                size: 20,
                              ),
                              Text(
                                doc.rating > 0
                                    ? ' ${doc.rating.toStringAsFixed(1)}'
                                    : ' Нет оценок',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kTextPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _toggleFavorite(doc!.id),
                                child: Icon(
                                  isFav
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFav ? Colors.red : kTextSecondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            doc.priceUsdPerSession == null
                                ? 'Цена уточняется'
                                : doc.price,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: kDeepPurple,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              floating: true,
              snap: true,
              elevation: 0,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              expandedHeight: 80,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            style: const TextStyle(color: kTextPrimary),
                            decoration: InputDecoration(
                              hintText: "Поиск психолога...",
                              hintStyle: TextStyle(
                                color: kTextPrimary.withOpacity(0.5),
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: kTextPrimary,
                                size: 22,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _showFilterSheet,
                        child: Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(Icons.tune, color: kTextPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: kAccentPurple),
                )
              : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            isLoading = true;
                          });
                          _loadData();
                        },
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildPinnedDoctorCard(),
                    Expanded(
                      child: filteredSpecialists.isEmpty
                          ? const Center(
                              child: Text(
                                "Ничего не найдено",
                                style: TextStyle(color: kTextSecondary),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 100,
                              ),
                              itemCount: filteredSpecialists.length,
                              itemBuilder: (context, index) =>
                                  _buildDoctorCard(filteredSpecialists[index]),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDoctorCard(Specialist doc) {
    bool isFav = favoriteIds.contains(doc.id);
    return GestureDetector(
      onTap: () {
        _searchFocusNode.unfocus();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => SpecialistProfileScreen(
              specialist: doc,
              isFavorite: isFav,
              currentAssignment: myAssignment,
              onFavoriteToggle: () => _toggleFavorite(doc.id),
              onBooking: widget.onBookingConfirmed,
              onRatingUpdated: () => _loadData(),
              onRequestAssignment: () => _loadData(),
              apiClient: widget.apiClient,
            ),
          ),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kWarmWhite.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0xFFE8E4F7),
              backgroundImage: doc.image.isEmpty
                  ? null
                  : NetworkImage(doc.image),
              child: doc.image.isEmpty
                  ? const Icon(Icons.person_outline, size: 36)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: kTextPrimary,
                    ),
                  ),
                  Text(
                    doc.spec,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kAccentPurple,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 19,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doc.rating > 0
                                  ? doc.rating.toStringAsFixed(1)
                                  : 'Нет оценок',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: kTextPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () => _toggleFavorite(doc.id),
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.red : kTextSecondary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        doc.priceUsdPerSession == null
                            ? 'Цена уточняется'
                            : doc.price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. Экран профиля специалиста
// ==========================================
class SpecialistProfileScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Specialist specialist;
  final bool isFavorite;
  final Map<String, dynamic>? currentAssignment;
  final VoidCallback onFavoriteToggle;
  final Function(Map<String, dynamic>)? onBooking;
  final VoidCallback? onRatingUpdated;
  final VoidCallback? onRequestAssignment;

  const SpecialistProfileScreen({
    super.key,
    required this.specialist,
    required this.isFavorite,
    this.currentAssignment,
    required this.onFavoriteToggle,
    this.onBooking,
    this.onRatingUpdated,
    this.onRequestAssignment,
    required this.apiClient,
  });

  @override
  _SpecialistProfileScreenState createState() =>
      _SpecialistProfileScreenState();
}

class _SpecialistProfileScreenState extends State<SpecialistProfileScreen> {
  late bool _localIsFavorite;

  @override
  void initState() {
    super.initState();
    _localIsFavorite = widget.isFavorite;
  }

  void _showRequestAssignmentDialog() {
    TextEditingController requestCtrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.86,
            ),
            decoration: const BoxDecoration(
              color: kWarmWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: kTextSecondary.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Text(
                    "Подача заявки",
                    style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Напишите пару слов о том, что вас беспокоит. Это поможет специалисту подготовиться.",
                    style: TextStyle(color: kTextSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: requestCtrl,
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(color: kTextPrimary),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: "Опишите ваш запрос...",
                      filled: true,
                      fillColor: kDeepPurple.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentPurple,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () async {
                        final comment = requestCtrl.text.trim();
                        if (comment.length < 20 || comment.length > 2000) {
                          showOakleNotice(
                            ctx,
                            'Опишите запрос минимум 20 символами (до 2000).',
                            isError: true,
                          );
                          return;
                        }
                        try {
                          await widget.apiClient.dio.post(
                            '/patient-assignments/request',
                            data: {
                              'psychologist_id': widget.specialist.id,
                              'comment': comment,
                            },
                          );
                          widget.onRequestAssignment?.call();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            showOakleNotice(
                              context,
                              'Заявка отправлена психологу.',
                            );
                          }
                        } catch (error) {
                          showOakleNotice(
                            ctx,
                            'Не удалось отправить заявку. ${friendlyApiError(error)}',
                            isError: true,
                          );
                        }
                      },
                      child: const Text(
                        "Отправить заявку",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(requestCtrl.dispose);
  }

  Future<bool?> _showStyledDialog(
    BuildContext context,
    String title,
    String content,
    String confirmText,
    Color confirmColor,
  ) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, a1, a2) => Container(),
      transitionBuilder: (context, a1, a2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF6F8FD), Color(0xFFF1EAFF)],
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 20),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF323045),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    content,
                    style: const TextStyle(
                      color: Color(0xFF706D8C),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          "Назад",
                          style: TextStyle(
                            color: Color(0xFF706D8C),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: confirmColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          elevation: 4,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          confirmText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRatingDialog() {
    _checkRatingEligibilityAndShowDialog();
  }

  Future<void> _checkRatingEligibilityAndShowDialog() async {
    try {
      final response = await widget.apiClient.dio.get('/slots/history');
      final rows = response.data;
      final canRate =
          rows is List &&
          rows.any((raw) {
            if (raw is! Map) return false;
            final slot = Map<String, dynamic>.from(raw);
            if (slot['psychologist_id']?.toString() != widget.specialist.id) {
              return false;
            }
            final latest = slot['latest_event'];
            return latest is Map &&
                latest['event_type']?.toString().toLowerCase() == 'completed';
          });

      if (!mounted) return;
      if (!canRate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Оценить психолога можно после завершённого сеанса.'),
          ),
        );
        return;
      }
      _openRatingDialog();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось проверить завершённые сеансы. ${_ratingFailureMessage(error)}',
          ),
        ),
      );
    }
  }

  void _openRatingDialog() {
    showDialog(
      context: context,
      builder: (context) {
        int selectedStars = widget.specialist.rating.round();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kWarmWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                "Оцените специалиста",
                style: TextStyle(color: kTextPrimary),
                textAlign: TextAlign.center,
              ),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      index < selectedStars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 42,
                    ),
                    onPressed: () {
                      setDialogState(() => selectedStars = index + 1);
                    },
                  );
                }),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Отмена",
                    style: TextStyle(color: kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await widget.apiClient.dio.put(
                        '/psychologists_rating/${widget.specialist.id}/rating',
                        data: {'rating': selectedStars},
                      );
                      if (widget.onRatingUpdated != null)
                        widget.onRatingUpdated!();
                      if (context.mounted) Navigator.pop(context);
                    } catch (error) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Не удалось отправить оценку. ${_ratingFailureMessage(error)}',
                            ),
                          ),
                        );
                    }
                  },
                  child: const Text(
                    "Оценить",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _tryBooking(BuildContext context) async {
    final assignment = widget.currentAssignment;
    if (assignment != null) {
      final status = assignment['status']?.toString().toLowerCase();
      final isActive =
          status == 'requested' || status == 'accepted' || status == 'active';
      if (isActive && assignment['psychologistId'] != widget.specialist.id) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "У вас уже есть активная работа со специалистом ${assignment['psychologistName']}. Сначала завершите её.",
            ),
            backgroundColor: kWeekendRed,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;
    _showBookingOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepPurple,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.45,
                  width: double.infinity,
                  child: ColoredBox(
                    color: kDeepPurple,
                    child: Center(
                      child: Icon(
                        Icons.psychology_alt,
                        size: 110,
                        color: kWarmWhite.withOpacity(.8),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.specialist.name,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: kWarmWhite,
                                  ),
                                ),
                                Text(
                                  widget.specialist.spec,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: kWarmWhite.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _showRatingDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: kWarmWhite.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.specialist.rating.toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kWarmWhite,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      Builder(
                        builder: (context) {
                          bool hasActiveAssignment =
                              widget.currentAssignment != null &&
                              (widget.currentAssignment!['status'] ==
                                      'requested' ||
                                  widget.currentAssignment!['status'] ==
                                      'accepted');
                          bool isAssignedToThis =
                              hasActiveAssignment &&
                              widget.currentAssignment!['psychologistId'] ==
                                  widget.specialist.id;

                          if (hasActiveAssignment) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kWarmWhite.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: isAssignedToThis
                                      ? kAccentPurple
                                      : kWeekendRed.withOpacity(0.6),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isAssignedToThis
                                        ? Icons.check_circle
                                        : Icons.info_outline,
                                    color: isAssignedToThis
                                        ? kAccentPurple
                                        : kWeekendRed,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      isAssignedToThis
                                          ? "Вы уже отправили заявку или работаете с этим специалистом."
                                          : "Вы уже выбрали специалиста. Для выбора нового завершите текущую терапию.",
                                      style: const TextStyle(
                                        color: kTextPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(
                                Icons.assignment_ind,
                                color: kAccentPurple,
                              ),
                              label: const Text(
                                "ПОДАТЬ ЗАЯВКУ",
                                style: TextStyle(
                                  color: kAccentPurple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kWarmWhite,
                                foregroundColor: kAccentPurple,
                                elevation: 6,
                                shadowColor: Colors.black45,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              onPressed: _showRequestAssignmentDialog,
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 25),
                      const Text(
                        "О себе",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: kWarmWhite,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.specialist.bio,
                        style: TextStyle(
                          color: kWarmWhite.withOpacity(0.7),
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black26,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: 50,
            right: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black26,
              child: IconButton(
                icon: Icon(
                  _localIsFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _localIsFavorite ? Colors.red : Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    _localIsFavorite = !_localIsFavorite;
                  });
                  widget.onFavoriteToggle();
                },
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: () => _tryBooking(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccentPurple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'ПОСМОТРЕТЬ СВОБОДНОЕ ВРЕМЯ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingOverlay(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Booking",
      pageBuilder: (context, anim1, anim2) {
        return _BookingOverlay(
          spec: widget.specialist,
          apiClient: widget.apiClient,
          onConfirmed: widget.onBooking,
          showStyledDialog: _showStyledDialog,
        );
      },
    );
  }
}

// ==========================================
// 5. Оверлей бронирования (Календарь)
// ==========================================
class _BookingOverlay extends StatefulWidget {
  final Specialist spec;
  final ApiClient apiClient;
  final Function(Map<String, dynamic>)? onConfirmed;
  final Future<bool?> Function(BuildContext, String, String, String, Color)
  showStyledDialog;

  const _BookingOverlay({
    required this.spec,
    required this.apiClient,
    this.onConfirmed,
    required this.showStyledDialog,
  });

  @override
  State<_BookingOverlay> createState() => _BookingOverlayState();
}

class _BookingOverlayState extends State<_BookingOverlay> {
  DateTime visibleMonth = DateTime.now();
  DateTime? _selectedDate;
  String? selectedTime;
  int _calendarSlideDirection = 0;
  final DateTime now = DateTime.now();

  late final SlotsRepository _slotsRepository = SlotsRepository(
    apiClient: widget.apiClient,
  );
  List<SlotModel> _availableSlots = [];
  bool _isLoadingSlots = true;
  String? _slotsError;

  Map<String, List<Map<String, dynamic>>> _bookedVisits = {};

  final List<String> _monthNames = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingBookings();
    _loadAvailableSlots();
  }

  Future<void> _loadAvailableSlots() async {
    try {
      final slots = await _slotsRepository.fetchAvailableSlots();
      if (!mounted) return;
      setState(() {
        _availableSlots = slots
            .where(
              (slot) =>
                  slot.psychologistId == widget.spec.id &&
                  slot.startTime.isAfter(DateTime.now()),
            )
            .toList();
        _isLoadingSlots = false;
        _slotsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _slotsError =
            'Не удалось загрузить доступное время. Попробуйте обновить список.';
      });
    }
  }

  String _timeLabel(SlotModel slot) {
    String fmt(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '${fmt(slot.startTime)} - ${fmt(slot.endTime)}';
  }

  List<SlotModel> _slotsForSelectedDate() => _selectedDate == null
      ? const []
      : _availableSlots
            .where(
              (slot) =>
                  slot.startTime.year == _selectedDate!.year &&
                  slot.startTime.month == _selectedDate!.month &&
                  slot.startTime.day == _selectedDate!.day,
            )
            .toList();

  void _changeMonth({required int delta}) {
    setState(() {
      _calendarSlideDirection = delta > 0 ? 1 : -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }

  Future<void> _loadExistingBookings() async {
    Map<String, List<Map<String, dynamic>>> visits = {};
    try {
      final response = await widget.apiClient.dio.get('/slots/booked');
      for (final raw in (response.data as List)) {
        final slot = Map<String, dynamic>.from(raw as Map);
        final latestEvent = Map<String, dynamic>.from(
          slot['latest_event'] as Map? ?? const {},
        );
        if (slot['psychologist_id']?.toString() != widget.spec.id ||
            (latestEvent['event_type'] != null &&
                latestEvent['event_type'] != 'booked')) {
          continue;
        }
        final start = DateTime.parse(slot['start_at'].toString()).toLocal();
        final end = DateTime.parse(slot['end_at'].toString()).toLocal();
        final dateStr = _formatToYMD(start);
        final time =
            '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        visits.putIfAbsent(dateStr, () => []).add({
          'id': slot['id'].toString(),
          'slot_id': slot['id'].toString(),
          'date': dateStr,
          'time': time,
          'text': widget.spec.name,
          'specialist': widget.spec.name,
          'type': 'visit',
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyApiError(
                error,
                fallback:
                    'Не удалось загрузить записи. Проверьте интернет и повторите попытку.',
              ),
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => _bookedVisits = visits);
  }

  Future<void> _cancelBooking(String dateStr, String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? displayedBooking;
    for (final item in _bookedVisits[dateStr] ?? const []) {
      if (item['id']?.toString() == bookingId) {
        displayedBooking = item;
        break;
      }
    }
    final saved = prefs.getString('notes_$dateStr');
    if (displayedBooking != null) {
      final slotId = displayedBooking['slot_id']?.toString() ?? bookingId;
      try {
        await _slotsRepository.cancelBooking(slotId);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyApiError(
                  error,
                  fallback:
                      'Не удалось отменить запись. Обновите список и попробуйте снова.',
                ),
              ),
            ),
          );
        }
        return;
      }
    } else if (saved != null) {
      try {
        final items = (jsonDecode(saved) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        Map<String, dynamic>? booking;
        for (final item in items) {
          if (item['id'] == bookingId) booking = item;
        }
        final slotId = booking?['slot_id']?.toString();
        if (slotId != null && slotId.isNotEmpty)
          await _slotsRepository.cancelBooking(slotId);
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyApiError(
                  error,
                  fallback:
                      'Не удалось отменить запись. Обновите список и попробуйте снова.',
                ),
              ),
            ),
          );
        return;
      }
    }
    final String dateKey = "notes_$dateStr";
    final String? existingData = prefs.getString(dateKey);

    if (existingData != null) {
      try {
        List<dynamic> notes = jsonDecode(existingData);
        notes.removeWhere(
          (n) => n['id'] == bookingId || n['slot_id'] == bookingId,
        );

        if (notes.isEmpty) {
          await prefs.remove(dateKey);
        } else {
          await prefs.setString(dateKey, jsonEncode(notes));
        }
      } catch (_) {}
    }

    setState(() {
      _bookedVisits[dateStr]?.removeWhere((b) => b['id'] == bookingId);
      if (_bookedVisits[dateStr]?.isEmpty ?? false) {
        _bookedVisits.remove(dateStr);
      }
      selectedTime = null;
    });

    if (widget.onConfirmed != null) {
      widget.onConfirmed!({'date': dateStr, 'action': 'cancel'});
    }
  }

  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  List<DateTime> _buildGridDates(DateTime month) {
    final first = _firstDayOfMonth(month);
    final int startOffset = (first.weekday - 1);
    final DateTime gridStart = DateTime(
      month.year,
      month.month,
      1,
    ).subtract(Duration(days: startOffset));
    // Build civil dates to avoid repeating a local date across DST changes.
    final all = List<DateTime>.generate(
      42,
      (i) => DateTime(gridStart.year, gridStart.month, gridStart.day + i),
    );
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) {
      weeks.add(all.sublist(i, i + 7));
    }
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));
    return weeks.expand((w) => w).toList();
  }

  Future<void> _saveToCalendar(Map<String, dynamic> booking) async {
    final prefs = await SharedPreferences.getInstance();
    final String dateKey = "notes_${booking['date']}";
    final String? existingData = prefs.getString(dateKey);
    List<dynamic> notes = [];
    if (existingData != null) {
      try {
        notes = jsonDecode(existingData);
      } catch (_) {
        notes = [];
      }
    }
    notes.add({
      'id': "booking_${DateTime.now().millisecondsSinceEpoch}",
      'text': "💠 ${booking['specialist']}",
      'time': booking['time'],
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'visit',
      'slot_id': booking['slot_id'],
    });
    await prefs.setString(dateKey, jsonEncode(notes));
  }

  String _formatToYMD(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$year-$month-$day";
  }

  Widget _buildCalendarGrid({
    required Key key,
    required List<DateTime> gridDates,
    required double calendarHeight,
  }) {
    final int totalCells = gridDates.length;
    final int rows = (totalCells / 7).ceil();
    final double cellHeight = calendarHeight / rows;

    return Container(
      key: key,
      child: SizedBox(
        height: calendarHeight,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio:
                (MediaQuery.of(context).size.width / 7) / cellHeight,
          ),
          itemCount: totalCells,
          itemBuilder: (context, idx) {
            final d = gridDates[idx];
            final dateStr = _formatToYMD(d);
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday =
                d.year == now.year && d.month == now.month && d.day == now.day;
            final isWeekend =
                d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
            final hasBooking =
                _bookedVisits.containsKey(dateStr) &&
                _bookedVisits[dateStr]!.isNotEmpty;

            bool isSelected =
                _selectedDate != null &&
                _selectedDate!.day == d.day &&
                _selectedDate!.month == d.month &&
                _selectedDate!.year == d.year;

            Color bg = Colors.transparent;
            if (isSelected) {
              bg = kAccentPurple;
            } else if (hasBooking) {
              bg = kAccentPurple.withOpacity(0.4);
            } else if (isToday) {
              bg = kWarmWhite.withOpacity(0.8);
            }

            Color textColor;
            if (isSelected) {
              textColor = Colors.white;
            } else if (isOtherMonth) {
              textColor = kTextSecondary.withOpacity(0.3);
            } else if (isWeekend) {
              textColor = kWeekendRed;
            } else {
              textColor = kTextPrimary;
            }

            return GestureDetector(
              onTap: () {
                if (isOtherMonth) {
                  setState(() => visibleMonth = DateTime(d.year, d.month));
                  Future.delayed(
                    const Duration(milliseconds: 150),
                    () => setState(() {
                      _selectedDate = d;
                      selectedTime = null;
                    }),
                  );
                } else {
                  setState(() {
                    _selectedDate = d;
                    selectedTime = null;
                  });
                }
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    d.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                      fontWeight: isToday || isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridDates = _buildGridDates(visibleMonth);
    const double calendarHeight = 230;

    String? selectedDateStr = _selectedDate != null
        ? _formatToYMD(_selectedDate!)
        : null;

    List<Map<String, dynamic>> currentBookings = selectedDateStr != null
        ? (_bookedVisits[selectedDateStr] ?? [])
        : [];
    List<String> bookedTimes = currentBookings
        .map((b) => b['time'].toString())
        .toList();
    final slotsForDate = _slotsForSelectedDate();
    List<String> availableTimes = slotsForDate
        .map(_timeLabel)
        .where((t) => !bookedTimes.contains(t))
        .toList();

    return Scaffold(
      backgroundColor: kDeepPurple,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: kWarmWhite, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      "Выбор даты",
                      style: TextStyle(
                        color: kWarmWhite,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: kWarmWhite.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_left,
                            color: kTextPrimary,
                          ),
                          onPressed: () {
                            _changeMonth(delta: -1);
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 1100),
                              transitionBuilder:
                                  (Widget child, Animation<double> anim) {
                                    final offset =
                                        Tween<Offset>(
                                          begin: Offset(
                                            0.22 * _calendarSlideDirection,
                                            0,
                                          ),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: anim,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        );
                                    return ClipRect(
                                      child: SlideTransition(
                                        position: offset,
                                        child: FadeTransition(
                                          opacity: anim,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                              child: Text(
                                '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                                key: ValueKey(
                                  '${visibleMonth.month}_${visibleMonth.year}',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: kTextPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_right,
                            color: kTextPrimary,
                          ),
                          onPressed: () {
                            _changeMonth(delta: 1);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map((
                        d,
                      ) {
                        final isWeekend = d == 'Сб' || d == 'Вс';
                        return Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                color: isWeekend ? kWeekendRed : kTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! < -200) {
                          _changeMonth(delta: 1);
                        } else if (details.primaryVelocity! > 200) {
                          _changeMonth(delta: -1);
                        }
                      },
                      child: SizedBox(
                        height: calendarHeight,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 1100),
                          transitionBuilder:
                              (Widget child, Animation<double> anim) {
                                final offset =
                                    Tween<Offset>(
                                      begin: Offset(
                                        0.18 * _calendarSlideDirection,
                                        0,
                                      ),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: anim,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    );
                                return ClipRect(
                                  child: SlideTransition(
                                    position: offset,
                                    child: FadeTransition(
                                      opacity: anim,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                          child: _buildCalendarGrid(
                            key: ValueKey<String>(
                              'grid_${visibleMonth.year}_${visibleMonth.month}_${gridDates.length}',
                            ),
                            gridDates: gridDates,
                            calendarHeight: calendarHeight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            if (_selectedDate != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currentBookings.isNotEmpty) ...[
                        const Text(
                          "Запланированные визиты",
                          style: TextStyle(
                            color: kWarmWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...currentBookings.map((booking) {
                          String title = booking['text']
                              .toString()
                              .replaceAll("Запись к психологу: ", "")
                              .replaceAll("💠 ", "");
                          if (title.contains(" в "))
                            title = title.split(" в ")[0];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kWarmWhite.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: kAccentPurple.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.event_available,
                                    color: kAccentPurple,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: kTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Сеанс: ${booking['time']}",
                                        style: const TextStyle(
                                          color: kTextSecondary,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    color: kWeekendRed,
                                    size: 28,
                                  ),
                                  onPressed: () async {
                                    String timeStr = booking['time']
                                        .toString()
                                        .split(" - ")[0];
                                    List<String> timeParts = timeStr.split(":");
                                    DateTime date = DateTime.parse(
                                      selectedDateStr!,
                                    );
                                    DateTime appointmentTime = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      int.tryParse(timeParts[0]) ?? 0,
                                      timeParts.length > 1
                                          ? (int.tryParse(timeParts[1]) ?? 0)
                                          : 0,
                                    );

                                    Duration diff = appointmentTime.difference(
                                      DateTime.now(),
                                    );
                                    bool isPenalty = diff.inHours < 24;

                                    final confirmCancel = await widget
                                        .showStyledDialog(
                                          context,
                                          "Отмена записи",
                                          "Вы действительно хотите отменить эту запись?",
                                          "Да, отменить",
                                          kWeekendRed,
                                        );

                                    if (confirmCancel != true) return;

                                    if (isPenalty) {
                                      if (!context.mounted) return;
                                      final confirmForfeit = await widget
                                          .showStyledDialog(
                                            context,
                                            "Внимание!",
                                            "До сеанса осталось менее 24 часов. За отмену может взиматься неустойка. Вы уверены, что хотите отменить?",
                                            "Согласен",
                                            kWeekendRed,
                                          );

                                      if (confirmForfeit != true) return;
                                    }

                                    _cancelBooking(
                                      selectedDateStr,
                                      booking['id'],
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 15),
                      ],

                      if (_isLoadingSlots) ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(color: kWarmWhite),
                          ),
                        ),
                      ] else if (_slotsError != null) ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _slotsError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: kWarmWhite),
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: _loadAvailableSlots,
                            child: const Text('Повторить'),
                          ),
                        ),
                      ] else if (availableTimes.isNotEmpty) ...[
                        const Text(
                          "Доступное время",
                          style: TextStyle(
                            color: kWarmWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: availableTimes
                                .map(
                                  (t) => ChoiceChip(
                                    label: Text(
                                      t,
                                      style: TextStyle(
                                        color: selectedTime == t
                                            ? Colors.white
                                            : kTextPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    selected: selectedTime == t,
                                    selectedColor: kAccentPurple,
                                    backgroundColor: kWarmWhite,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    onSelected: (v) => setState(
                                      () => selectedTime = v ? t : null,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ] else ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text(
                              "Нет доступного времени на этот день",
                              style: TextStyle(color: kWarmWhite, fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedTime != null
                          ? kAccentPurple
                          : Colors.white10,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: selectedTime != null
                        ? () async {
                            final selectedSlot = slotsForDate
                                .where(
                                  (slot) => _timeLabel(slot) == selectedTime,
                                )
                                .first;
                            try {
                              await _slotsRepository.bookSlot(selectedSlot.id);
                            } catch (error) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Не удалось записаться. ${friendlyApiError(error)}',
                                    ),
                                  ),
                                );
                              return;
                            }
                            final data = {
                              'specialist': widget.spec.name,
                              'date': _formatToYMD(_selectedDate!),
                              'time': selectedTime,
                              'slot_id': selectedSlot.id,
                            };
                            await _saveToCalendar(data);
                            await _loadExistingBookings();
                            if (widget.onConfirmed != null)
                              widget.onConfirmed!(data);

                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                        : null,
                    child: const Text(
                      "ПОДТВЕРДИТЬ",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
