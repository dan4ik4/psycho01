import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/widgets/oakle_notice.dart';
import 'breathing_screen.dart';
import 'analytics_screen.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenProfile;
  final ApiClient apiClient;
  final String displayName;
  final bool isPsychologist;

  const HomeScreen({
    required this.onOpenProfile,
    required this.apiClient,
    this.displayName = 'Пользователь',
    this.isPsychologist = false,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool isDarkTheme = false;

  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFF6F8FD);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);
  final Color weekendRed = const Color(0xFFFF8A80);
  final Color lavenderBackground = const Color(0xFFB0A6E8);

  bool isProfileOpen = false;
  bool isLoading = false;
  String fullName = 'Пользователь';
  Map<String, Map<String, dynamic>> notesByDate = {};
  Map<String, List<Map<String, dynamic>>> _bookedSessions = {};
  late DateTime visibleMonth;

  String? selectedImagePath;

  final Map<String, dynamic> moodData = {
    'terrible': {
      'path': 'assets/lottie/terrible.json',
      'color': Colors.redAccent,
      'label': 'Ужасно',
    },
    'bad': {
      'path': 'assets/lottie/bad.json',
      'color': Colors.orange,
      'label': 'Плохо',
    },
    'neutral': {
      'path': 'assets/lottie/neutral.json',
      'color': Colors.amber,
      'label': 'Нормально',
    },
    'good': {
      'path': 'assets/lottie/good.json',
      'color': Colors.lightGreen,
      'label': 'Хорошо',
    },
    'excellent': {
      'path': 'assets/lottie/excellent.json',
      'color': Colors.green,
      'label': 'Отлично',
    },
  };

  String formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      String two(int n) => n.toString().padLeft(2, '0');
      return "${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}";
    } catch (_) {
      return iso;
    }
  }

  int _calendarSlideDirection = 0;

  @override
  void initState() {
    super.initState();
    fullName = widget.displayName;
    visibleMonth = DateTime.now();
    _loadAll();
    _loadBookedSessions();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayName != widget.displayName &&
        fullName != widget.displayName) {
      fullName = widget.displayName;
    }
  }
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('local_diary_entries');
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as Map<String, dynamic>;
        notesByDate = decoded.map(
          (key, value) =>
              MapEntry(key, Map<String, dynamic>.from(value as Map)),
        );
      } catch (_) {
        notesByDate = {};
      }
    }
    fullName = widget.displayName;
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadBookedSessions() async {
    try {
      final response = await widget.apiClient.dio.get('/slots/booked');
      if (response.data is! List) return;
      final visits = <String, List<Map<String, dynamic>>>{};
      for (final raw in response.data as List) {
        if (raw is! Map) continue;
        final slot = Map<String, dynamic>.from(raw);
        final event = Map<String, dynamic>.from(
          slot['latest_event'] as Map? ?? const {},
        );
        if (event['event_type']?.toString().toLowerCase() != 'booked') continue;
        final start = DateTime.tryParse(
          slot['start_at']?.toString() ?? '',
        )?.toLocal();
        final end = DateTime.tryParse(
          slot['end_at']?.toString() ?? '',
        )?.toLocal();
        if (start == null || end == null) continue;
        final date = _dateKey(start);
        final time =
            '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        visits.putIfAbsent(date, () => []).add({
          'id': slot['id']?.toString() ?? '',
          'time': time,
          'psychologistId': slot['psychologist_id']?.toString() ?? '',
        });
      }
      if (mounted) setState(() => _bookedSessions = visits);
    } catch (error) {
      debugPrint('Could not load booked sessions for home calendar: $error');
    }
  }

  Future<void> _persistNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_diary_entries', jsonEncode(notesByDate));
  }

  Future<void> _openUpcomingCall() async {
    try {
      final response = await widget.apiClient.dio.get('/slots/booked');
      final slots = (response.data as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final future =
          slots
              .where(
                (slot) => DateTime.parse(
                  slot['start_at'].toString(),
                ).isAfter(DateTime.now()),
              )
              .toList()
            ..sort(
              (a, b) => DateTime.parse(
                a['start_at'].toString(),
              ).compareTo(DateTime.parse(b['start_at'].toString())),
            );
      if (future.isEmpty) {
        if (mounted)
          showOakleNotice(context, 'У вас пока нет предстоящих записей.');
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            slotId: future.first['id'].toString(),
            apiClient: widget.apiClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        showOakleNotice(
          context,
          friendlyApiError(
            error,
            fallback:
                'Не удалось выполнить действие с записью. Обновите список и попробуйте снова.',
          ),
          isError: true,
        );
    }
  }

  Future<void> _saveDayMood(DateTime day, String mood) async {
    final dateKey = _dateKey(day);
    notesByDate.putIfAbsent(dateKey, () => {'items': []});
    notesByDate[dateKey]!['dayMood'] = mood;
    await _persistNotes();
  }

  Future<String> _addNoteForDay(
    DateTime day,
    String text,
    String? imagePath,
  ) async {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<void> _updateNoteForDay(
    DateTime day,
    String noteId,
    String newText,
    String? imagePath,
  ) async {
    // The caller updates the entry before persisting the local diary.
  }

  Future<void> _deleteNoteById(DateTime day, {String? noteId}) async {
    if (noteId == null) return;
    final items = notesByDate[_dateKey(day)]?['items'] as List<dynamic>?;
    items?.removeWhere(
      (item) => (item as Map<String, dynamic>)['id'].toString() == noteId,
    );
    await _persistNotes();
  }

  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  List<DateTime> _buildGridDates(DateTime month) {
    final first = _firstDayOfMonth(month);
    final int startOffset = (first.weekday - 1);
    final DateTime gridStart = DateTime(
      first.year,
      first.month,
      1 - startOffset,
    );

    final all = List<DateTime>.generate(42, (i) {
      return DateTime(gridStart.year, gridStart.month, gridStart.day + i);
    });

    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) {
      weeks.add(all.sublist(i, i + 7));
    }
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));
    return weeks.expand((w) => w).toList();
  }

  void _changeMonth({required int delta}) {
    setState(() {
      _calendarSlideDirection = delta > 0 ? 1 : -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }

  void _showFullScreenImage(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: path.startsWith('http')
                  ? Image.network(path)
                  : Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
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
      transitionDuration: const Duration(milliseconds: 300),
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

  void _openDaySheet(DateTime day) {
    final dateKey = _dateKey(day);
    final existing = notesByDate[dateKey];
    String? dayMood = existing?['dayMood'];
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      existing != null && existing['items'] != null
          ? existing['items'] as List
          : [],
    );

    final newController = TextEditingController();
    String? editingId;
    bool confirmShown = false;
    String? newlyAddedId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (bool didPop, dynamic result) async {
                if (didPop) return;
                if (!confirmShown &&
                    newController.text.trim().isNotEmpty &&
                    editingId == null) {
                  confirmShown = true;
                  final confirm = await _showStyledDialog(
                    context,
                    "Закрыть без сохранения?",
                    "Текущая заметка не сохранена.",
                    "Закрыть",
                    weekendRed,
                  );
                  confirmShown = false;
                  if (confirm == true && context.mounted) {
                    Navigator.of(context).pop();
                  }
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: GestureDetector(
                onTap: () {},
                child: DraggableScrollableSheet(
                  initialChildSize: 0.75,
                  minChildSize: 0.3,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: lavenderBackground,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Записи на ${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: textPrimary),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Блок выбора настроения
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: warmWhite.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: moodData.entries.map((e) {
                                bool isSel = dayMood == e.key;
                                return GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      dayMood = e.key;
                                    });
                                    if (notesByDate[dateKey] == null) {
                                      notesByDate[dateKey] = {'items': []};
                                    }
                                    notesByDate[dateKey]!['dayMood'] = e.key;
                                    _saveDayMood(day, e.key);
                                    if (mounted) setState(() {});
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? e.value['color'].withOpacity(0.3)
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSel
                                            ? e.value['color']
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Lottie.asset(
                                      e.value['path'],
                                      key: ValueKey(
                                        '${e.key}_${dayMood == e.key}',
                                      ),
                                      width: 40,
                                      height: 40,
                                      repeat: false,
                                      animate: isSel,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if ((_bookedSessions[dateKey] ?? []).isNotEmpty) ...[
                            Text(
                              'Сеансы с психологом',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...(_bookedSessions[dateKey]!).map(
                              (booking) => Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: warmWhite.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.videocam_rounded,
                                      color: accentPurple,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Сеанс: ${booking['time']}',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (selectedImagePath != null)
                            Stack(
                              alignment: Alignment.topRight,
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      _showFullScreenImage(selectedImagePath!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: selectedImagePath!.startsWith('http')
                                        ? Image.network(
                                            selectedImagePath!,
                                            height: 120,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          )
                                        : Image.file(
                                            File(selectedImagePath!),
                                            height: 120,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.cancel,
                                    color: textPrimary.withOpacity(0.5),
                                  ),
                                  onPressed: () => setModalState(
                                    () => selectedImagePath = null,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: newController,
                            maxLines: 3,
                            minLines: 2,
                            style: TextStyle(color: textPrimary),
                            decoration: InputDecoration(
                              hintText: editingId == null
                                  ? 'Как прошел день?'
                                  : 'Редактирование заметки...',
                              hintStyle: TextStyle(color: textSecondary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: warmWhite.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                icon: Icon(Icons.check, color: textPrimary),
                                label: Text(
                                  "Сохранить",
                                  style: TextStyle(color: textPrimary),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: warmWhite.withOpacity(0.8),
                                  elevation: 0,
                                ),
                                onPressed: () async {
                                  final txt = newController.text.trim();
                                  if (txt.isEmpty && selectedImagePath == null)
                                    return;

                                  if (editingId == null) {
                                    final id = await _addNoteForDay(
                                      day,
                                      txt,
                                      selectedImagePath,
                                    );
                                    items.insert(0, {
                                      "id": id,
                                      "text": txt,
                                      "imagePath": selectedImagePath,
                                      "createdAt": DateTime.now()
                                          .toIso8601String(),
                                    });
                                    newlyAddedId = id;
                                  } else {
                                    await _updateNoteForDay(
                                      day,
                                      editingId!,
                                      txt,
                                      selectedImagePath,
                                    );
                                    final idx = items.indexWhere(
                                      (e) => e["id"] == editingId,
                                    );
                                    if (idx != -1) {
                                      items[idx]["text"] = txt;
                                      items[idx]["imagePath"] =
                                          selectedImagePath;
                                      items[idx]["createdAt"] = DateTime.now()
                                          .toIso8601String();
                                    }
                                    editingId = null;
                                  }

                                  if (notesByDate[dateKey] == null)
                                    notesByDate[dateKey] = {'items': []};
                                  notesByDate[dateKey]!['items'] =
                                      List<Map<String, dynamic>>.from(items);
                                  await _persistNotes();
                                  newController.clear();
                                  selectedImagePath = null;
                                  if (context.mounted) setModalState(() {});
                                  if (mounted) setState(() {});
                                  Future.delayed(
                                    const Duration(milliseconds: 300),
                                    () {
                                      if (context.mounted)
                                        setModalState(
                                          () => newlyAddedId = null,
                                        );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(
                                  Icons.photo_camera,
                                  color: accentPurple,
                                ),
                                onPressed: () => pickImage(setModalState),
                              ),
                              const Spacer(),
                              if (editingId != null)
                                OutlinedButton(
                                  onPressed: () {
                                    editingId = null;
                                    newController.clear();
                                    selectedImagePath = null;
                                    setModalState(() {});
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: accentPurple),
                                  ),
                                  child: Text(
                                    'Отмена',
                                    style: TextStyle(color: textSecondary),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (items.isEmpty)
                            Text(
                              'Заметок пока нет.',
                              style: TextStyle(color: textSecondary),
                            )
                          else
                            Column(
                              children: items.map((note) {
                                final id = note['id']?.toString() ?? '';
                                final text = note['text']?.toString() ?? '';
                                final createdAt =
                                    note['createdAt']?.toString() ?? '';
                                final imgPath = note['imagePath']?.toString();
                                final bool isNew = (id == newlyAddedId);
                                final bool isAppointment = text.contains('💠');

                                final Widget card = Card(
                                  color: warmWhite.withOpacity(0.85),
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (imgPath != null)
                                        GestureDetector(
                                          onTap: () =>
                                              _showFullScreenImage(imgPath),
                                          child: ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(16),
                                                ),
                                            child: imgPath.startsWith('http')
                                                ? Image.network(
                                                    imgPath,
                                                    width: double.infinity,
                                                    height: 120,
                                                    fit: BoxFit.cover,
                                                  )
                                                : Image.file(
                                                    File(imgPath),
                                                    width: double.infinity,
                                                    height: 120,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                      ListTile(
                                        leading:
                                            dayMood != null &&
                                                moodData.containsKey(dayMood) &&
                                                !isAppointment
                                            ? Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      (moodData[dayMood]['color']
                                                              as Color)
                                                          .withOpacity(0.15),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Lottie.asset(
                                                  moodData[dayMood]['path'],
                                                  width: 32,
                                                  height: 32,
                                                  repeat: false,
                                                ),
                                              )
                                            : Container(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: accentPurple
                                                      .withOpacity(0.15),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.event_available,
                                                  color: accentPurple,
                                                  size: 24,
                                                ),
                                              ),
                                        title: Text(
                                          text,
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          formatDate(createdAt),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: textSecondary,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.edit,
                                                color: accentPurple,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                editingId = id;
                                                newController.text = text;
                                                selectedImagePath = imgPath;
                                                setModalState(() {});
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                              onPressed: () async {
                                                FocusScope.of(
                                                  context,
                                                ).unfocus();

                                                if (isAppointment) {
                                                  final confirmCancel =
                                                      await _showStyledDialog(
                                                        context,
                                                        "Отмена записи",
                                                        "Вы действительно хотите отменить запись к психологу на ${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}?",
                                                        "Да, отменить",
                                                        weekendRed,
                                                      );

                                                  if (confirmCancel != true)
                                                    return;
                                                  if (!context.mounted) return;

                                                  String timeStr =
                                                      note['time']
                                                          ?.toString() ??
                                                      "00:00";
                                                  if (timeStr.contains(" - "))
                                                    timeStr = timeStr.split(
                                                      " - ",
                                                    )[0];
                                                  List<String> timeParts =
                                                      timeStr.split(":");
                                                  DateTime
                                                  appointmentTime = DateTime(
                                                    day.year,
                                                    day.month,
                                                    day.day,
                                                    int.tryParse(
                                                          timeParts[0],
                                                        ) ??
                                                        0,
                                                    timeParts.length > 1
                                                        ? (int.tryParse(
                                                                timeParts[1],
                                                              ) ??
                                                              0)
                                                        : 0,
                                                  );

                                                  Duration diff =
                                                      appointmentTime
                                                          .difference(
                                                            DateTime.now(),
                                                          );
                                                  bool isPenalty =
                                                      diff.inHours < 24;

                                                  if (isPenalty) {
                                                    final confirmForfeit =
                                                        await _showStyledDialog(
                                                          context,
                                                          "Внимание",
                                                          "При отмене визита менее чем за 24 часа удерживается неустойка 100%. Вы уверены, что хотите продолжить?",
                                                          "Согласен",
                                                          weekendRed,
                                                        );
                                                    if (confirmForfeit != true)
                                                      return;
                                                  }
                                                } else {
                                                  final confirm =
                                                      await _showStyledDialog(
                                                        context,
                                                        "Удалить заметку?",
                                                        "Восстановить её будет невозможно.",
                                                        "Удалить",
                                                        weekendRed,
                                                      );
                                                  if (confirm != true) return;
                                                }

                                                await _deleteNoteById(
                                                  day,
                                                  noteId: id,
                                                );
                                                items.removeWhere(
                                                  (e) =>
                                                      e["id"].toString() == id,
                                                );
                                                if (editingId == id) {
                                                  editingId = null;
                                                  newController.clear();
                                                  selectedImagePath = null;
                                                }
                                                setModalState(() {});
                                                if (mounted) setState(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (!isNew) return card;
                                return TweenAnimationBuilder<double>(
                                  key: ValueKey(id),
                                  tween: Tween(begin: -20.0, end: 0.0),
                                  duration: const Duration(milliseconds: 400),
                                  builder: (context, value, child) {
                                    return Transform.translate(
                                      offset: Offset(0, value),
                                      child: Opacity(
                                        opacity: 1 - (value.abs() / 20),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: card,
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      selectedImagePath = null;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final gridDates = _buildGridDates(visibleMonth);
    const double topBarHeight = 85;
    const double calendarHeight = 230;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: deepPurple),
        child: Stack(
          children: [
            Positioned.fill(
              top: topBarHeight + 10,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      // Карточка Приветствия
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: warmWhite.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Здравствуйте, $fullName',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Рады видеть вас снова!',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Карточка Календаря
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: warmWhite.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.chevron_left,
                                      color: textPrimary,
                                    ),
                                    onPressed: () {
                                      _calendarSlideDirection = -1;
                                      _changeMonth(delta: -1);
                                    },
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 400,
                                        ),
                                        transitionBuilder:
                                            (
                                              Widget child,
                                              Animation<double> anim,
                                            ) {
                                              final offset =
                                                  Tween<Offset>(
                                                    begin: Offset(
                                                      0.2 *
                                                          _calendarSlideDirection,
                                                      0,
                                                    ),
                                                    end: Offset.zero,
                                                  ).animate(
                                                    CurvedAnimation(
                                                      parent: anim,
                                                      curve: Curves.easeInOut,
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
                                          '${_monthName(visibleMonth.month)} ${visibleMonth.year}',
                                          key: ValueKey(
                                            '${visibleMonth.month}_${visibleMonth.year}',
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.chevron_right,
                                      color: textPrimary,
                                    ),
                                    onPressed: () {
                                      _calendarSlideDirection = 1;
                                      _changeMonth(delta: 1);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children:
                                    [
                                      'Пн',
                                      'Вт',
                                      'Ср',
                                      'Чт',
                                      'Пт',
                                      'Сб',
                                      'Вс',
                                    ].map((d) {
                                      final isWeekend = d == 'Сб' || d == 'Вс';
                                      return Expanded(
                                        child: Center(
                                          child: Text(
                                            d,
                                            style: TextStyle(
                                              color: isWeekend
                                                  ? weekendRed
                                                  : textSecondary,
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
                                    _calendarSlideDirection = 1;
                                    _changeMonth(delta: 1);
                                  } else if (details.primaryVelocity! > 200) {
                                    _calendarSlideDirection = -1;
                                    _changeMonth(delta: -1);
                                  }
                                },
                                child: SizedBox(
                                  height: calendarHeight,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder:
                                        (Widget child, Animation<double> anim) {
                                          final offset =
                                              Tween<Offset>(
                                                begin: Offset(
                                                  0.2 * _calendarSlideDirection,
                                                  0,
                                                ),
                                                end: Offset.zero,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent: anim,
                                                  curve: Curves.easeInOut,
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
                                      now: now,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Карточка Сессия с психологом
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: InkWell(
                          onTap: _openUpcomingCall,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: accentPurple,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.videocam_rounded,
                                  color: warmWhite,
                                  size: 30,
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Сессия с психологом",
                                        style: TextStyle(
                                          color: warmWhite,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        "Нажмите, чтобы войти в комнату",
                                        style: TextStyle(
                                          color: warmWhite.withOpacity(0.8),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: warmWhite,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Карточка Дыхательной практики
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BreathingScreen(),
                            ),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: warmWhite.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Image.asset(
                                    'assets/images/Wind.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Дыхательная практика',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Снижение стресса',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.play_circle_fill,
                                  color: accentPurple,
                                  size: 40,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
            // ВЕРХНЯЯ ПАНЕЛЬ
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: topBarHeight,
                color: Colors.transparent,
                child: SafeArea(
                  bottom: false,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 10,
                        child: IconButton(
                          icon: Icon(Icons.menu, color: warmWhite, size: 28),
                          onPressed: widget.onOpenProfile,
                        ),
                      ),
                      IgnorePointer(
                        child: Image.asset(
                          'assets/images/White_Lotus.png',
                          height: topBarHeight * 0.8,
                        ),
                      ),
                      Positioned(
                        right: 10,
                        child: IconButton(
                          icon: Icon(
                            Icons.bar_chart_rounded,
                            color: warmWhite,
                            size: 28,
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AnalyticsScreen(notesData: notesByDate),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid({
    required Key key,
    required List<DateTime> gridDates,
    required double calendarHeight,
    required DateTime now,
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
            final dKey = _dateKey(d);
            final note = notesByDate[dKey];
            final hasBooking = (_bookedSessions[dKey]?.isNotEmpty ?? false);
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday =
                d.year == now.year && d.month == now.month && d.day == now.day;
            final isWeekend =
                d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

            Color bg = Colors.transparent;
            bool hasNote = false;

            if (note != null) {
              final items = (note['items'] as List?);
              if (items != null && items.isNotEmpty) {
                hasNote = true;
              }
              String? mood = note['dayMood'];
              if (mood != null && moodData.containsKey(mood)) {
                bg = moodData[mood]['color'].withOpacity(0.3);
              } else if (hasNote) {
                bg = warmWhite.withOpacity(0.8);
              }
            }

            if (hasBooking && bg == Colors.transparent) {
              bg = accentPurple.withOpacity(0.2);
            }

            return GestureDetector(
              onTap: () {
                if (isOtherMonth) {
                  setState(() => visibleMonth = DateTime(d.year, d.month));
                  Future.delayed(
                    const Duration(milliseconds: 150),
                    () => _openDaySheet(d),
                  );
                } else {
                  _openDaySheet(d);
                }
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isToday ? warmWhite.withOpacity(0.8) : bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      d.day.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 14,
                        color: isOtherMonth
                            ? textSecondary.withOpacity(0.3)
                            : (isWeekend ? weekendRed : textPrimary),
                        fontWeight: isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (hasBooking)
                      Positioned(
                        bottom: 2,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: accentPurple,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      '',
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
    return names[m];
  }

  Future<void> pickImage(StateSetter setModalState) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: deepPurple,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Wrap(
            children: <Widget>[
              _imageSourceTile(
                Icons.photo_library,
                'Галерея',
                ImageSource.gallery,
                setModalState,
              ),
              _imageSourceTile(
                Icons.photo_camera,
                'Камера',
                ImageSource.camera,
                setModalState,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _imageSourceTile(
    IconData icon,
    String title,
    ImageSource source,
    StateSetter setModalState,
  ) {
    return ListTile(
      leading: Icon(icon, color: accentPurple),
      title: Text(title, style: TextStyle(color: textPrimary)),
      onTap: () async {
        Navigator.of(context).pop();
        final image = await ImagePicker().pickImage(source: source);
        if (image != null) {
          final directory = await getApplicationDocumentsDirectory();
          final String fileName =
              "img_${DateTime.now().millisecondsSinceEpoch}${p.extension(image.path)}";
          final String savedPath = p.join(directory.path, fileName);
          await File(image.path).copy(savedPath);
          setModalState(() => selectedImagePath = savedPath);
        }
      },
    );
  }
}
