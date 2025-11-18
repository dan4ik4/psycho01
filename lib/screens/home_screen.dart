// lib/screens/home_screen.dart
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_screen.dart';
import 'chat_screen.dart';
import 'plan_screen.dart';
import 'shop_placeholder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Theme & colors
  bool isDarkTheme = false;
  final Color purple = const Color(0xFF5E3B8C);
  final Color darkWhite = const Color(0xFFF2F2F2);
  final Color pureWhite = Colors.white;

  // UI state
  bool isProfileOpen = false;
  bool isShopOpen = false; // not used as panel - shop has its own screen
  int userPoints = 0;
  String fullName = 'Пользователь';

  // calendar/notes
  Map<String, Map<String, dynamic>> notesByDate = {}; // key: 'YYYY-MM-DD' -> {'text', 'createdAt'}
  late DateTime visibleMonth; // used to show month in calendar

  // breathing animation
  late AnimationController breathController;

  // bottom nav (kept for completeness)
  int _selectedIndex = 0;

  // Calendar animation helpers
  int _calendarSlideDirection = 0; // -1 = to left (prev), +1 = to right (next)
  final _monthSwitcherKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    visibleMonth = DateTime.now();
    breathController = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    breathController.repeat(reverse: true);
    _loadAll();
    // system UI transparent nav bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  @override
  void dispose() {
    breathController.dispose();
    super.dispose();
  }

  // ------------------- Storage helpers -------------------
  String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
// ------------------- Storage helpers (REPLACEMENT) -------------------

// Note data model helper: each date key stores a list of note objects:
// {'id': '<uuid or timestamp>', 'text': '...', 'createdAt': 'iso'} stored as JSON array under 'notes_YYYY-MM-DD'
  String _notesKeyForDate(DateTime d) => 'notes_${_dateKey(d)}';

  Future<void> _loadAll() async {
    final prefs = await _prefs();
    setState(() {
      fullName = prefs.getString('full_name') ?? fullName;
      isDarkTheme = prefs.getBool('isDarkTheme') ?? false;
      userPoints = prefs.getInt('user_points') ?? 0;
    });

    // Try to get Supabase metadata if available (supersedes prefs)
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

    // load notes: now each key 'notes_YYYY-MM-DD' contains JSON array of notes
    final keys = prefs.getKeys();
    final Map<String, Map<String, dynamic>> tmp = {};
    for (final k in keys) {
      if (k.startsWith('notes_')) {
        try {
          final raw = prefs.getString(k);
          if (raw != null) {
            final List<dynamic> arr = jsonDecode(raw) as List<dynamic>;
            // store as map with dateKey -> {'items': [...]} to keep backward compatibility
            final dateKey = k.substring(6); // remove 'notes_'
            // keep only latest item for quick existing['text'] uses elsewhere (legacy), but store full list
            tmp[dateKey] = {
              'items': arr.map((e) => e as Map<String, dynamic>).toList(),
              // legacy compatibility: last created
              'text': arr.isNotEmpty ? (arr.last['text'] ?? '') : '',
              'createdAt': arr.isNotEmpty ? (arr.last['createdAt'] ?? '') : '',
            };
          }
        } catch (_) {}
      }
    }
    setState(() => notesByDate = tmp);
  }

// generate a simple unique id (timestamp based)
  String _noteId() => DateTime.now().microsecondsSinceEpoch.toString();

// Add a new note to a day
  Future<void> _addNoteForDay(DateTime day, String text) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);
    final nowIso = DateTime.now().toIso8601String();
    final newNote = {'id': _noteId(), 'text': text, 'createdAt': nowIso};
    final raw = prefs.getString(key);
    List<dynamic> arr = [];
    if (raw != null) {
      try {
        arr = jsonDecode(raw) as List<dynamic>;
      } catch (_) { arr = []; }
    }
    arr.add(newNote);
    await prefs.setString(key, jsonEncode(arr));

    // award points only once per date: check flag (keep original award logic)
    final awardedKey = 'points_awarded_${_dateKey(day)}';
    final alreadyAwarded = prefs.getBool(awardedKey) ?? false;
    final createdAt = DateTime.now();
    final sameDay = createdAt.year == day.year && createdAt.month == day.month && createdAt.day == day.day;
    if (!alreadyAwarded && sameDay) {
      userPoints += 1;
      await prefs.setInt('user_points', userPoints);
      await prefs.setBool(awardedKey, true);
    }

    // update in-memory map: store items + legacy fields
    final dateKey = _dateKey(day);
    final items = arr.map((e) => e as Map<String, dynamic>).toList();
    setState(() {
      notesByDate[dateKey] = {
        'items': items,
        'text': items.isNotEmpty ? (items.last['text'] ?? '') : '',
        'createdAt': items.isNotEmpty ? (items.last['createdAt'] ?? '') : '',
      };
    });
  }

// Update an existing note by id
  Future<void> _updateNoteForDay(DateTime day, String noteId, String newText) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);
    final raw = prefs.getString(key);
    if (raw == null) return;
    List<dynamic> arr;
    try {
      arr = jsonDecode(raw) as List<dynamic>;
    } catch (_) { return; }
    bool changed = false;
    for (var i = 0; i < arr.length; i++) {
      final n = arr[i] as Map<String, dynamic>;
      if (n['id'] == noteId) {
        n['text'] = newText;
        n['createdAt'] = DateTime.now().toIso8601String();
        arr[i] = n;
        changed = true;
        break;
      }
    }
    if (!changed) return;
    await prefs.setString(key, jsonEncode(arr));
    final dateKey = _dateKey(day);
    final items = arr.map((e) => e as Map<String, dynamic>).toList();
    setState(() {
      notesByDate[dateKey] = {
        'items': items,
        'text': items.isNotEmpty ? (items.last['text'] ?? '') : '',
        'createdAt': items.isNotEmpty ? (items.last['createdAt'] ?? '') : '',
      };
    });
  }

// Delete a note by id for a day (if noteId == null, delete all notes for that day)
  Future<void> _deleteNoteById(DateTime day, {String? noteId}) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);
    final raw = prefs.getString(key);
    if (raw == null) {
      // nothing to delete
      return;
    }
    List<dynamic> arr;
    try {
      arr = jsonDecode(raw) as List<dynamic>;
    } catch (_) { arr = []; }
    if (noteId == null) {
      // delete all
      await prefs.remove(key);
      setState(() => notesByDate.remove(_dateKey(day)));
      return;
    }
    final newArr = arr.where((e) => (e as Map<String, dynamic>)['id'] != noteId).toList();
    if (newArr.isEmpty) {
      await prefs.remove(key);
      setState(() => notesByDate.remove(_dateKey(day)));
      return;
    }
    await prefs.setString(key, jsonEncode(newArr));
    final dateKey = _dateKey(day);
    setState(() {
      notesByDate[dateKey] = {
        'items': newArr.map((e) => e as Map<String, dynamic>).toList(),
        'text': newArr.isNotEmpty ? (newArr.last['text'] ?? '') : '',
        'createdAt': newArr.isNotEmpty ? (newArr.last['createdAt'] ?? '') : '',
      };
    });
  }

  // ------------------- Calendar helpers -------------------
  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  // Build grid (Monday first) — keep original logic but we will display only first 35 items (5 rows)
  List<DateTime> _buildGridDates(DateTime month) {
    final first = _firstDayOfMonth(month);
    final int startOffset = (first.weekday - 1); // Monday=0

    // первая дата сетки (понедельник первой недели)
    final DateTime gridStart = DateTime(month.year, month.month, 1).subtract(Duration(days: startOffset));

    // сгенерируем 6 недель (макс)
    final all = List<DateTime>.generate(42, (i) => gridStart.add(Duration(days: i)));

    // разобьём по неделям
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) {
      weeks.add(all.sublist(i, i + 7));
    }

    // удаляем недели, где нет ни одного дня текущего месяца
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));

    // возвращаем сплющенный список (4/5/6 строки)
    return weeks.expand((w) => w).toList();
  }


  // function to change visibleMonth with direction (for animation)
  void _changeMonth({required int delta}) {
    setState(() {
      _calendarSlideDirection = delta > 0 ? 1 : -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }
// ------------------- UI: Day sheet (REPLACEMENT, supports multiple notes) -------------------
  void _openDaySheet(DateTime day) {
    final dateKey = _dateKey(day);
    final existing = notesByDate[dateKey];
    final List<Map<String, dynamic>> items = List<Map<String,dynamic>>.from(existing != null && existing['items'] != null ? existing['items'] as List : []);
    // controller used for new note / editing
    final newController = TextEditingController();
    String? editingId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setModalState) {
          void refreshFromMemory() {
            final mem = notesByDate[dateKey];
            setModalState(() {
              items.clear();
              if (mem != null && mem['items'] != null) {
                final list = mem['items'] as List;
                items.addAll(list.map((e) => Map<String,dynamic>.from(e as Map)));
              }
            });
          }

          return WillPopScope(
            onWillPop: () async {
              // no special unsaved check for list mode
              return true;
            },
            child: GestureDetector(
              onTap: () {}, // prevent closing by tapping sheet itself
              child: DraggableScrollableSheet(
                initialChildSize: 0.65,
                minChildSize: 0.3,
                maxChildSize: 0.95,
                builder: (context, scrollController) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.grey[900] : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Записи на ${day.day}.${day.month}.${day.year}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkTheme ? Colors.white : Colors.black87))),
                            IconButton(icon: Icon(Icons.close, color: purple), onPressed: () => Navigator.pop(ctx)),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // input area: either new note or editing existing
                        TextField(
                          controller: newController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: editingId == null ? 'Напишите новую заметку...' : 'Редактирование заметки...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: Text(editingId == null ? 'Добавить' : 'Сохранить'),
                              style: ElevatedButton.styleFrom(backgroundColor: purple),
                              onPressed: () async {
                                final txt = newController.text.trim();
                                if (txt.isEmpty) return;
                                if (editingId == null) {
                                  await _addNoteForDay(day, txt);
                                } else {
                                  await _updateNoteForDay(day, editingId!, txt);
                                  editingId = null;
                                }
                                // сразу обновляем локальный список и UI модального окна:
                                newController.clear();
                                // refreshFromMemory использует setModalState() — вызываем её для немедленного обновления
                                refreshFromMemory();
                                // небольшая анимация фокуса/пульсации (необязательно), но можно сделать setModalState пустым вызовом:
                                // setModalState((){});
                              },

                            ),
                            const SizedBox(width: 12),
                            if (editingId != null)
                              OutlinedButton(
                                onPressed: () {
                                  editingId = null;
                                  newController.clear();
                                  setModalState((){});
                                },
                                child: const Text('Отмена'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // list of notes
                        if (items.isEmpty) ...[
                          Text('Заметок пока нет.', style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                        ] else
                          Column(
                            children: items.reversed.map((note) {
                              final id = note['id']?.toString() ?? '';
                              final text = note['text']?.toString() ?? '';
                              final createdAt = note['createdAt']?.toString() ?? '';
                              return Card(
                                color: isDarkTheme ? Colors.grey[850] : Colors.white,
                                child: ListTile(
                                  title: Text(text, style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black87)),
                                  subtitle: Text(createdAt, style: TextStyle(fontSize: 11, color: isDarkTheme ? Colors.white60 : Colors.black54)),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: purple),
                                      onPressed: () {
                                        editingId = id;
                                        newController.text = text;
                                        setModalState((){});
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.redAccent),
                                      onPressed: () async {
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (dctx) => AlertDialog(
                                            title: const Text('Удалить заметку?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Нет')),
                                              TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Да')),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          await _deleteNoteById(day, noteId: id);
                                          refreshFromMemory();
                                        }
                                      },
                                    ),
                                  ]),
                                  onTap: () {
                                    // quick edit on tap
                                    editingId = id;
                                    newController.text = text;
                                    setModalState((){});
                                  },
                                ),
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
        });
      },
    ).whenComplete(() => setState(() {}));
  }

  // ------------------- Breathing overlay -------------------
  void _openBreathOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async {
            return true;
          },
          child: Scaffold(
            backgroundColor: Colors.black54,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(child: _BreathingFull(controller: this, animation: breathController)),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------- UI build -------------------
  @override
  Widget build(BuildContext context) {
    final Color bgColor = isDarkTheme ? const Color(0xFF121212) : darkWhite;
    final Color cardColor = isDarkTheme ? const Color(0xFF1E1E1E) : pureWhite;
    final Color textColor = isDarkTheme ? Colors.white : Colors.black87;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;

    final now = DateTime.now();
    final gridDates = _buildGridDates(visibleMonth);

    // panel width
    final panelWidth = MediaQuery.of(context).size.width * 0.8;

    // --------------------------
    // Настраиваемые параметры:
    // --------------------------
    final double topBarHeight = 72; // <-- регулируй высоту верхней плашки
    final double calendarHeight = 230; // <-- регулируй высоту календаря (5 строк)
    // --------------------------

    return Scaffold(
      backgroundColor: bgColor,
      // Мы используем Stack: верхняя плашка — Positioned (фикс.), контент — с отступом сверху.
      body: Stack(
        children: [
          // ---------- MAIN SCROLLABLE CONTENT ----------
          Positioned.fill(
            top: topBarHeight + 10, // контент начинается ниже закреплённой плашки
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 10),

                    // Greeting card (оставил без изменений)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Здравствуйте, $fullName 👋',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: purple,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Рады видеть вас снова!',
                              style: TextStyle(fontSize: 16, color: textColor),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Calendar container with swipe + arrow + animation
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: purple.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            // header with month navigation (AnimatedSwitcher)
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: () {
                                    _calendarSlideDirection = -1;
                                    _changeMonth(delta: -1);
                                  },
                                ),
                                Expanded(
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 1500),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) => currentChild ?? const SizedBox.shrink(),
                                      transitionBuilder: (Widget child, Animation<double> anim) {
                                        final offset = Tween<Offset>(
                                          begin: Offset(0.22 * _calendarSlideDirection, 0),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                                        return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                                      },
                                      child: Text(
                                        '${_monthName(visibleMonth.month)} ${visibleMonth.year}',
                                        key: ValueKey('${visibleMonth.month}_${visibleMonth.year}'),
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: textColor),
                                      ),
                                    ),

                                  ),
                                ),

                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: () {
                                    _calendarSlideDirection = 1;
                                    _changeMonth(delta: 1);
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            // days of week header (Mon..Sun) — оставил как есть
                            Row(
                              children: ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'].map((d) {
                                final isWeekend = d == 'Сб' || d == 'Вс';
                                return Expanded(child: Center(child: Text(d, style: TextStyle(color: isWeekend ? purple : textColor, fontWeight: FontWeight.w600))));
                              }).toList(),
                            ),

                            const SizedBox(height: 8),

                            // GRID with swipe detection and animated month change (we show exactly 35 cells = 5 rows)
                            GestureDetector(
                              onHorizontalDragEnd: (details) {
                                if (details.primaryVelocity == null) return;
                                if (details.primaryVelocity! < -200) {
                                  // swipe left -> next month
                                  _calendarSlideDirection = 1;
                                  _changeMonth(delta: 1);
                                } else if (details.primaryVelocity! > 200) {
                                  // swipe right -> prev month
                                  _calendarSlideDirection = -1;
                                  _changeMonth(delta: -1);
                                }
                              },
                              child: SizedBox(
                                height: calendarHeight,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 1500),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                                    // Чтобы не было видимого наложения старого и нового — показываем только текущий
                                    return currentChild ?? const SizedBox.shrink();
                                  },
                                  transitionBuilder: (Widget child, Animation<double> anim) {
                                    // лёгкое слайд+fade — без "следов"
                                    final offset = Tween<Offset>(
                                      begin: Offset(0.18 * _calendarSlideDirection, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));

                                    return ClipRect(           // обрезаем, чтобы не было артефактов при сдвиге
                                      child: SlideTransition(
                                        position: offset,
                                        child: FadeTransition(opacity: anim, child: child),
                                      ),
                                    );
                                  },
                                  child: _buildCalendarGrid(
                                    key: ValueKey<String>('grid_${visibleMonth.year}_${visibleMonth.month}_${gridDates.length}'),
                                    gridDates: gridDates,
                                    calendarHeight: calendarHeight,
                                    textColor: textColor,
                                    now: now,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // breathing card (untouched)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: _openBreathOverlay,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: purple.withOpacity(0.18)),
                          ),
                          child: Row(
                            children: [
                              CustomPaint(size: const Size(80,40), painter: _ProtoBreathPainter(color: purple)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Быстрая дыхательная практика', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                                  const SizedBox(height: 6),
                                  Text('Короткая практика для снижения стресса', style: TextStyle(color: textColor, fontSize: 12)),
                                ],
                              )),
                              Icon(Icons.play_circle_fill, color: purple, size: 36)
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

          // ---------- FIXED TOP BAR (ONLY ON THIS SCREEN) ----------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: topBarHeight,
              color: cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.menu, color: purple, size: 28),
                      onPressed: () => setState(() => isProfileOpen = true),
                    ),
                    // Spacer removed because we want perfect center for lotus — use Expanded + Stack to absolutely center
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // invisible row so left and right areas keep their sizes
                          Row(
                            children: [
                              const SizedBox(width: 48), // room for menu
                              const Spacer(),
                              const SizedBox(width: 110), // room for right widget
                            ],
                          ),
                          // centered lotus
                          Align(
                            alignment: Alignment.center,
                            child: Image.asset('assets/images/lotus.png', height: topBarHeight * 0.55),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopPlaceholderScreen()));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: const Offset(2,2))],
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.star, color: purple, size: 22),
                            const SizedBox(width: 6),
                            Text('$userPoints', style: TextStyle(color: purple, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --------------- profile drawer (overlay) ---------------
          if (isProfileOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(()=>isProfileOpen=false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                width: panelWidth,
                child: SafeArea(
                  child: Container(
                    color: cardColor,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // header: name + theme toggle
                        Row(
                          children: [
                            Expanded(child: Text(fullName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor))),
                            IconButton(icon: Icon(isDarkTheme ? Icons.wb_sunny : Icons.nightlight_round, color: purple), onPressed: () async {
                              final prefs = await _prefs();
                              prefs.setBool('isDarkTheme', !isDarkTheme);
                              setState(()=>isDarkTheme = !isDarkTheme);
                            }),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Пол: ---', style: TextStyle(color: textColor)),
                        Text('Возраст: ---', style: TextStyle(color: textColor)),
                        Text('Email: ---', style: TextStyle(color: textColor)),
                        const Spacer(),
                        OutlinedButton(onPressed: () {}, child: const Text('Настройки')),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
                            final prefs = await _prefs();
                            await prefs.clear();
                            if (context.mounted) Navigator.of(context).pushReplacementNamed('/');
                          },
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Выйти'),
                          style: ElevatedButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

// ----------------- Calendar grid builder (REPLACEMENT) -----------------
  Widget _buildCalendarGrid({
    required Key key,
    required List<DateTime> gridDates,
    required double calendarHeight,
    required Color textColor,
    required DateTime now,
  }) {
    final int totalCells = gridDates.length;            // 28..42 (на деле 28 редко)
    final int rows = (totalCells / 7).ceil();          // 4/5/6
    final bool sixRows = rows >= 6;
    final double cellHeight = calendarHeight / rows;
    final double fontSize = sixRows ? 12.0 : 14.0;     // уменьшаем, если 6 строк
    final double margin = sixRows ? 3.0 : 4.0;


    return Container(
      key: key,
      child: SizedBox(
        height: calendarHeight,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: (MediaQuery.of(context).size.width / 7) / cellHeight,
          ),
          itemCount: totalCells,
          itemBuilder: (context, idx) {
            final d = gridDates[idx];
            final dKey = _dateKey(d);
            final note = notesByDate[dKey];
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday = d.year == now.year && d.month == now.month && d.day == now.day;

            Color bg = Colors.transparent;
            if (note != null) {
              final created = DateTime.tryParse((note is Map && note['createdAt'] != null) ? note['createdAt'] as String : (note is Map && note['items'] != null ? (note['items'] as List).isNotEmpty ? (note['items'] as List).last['createdAt'] as String? : null : null) ?? '');
              if (created != null && created.year == d.year && created.month == d.month && created.day == d.day) {
                bg = purple.withOpacity(0.45);
              } else {
                bg = purple.withOpacity(0.22);
              }
            }

            return GestureDetector(
              onTap: () {
                if (isOtherMonth) {
                  setState(() => visibleMonth = DateTime(d.year, d.month));
                  Future.delayed(const Duration(milliseconds: 150), () => _openDaySheet(d));
                } else {
                  _openDaySheet(d);
                }
              },
              child: Container(
                margin: EdgeInsets.all(margin),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Center(child: Text('${d.day}', style: TextStyle(fontSize: fontSize, color: isOtherMonth ? Colors.grey : textColor))),
                    if (isToday) Positioned(top: 4, right: 4, child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: purple))),
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
}

// ----------------- Breathing custom painters & widget -----------------

class _ProtoBreathPainter extends CustomPainter {
  final Color color;
  _ProtoBreathPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path();
    path.moveTo(0, size.height*0.7);
    path.quadraticBezierTo(size.width*0.25, size.height*0.2, size.width*0.5, size.height*0.7);
    path.quadraticBezierTo(size.width*0.75, size.height*1.1, size.width, size.height*0.6);
    canvas.drawPath(path, paint);
    final dotPaint = Paint()..color=color;
    canvas.drawCircle(Offset(size.width*0.1, size.height*0.65), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BreathPathPainter extends CustomPainter {
  final Color color;
  _BreathPathPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color=color.withOpacity(0.9)..strokeWidth=4..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final path = Path();
    path.moveTo(0, size.height*0.7);
    path.quadraticBezierTo(size.width*0.25, size.height*0.2, size.width*0.5, size.height*0.7);
    path.quadraticBezierTo(size.width*0.75, size.height*1.05, size.width, size.height*0.6);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full breathing UI: moving dot along path and phase label
class _BreathingFull extends StatefulWidget {
  final _HomeScreenState controller;
  final AnimationController animation; // оставляем сигнатуру для совместимости
  const _BreathingFull({required this.controller, required this.animation, super.key});

  @override
  State<_BreathingFull> createState() => _BreathingFullState();
}

class _BreathingFullState extends State<_BreathingFull> with TickerProviderStateMixin {
  late AnimationController _ctrl; // управляет позицией шарика и таймером
  bool running = false;

  static const int totalSeconds = 57; // 3 cycles: 4+7+8 = 19 *3 =57
  // phases per cycle: [4 inhale, 7 hold, 8 exhale]
  final List<int> phaseDurations = [4, 7, 8];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: totalSeconds));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    if (running) return;
    setState(() => running = true);
    _ctrl.forward(from: 0.0).whenComplete(() {
      setState(() => running = false);
    });
  }

  void _stop() {
    if (!running) return;
    _ctrl.stop();
    setState(() => running = false);
  }

  // helper: compute progress on full 0..1 (0 start, 1 end)
  double get progress => _ctrl.value;

  // compute current local time in seconds (0..totalSeconds)
  double get secs => _ctrl.value * totalSeconds;

  // returns which phase index (0..2) within a cycle and which cycle
  Map<String,int> phaseInfo(double tSeconds) {
    final cycleLen = phaseDurations.reduce((a,b) => a+b);
    final cycleIndex = (tSeconds ~/ cycleLen);
    final inCycle = (tSeconds % cycleLen).toInt();
    int acc = 0;
    for (int i=0;i<phaseDurations.length;i++) {
      acc += phaseDurations[i];
      if (inCycle < acc) {
        return {'phase': i, 'cycle': cycleIndex};
      }
    }
    return {'phase': 1, 'cycle': cycleIndex};
  }

  // Compute world position of ball along polyline
  Offset _posAlongPath(Size size, double t) {
    // define points relative to size:
    final p0 = Offset(size.width * 0.08, size.height * 0.88);
    final p1 = Offset(size.width * 0.35, size.height * 0.28); // up-left -> up
    final p2 = Offset(size.width * 0.65, size.height * 0.28); // straight right
    final p3 = Offset(size.width * 0.92, size.height * 0.88); // down-right

    // lengths
    final l1 = (p1 - p0).distance;
    final l2 = (p2 - p1).distance;
    final l3 = (p3 - p2).distance;
    final total = l1 + l2 + l3;
    final dist = t * total;

    if (dist <= l1) {
      final local = dist / l1;
      return Offset.lerp(p0, p1, local)!;
    } else if (dist <= l1 + l2) {
      final local = (dist - l1) / l2;
      return Offset.lerp(p1, p2, local)!;
    } else {
      final local = (dist - l1 - l2) / l3;
      return Offset.lerp(p2, p3, local)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeW = MediaQuery.of(context).size.width * 0.9;
    final sizeH = sizeW * 0.6;
    return SizedBox(
      width: sizeW,
      height: sizeH,
      child: Stack(
        children: [
          // background path
          Positioned.fill(
            child: CustomPaint(
              painter: _BreathPathPainter(color: widget.controller.purple),
            ),
          ),

          // Moving ball + phase texts + circular timer:
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final localT = progress.clamp(0.0, 1.0);
              final pos = _posAlongPath(Size(sizeW, sizeH), localT);
              final double secondsNow = secs;
              final info = phaseInfo(secondsNow);
              final phase = info['phase'] ?? 1; // 0 inhale,1 hold,2 exhale

              // show text only during inhale(0) or exhale(2)
              String? phaseText;
              if (phase == 0) phaseText = 'Вдох';
              else if (phase == 2) phaseText = 'Выдох';
              else phaseText = null;

              // compute text fade/scale (smooth)
              double textOpacity = 0.0;
              double textScale = 1.0;
              if (phaseText != null) {
                // within current phase progress
                final cycleLen = phaseDurations.reduce((a,b)=>a+b);
                final inCycle = (secondsNow % cycleLen);
                // compute startSecond of this phase in cycle:
                int start = 0;
                for (int i=0;i<phase;i++) start += phaseDurations[i];
                final phaseElapsed = inCycle - start;
                final phaseLen = phaseDurations[phase];
                final p = (phaseElapsed / phaseLen).clamp(0.0, 1.0);
                // fade in first 15% and fade out last 15%
                if (p < 0.15) textOpacity = p / 0.15;
                else if (p > 0.85) textOpacity = (1 - p) / 0.15;
                else textOpacity = 1.0;
                textScale = 1.0 + 0.06 * (0.5 - (p - 0.5).abs()) * 2.0;
              }

              return Stack(
                children: [
                  // ball position
                  Positioned(
                    left: pos.dx - 12,
                    top: pos.dy - 12,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: widget.controller.purple,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0,3))],
                      ),
                    ),
                  ),

                  // phase text in center
                  if (phaseText != null)
                    Positioned.fill(
                      child: Center(
                        child: Opacity(
                          opacity: textOpacity,
                          child: Transform.scale(
                            scale: textScale,
                            child: Text(
                              phaseText,
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: widget.controller.purple.withOpacity(0.95)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // circular timer top-right
          Positioned(
            top: 8,
            right: 12,
            child: SizedBox(
              width: 56,
              height: 56,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final p = _ctrl.value.clamp(0.0, 1.0);
                  return CustomPaint(
                    painter: _BreathTimerPainter(color: widget.controller.purple, progress: p),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),

          // start/stop button bottom center
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: () {
                  if (!running) _start(); else _stop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.controller.purple,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(running ? 'Стоп' : 'Старт', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Painter for circular timer
class _BreathTimerPainter extends CustomPainter {
  final Color color;
  final double progress; // 0..1
  _BreathTimerPainter({required this.color, required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final bgPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, bgPaint);

    // white arc that grows counter-clockwise
    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: r - 4);
    // start at -90deg, sweep negative to draw CCW
    final sweep = -progress * 2 * 3.141592653589793;
    canvas.drawArc(rect, -3.141592653589793/2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _BreathTimerPainter old) => old.progress != progress || old.color != color;
}
