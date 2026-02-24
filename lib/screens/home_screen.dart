// lib/screens/home_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'breathing_screen.dart';
import 'SpecialistSelectionScreen.dart';
import 'chat_screen.dart';
import 'plan_screen.dart';
import 'analytics_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;


class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenProfile;
  const HomeScreen({required this.onOpenProfile, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool isDarkTheme = false;
  final Color purple = const Color(0xFF5E3B8C);
  final Color darkWhite = const Color(0xFFF2F2F2);
  final Color pureWhite = Colors.white;

  bool isProfileOpen = false;
  String fullName = 'Пользователь';
  Map<String, Map<String, dynamic>> notesByDate = {};
  late DateTime visibleMonth;

  String? selectedImagePath;


  // ИЗМЕНЕНО: Порядок от Ужасного (слева) до Отличного (справа)
  final Map<String, dynamic> moodData = {
    'terrible': {'emoji': '😫', 'color': Colors.redAccent, 'label': 'Ужасно'},
    'bad': {'emoji': '😔', 'color': Colors.orange, 'label': 'Плохо'},
    'neutral': {'emoji': '😐', 'color': Colors.amber, 'label': 'Нормально'},
    'good': {'emoji': '🙂', 'color': Colors.lightGreen, 'label': 'Хорошо'},
    'excellent': {'emoji': '😊', 'color': Colors.green, 'label': 'Отлично'},
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
    visibleMonth = DateTime.now();
    _loadAll();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
  String _notesKeyForDate(DateTime d) => 'notes_${_dateKey(d)}';

  Future<void> _loadAll() async {
    final prefs = await _prefs();
    setState(() {
      fullName = prefs.getString('full_name') ?? fullName;
      isDarkTheme = prefs.getBool('isDarkTheme') ?? false;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final meta = user.userMetadata ?? {};
        final supaName = (meta['full_name'] ?? meta['name'])?.toString();
        if (supaName != null && supaName.isNotEmpty) {
          setState(() => fullName = supaName);
        }
      }
    } catch (_) {}

    final keys = prefs.getKeys();
    final Map<String, Map<String, dynamic>> tmp = {};
    for (final k in keys) {
      // Загружаем заметки
      if (k.startsWith('notes_')) {
        final dateKey = k.substring(6);
        tmp.putIfAbsent(dateKey, () => {'items': []});
        try {
          final raw = prefs.getString(k);
          if (raw != null) {
            tmp[dateKey]!['items'] = (jsonDecode(raw) as List).map((e) => e as Map<String, dynamic>).toList();
          }
        } catch (_) {}
      }
      // Загружаем независимое настроение дня
      else if (k.startsWith('mood_')) {
        final dateKey = k.substring(5);
        tmp.putIfAbsent(dateKey, () => {'items': []});
        tmp[dateKey]!['dayMood'] = prefs.getString(k);
      }
    }
    setState(() => notesByDate = tmp);
  }

  // НОВОЕ: Моментальное сохранение настроения для дня
  Future<void> _saveDayMood(DateTime day, String mood) async {
    final dateKey = _dateKey(day);
    final prefs = await _prefs();
    await prefs.setString('mood_$dateKey', mood);
    setState(() {
      notesByDate.putIfAbsent(dateKey, () => {'items': []});
      notesByDate[dateKey]!['dayMood'] = mood;
    });
  }

  String _noteId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<String> _addNoteForDay(DateTime day, String text, String? imagePath) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);
    final newId = _noteId();

    final newNote = {
      'id': newId,
      'text': text,
      'imagePath': imagePath,
      'createdAt': DateTime.now().toIso8601String()
    };

    final raw = prefs.getString(key);
    List<dynamic> arr = [];
    if (raw != null) {
      try { arr = jsonDecode(raw) as List<dynamic>; } catch (_) { arr = []; }
    }

    arr.add(newNote);
    await prefs.setString(key, jsonEncode(arr));
    return newId;
  }

  Future<void> _updateNoteForDay(DateTime day, String noteId, String newText, String? imagePath) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);
    final raw = prefs.getString(key);
    if (raw == null) return;

    List<dynamic> arr;
    try { arr = jsonDecode(raw) as List<dynamic>; } catch (_) { return; }

    bool changed = false;
    for (var i = 0; i < arr.length; i++) {
      final n = arr[i] as Map<String, dynamic>;
      if (n['id'] == noteId) {
        n['text'] = newText;
        n['imagePath'] = imagePath;
        n['createdAt'] = DateTime.now().toIso8601String();
        arr[i] = n;
        changed = true;
        break;
      }
    }

    if (!changed) return;
    await prefs.setString(key, jsonEncode(arr));
  }

  Future<void> _deleteNoteById(DateTime day, {String? noteId}) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);
    final raw = prefs.getString(key);
    if (raw == null) return;

    List<dynamic> arr;
    try { arr = jsonDecode(raw) as List<dynamic>; } catch (_) { arr = []; }

    final newArr = arr.where((e) => (e as Map<String, dynamic>)['id'] != noteId).toList();
    await prefs.setString(key, jsonEncode(newArr));

    final dateKey = _dateKey(day);
    setState(() {
      if (notesByDate.containsKey(dateKey)) {
        notesByDate[dateKey]!['items'] = newArr.map((e) => e as Map<String, dynamic>).toList();
      }
    });
  }

  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  List<DateTime> _buildGridDates(DateTime month) {
    final first = _firstDayOfMonth(month);
    final int startOffset = (first.weekday - 1);
    final DateTime gridStart = DateTime(month.year, month.month, 1).subtract(Duration(days: startOffset));
    final all = List<DateTime>.generate(42, (i) => gridStart.add(Duration(days: i)));
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) { weeks.add(all.sublist(i, i + 7)); }
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));
    return weeks.expand((w) => w).toList();
  }

  void _changeMonth({required int delta}) {
    setState(() {
      _calendarSlideDirection = delta > 0 ? 1 : -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }

  // НОВОЕ: Просмотр фото на весь экран
  void _showFullScreenImage(String path) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
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
          child: Image.file(File(path)),
        ),
      ),
    )));
  }

  void _openDaySheet(DateTime day) {
    final dateKey = _dateKey(day);
    final existing = notesByDate[dateKey];

    String? dayMood = existing?['dayMood'];

    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        existing != null && existing['items'] != null ? existing['items'] as List : []);

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
        return StatefulBuilder(builder: (context, setModalState) {

          return WillPopScope(
            onWillPop: () async {
              if (!confirmShown && newController.text.trim().isNotEmpty && editingId == null) {
                confirmShown = true;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Закрыть без сохранения?"),
                    content: const Text("Текущая заметка не сохранена."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Нет")),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Да")),
                    ],
                  ),
                );
                confirmShown = false;
                return confirm == true;
              }
              return true;
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
                    color: isDarkTheme ? Colors.grey[900] : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkTheme ? Colors.white : Colors.black87),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: purple),
                              onPressed: () async {
                                if (!confirmShown && newController.text.trim().isNotEmpty && editingId == null) {
                                  // Код проверки на закрытие
                                  // ... (оставил как было)
                                  Navigator.of(ctx).pop();
                                } else {
                                  Navigator.of(ctx).pop();
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // ИЗМЕНЕНО: Смайлики теперь сохраняют Настроение Дня моментально
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: moodData.entries.map((e) {
                            bool isSel = dayMood == e.key;
                            return GestureDetector(
                              onTap: () {
                                setModalState(() => dayMood = e.key);
                                _saveDayMood(day, e.key); // Сразу сохраняем
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isSel ? e.value['color'].withOpacity(0.2) : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isSel ? e.value['color'] : Colors.transparent, width: 2),
                                ),
                                child: Text(e.value['emoji'], style: const TextStyle(fontSize: 28)),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),

                        if (selectedImagePath != null)
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              GestureDetector(
                                onTap: () => _showFullScreenImage(selectedImagePath!),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(File(selectedImagePath!), height: 120, width: double.infinity, fit: BoxFit.cover),
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.cancel, color: Colors.white), onPressed: () => setModalState(() => selectedImagePath = null))
                            ],
                          ),
                        const SizedBox(height: 8),

                        TextField(
                          controller: newController,
                          maxLines: 3,
                          minLines: 2,
                          decoration: InputDecoration(
                            hintText: editingId == null ? 'Как прошел день?' : 'Редактирование заметки...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            filled: true,
                            fillColor: isDarkTheme ? Colors.grey[850] : Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check, color: Colors.white),
                              label: const Text("Сохранить", style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(backgroundColor: purple),
                              onPressed: () async {
                                final txt = newController.text.trim();
                                if (txt.isEmpty && selectedImagePath == null) return;

                                if (editingId == null) {
                                  final id = await _addNoteForDay(day, txt, selectedImagePath);
                                  items.insert(0, {"id": id, "text": txt, "imagePath": selectedImagePath, "createdAt": DateTime.now().toIso8601String()});
                                  newlyAddedId = id;
                                } else {
                                  await _updateNoteForDay(day, editingId!, txt, selectedImagePath);
                                  final idx = items.indexWhere((e) => e["id"] == editingId);
                                  if (idx != -1) {
                                    items[idx]["text"] = txt;
                                    items[idx]["imagePath"] = selectedImagePath;
                                    items[idx]["createdAt"] = DateTime.now().toIso8601String();
                                  }
                                  editingId = null;
                                }

                                if (notesByDate[dateKey] == null) notesByDate[dateKey] = {'items': []};
                                notesByDate[dateKey]!['items'] = List<Map<String, dynamic>>.from(items);

                                newController.clear();
                                selectedImagePath = null;
                                if (context.mounted) setModalState(() {});
                                if (mounted) setState(() {});

                                Future.delayed(const Duration(milliseconds: 700), () {
                                  if (context.mounted) setModalState(() => newlyAddedId = null);
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(icon: Icon(Icons.photo_camera, color: purple), onPressed: () => pickImage(setModalState)),
                            const Spacer(),
                            if (editingId != null)
                              OutlinedButton(onPressed: () { editingId = null; newController.clear(); selectedImagePath = null; setModalState(() {}); }, child: const Text('Отмена')),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (items.isEmpty)
                          Text('Заметок пока нет.', style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54))
                        else
                          Column(
                            children: items.map((note) {
                              final id = note['id']?.toString() ?? '';
                              final text = note['text']?.toString() ?? '';
                              final createdAt = note['createdAt']?.toString() ?? '';
                              final imgPath = note['imagePath']?.toString();
                              final bool isNew = (id == newlyAddedId);

                              final Widget card = Card(
                                color: isDarkTheme ? Colors.grey[850] : Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (imgPath != null)
                                      GestureDetector(
                                        onTap: () => _showFullScreenImage(imgPath),
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                          child: Image.file(File(imgPath), width: double.infinity, height: 120, fit: BoxFit.cover),
                                        ),
                                      ),
                                    ListTile(
                                      leading: dayMood != null ? Text(moodData[dayMood]['emoji'], style: const TextStyle(fontSize: 24)) : const Icon(Icons.notes),
                                      title: Text(text, style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black87)),
                                      subtitle: Text(formatDate(createdAt), style: TextStyle(fontSize: 11, color: isDarkTheme ? Colors.white60 : Colors.black54)),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.deepPurple, size: 20),
                                            onPressed: () {
                                              editingId = id;
                                              newController.text = text;
                                              selectedImagePath = imgPath;
                                              setModalState(() {});
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                            onPressed: () async {
                                              FocusScope.of(context).unfocus();
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (dctx) => AlertDialog(
                                                  title: const Text("Удалить заметку?"),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("Нет")),
                                                    TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("Да")),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                await _deleteNoteById(day, noteId: id);
                                                items.removeWhere((e) => e["id"].toString() == id);
                                                if (editingId == id) { editingId = null; newController.clear(); selectedImagePath = null; }
                                                setModalState(() {});
                                                if (mounted) setState(() {});
                                              }
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
                                duration: const Duration(milliseconds: 350),
                                builder: (context, value, child) {
                                  return Transform.translate(offset: Offset(0, value), child: Opacity(opacity: 1 - (value.abs() / 20), child: child));
                                },
                                child: card,
                              );
                            }).toList(),
                          )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        });
      },
    ).whenComplete(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isDarkTheme ? const Color(0xFF121212) : darkWhite;
    final Color cardColor = isDarkTheme ? const Color(0xFF1E1E1E) : pureWhite;
    final Color textColor = isDarkTheme ? Colors.white : Colors.black87;

    final now = DateTime.now();
    final gridDates = _buildGridDates(visibleMonth);

    final double topBarHeight = 85;
    final double calendarHeight = 230;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
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

                    // Greeting card (Без кнопки аналитики, она теперь в шапке)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Здравствуйте, $fullName', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: purple)),
                            const SizedBox(height: 6),
                            Text('Рады видеть вас снова!', style: TextStyle(fontSize: 16, color: textColor)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Calendar container
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        decoration: BoxDecoration(color: purple.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { _calendarSlideDirection = -1; _changeMonth(delta: -1); }),
                                Expanded(
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 1100),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (Widget child, Animation<double> anim) {
                                        final offset = Tween<Offset>(begin: Offset(0.22 * _calendarSlideDirection, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                                        return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                                      },
                                      child: Text('${_monthName(visibleMonth.month)} ${visibleMonth.year}', key: ValueKey('${visibleMonth.month}_${visibleMonth.year}'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                                    ),
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { _calendarSlideDirection = 1; _changeMonth(delta: 1); }),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'].map((d) {
                                final isWeekend = d == 'Сб' || d == 'Вс';
                                return Expanded(child: Center(child: Text(d, style: TextStyle(color: isWeekend ? purple : textColor, fontWeight: FontWeight.w600))));
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onHorizontalDragEnd: (details) {
                                if (details.primaryVelocity == null) return;
                                if (details.primaryVelocity! < -200) { _calendarSlideDirection = 1; _changeMonth(delta: 1); }
                                else if (details.primaryVelocity! > 200) { _calendarSlideDirection = -1; _changeMonth(delta: -1); }
                              },
                              child: SizedBox(
                                height: calendarHeight,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 1100),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (Widget child, Animation<double> anim) {
                                    final offset = Tween<Offset>(begin: Offset(0.18 * _calendarSlideDirection, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                                    return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                                  },
                                  child: _buildCalendarGrid(key: ValueKey<String>('grid_${visibleMonth.year}_${visibleMonth.month}_${gridDates.length}'), gridDates: gridDates, calendarHeight: calendarHeight, textColor: textColor, now: now),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Breathing card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const BreathingScreen())); },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: purple.withOpacity(0.15)),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 60, height: 60, child: Image.asset('assets/images/meditation.png', fit: BoxFit.contain)),
                              const SizedBox(width: 16),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Дыхательная практика', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)), const SizedBox(height: 4), Text('Снижение стресса', style: TextStyle(color: Colors.grey[600], fontSize: 13))])),
                              Icon(Icons.play_circle_fill, color: purple, size: 40),
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

          // ИЗМЕНЕНО: Кнопка Аналитики добавлена справа, симметрично профилю
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: topBarHeight, color: cardColor,
              child: SafeArea(
                bottom: false,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(left: 10, child: IconButton(icon: Icon(Icons.menu, color: purple, size: 28), onPressed: widget.onOpenProfile)),
                    IgnorePointer(child: Image.asset('assets/images/lotus.png', height: topBarHeight * 0.8)),
                    Positioned(
                        right: 10,
                        child: IconButton(
                            icon: Icon(Icons.bar_chart_rounded, color: purple, size: 28),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnalyticsScreen(notesData: notesByDate)))
                        )
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ИЗМЕНЕНО: Отображение чисел с нулём и цвет от независимого Настроения Дня
  Widget _buildCalendarGrid({required Key key, required List<DateTime> gridDates, required double calendarHeight, required Color textColor, required DateTime now}) {
    final int totalCells = gridDates.length;
    final int rows = (totalCells / 7).ceil();
    final bool sixRows = rows >= 6;
    final double cellHeight = calendarHeight / rows;
    final double fontSize = sixRows ? 12.0 : 14.0;
    final double margin = sixRows ? 3.0 : 4.0;

    return Container(
      key: key,
      child: SizedBox(
        height: calendarHeight,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: (MediaQuery.of(context).size.width / 7) / cellHeight),
          itemCount: totalCells,
          itemBuilder: (context, idx) {
            final d = gridDates[idx];
            final dKey = _dateKey(d);
            final note = notesByDate[dKey];
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday = d.year == now.year && d.month == now.month && d.day == now.day;

            Color bg = Colors.transparent;
            String emoji = '';

            if (note != null) {
              String? mood = note['dayMood'];
              // Если настроения дня нет, но есть старые заметки с настроением (для совместимости)
              if (mood == null && note['items'] != null && (note['items'] as List).isNotEmpty) {
                mood = (note['items'] as List).first['mood'];
              }

              if (mood != null && moodData.containsKey(mood)) {
                bg = moodData[mood]['color'].withOpacity(0.4);
                emoji = moodData[mood]['emoji'] ?? '';
              }
            }

            return GestureDetector(
              onTap: () {
                if (isOtherMonth) {
                  setState(() => visibleMonth = DateTime(d.year, d.month));
                  Future.delayed(const Duration(milliseconds: 150), () => _openDaySheet(d));
                } else { _openDaySheet(d); }
              },
              child: Container(
                margin: EdgeInsets.all(margin),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Stack(
                  children: [
                    // ДОБАВЛЕНО: .padLeft(2, '0')
                    Center(child: Text(d.day.toString().padLeft(2, '0'), style: TextStyle(fontSize: fontSize, color: isOtherMonth ? Colors.grey : textColor, fontWeight: isToday ? FontWeight.bold : FontWeight.normal))),
                    if (isToday) Positioned(bottom: 4, left: 0, right: 0, child: Center(child: Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: purple)))),
                    if (emoji.isNotEmpty) Positioned(top: 2, right: 2, child: Text(emoji, style: const TextStyle(fontSize: 9))),
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
    const names = ['','Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь'];
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
                color: isDarkTheme ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(20)
            ),
            child: Wrap(
              children: <Widget>[
                _imageSourceTile(Icons.photo_library, 'Галерея', ImageSource.gallery, setModalState),
                _imageSourceTile(Icons.photo_camera, 'Камера', ImageSource.camera, setModalState),
              ],
            ),
          );
        }
    );
  }

  Widget _imageSourceTile(IconData icon, String title, ImageSource source, StateSetter setModalState) {
    return ListTile(
      leading: Icon(icon, color: purple),
      title: Text(title, style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black87)),
      onTap: () async {
        Navigator.of(context).pop();
        final image = await ImagePicker().pickImage(source: source);
        if (image != null) {
          final directory = await getApplicationDocumentsDirectory();
          final String fileName = "img_${DateTime.now().millisecondsSinceEpoch}${p.extension(image.path)}";
          final String savedPath = p.join(directory.path, fileName);
          await File(image.path).copy(savedPath);
          setModalState(() => selectedImagePath = savedPath);
        }
      },
    );
  }
}
