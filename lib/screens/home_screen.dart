// lib/screens/home_screen.dart
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'breathing_screen.dart';
import 'SpecialistSelectionScreen.dart';
import 'chat_screen.dart';
import 'plan_screen.dart';
import 'shop_placeholder_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenProfile;
  const HomeScreen({required this.onOpenProfile, super.key});

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

  bool saving = false;

  // calendar/notes
  Map<String, Map<String, dynamic>> notesByDate = {}; // key: 'YYYY-MM-DD' -> {'text', 'createdAt'}
  late DateTime visibleMonth; // used to show month in calendar

  String formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      String two(int n) => n.toString().padLeft(2, '0');

      return "${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}";
    } catch (_) {
      return iso;
    }
  }

  // bottom nav (kept for completeness)
  int _selectedIndex = 0;

  // Calendar animation helpers
  int _calendarSlideDirection = 0; // -1 = to left (prev), +1 = to right (next)
  final _monthSwitcherKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    visibleMonth = DateTime.now();
    _loadAll();
    // system UI transparent nav bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
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
  Future<String> _addNoteForDay(DateTime day, String text) async {
    final prefs = await _prefs();
    final key = _notesKeyForDate(day);

    final nowIso = DateTime.now().toIso8601String();
    final newId = _noteId();

    final newNote = {'id': newId, 'text': text, 'createdAt': nowIso};

    // читаем старые заметки
    final raw = prefs.getString(key);
    List<dynamic> arr = [];
    if (raw != null) {
      try {
        arr = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        arr = [];
      }
    }

    // добавляем новую
    arr.add(newNote);

    // сохраняем
    await prefs.setString(key, jsonEncode(arr));

    // -------------- начисление поинтов --------------
    final awardedKey = 'points_awarded_${_dateKey(day)}';
    final alreadyAwarded = prefs.getBool(awardedKey) ?? false;
    final createdAt = DateTime.now();
    final sameDay =
        createdAt.year == day.year &&
            createdAt.month == day.month &&
            createdAt.day == day.day;

    if (!alreadyAwarded && sameDay) {
      userPoints += 1;
      await prefs.setInt('user_points', userPoints);
      await prefs.setBool(awardedKey, true);
    }

    // ⚠️ ВАЖНО: НЕ ДЕЛАТЬ setState() ЗДЕСЬ!

    return newId;
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
    } catch (_) {
      return;
    }

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

    // ⚠️ ВАЖНО: ТУТ ТОЖЕ НЕ ДЕЛАЕМ setState()
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
    // создаём локальную копию списка заметок (будем модифицировать)
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        existing != null && existing['items'] != null ? existing['items'] as List : []);

    final newController = TextEditingController();
    String? editingId;

    bool saving = false; // блокировка кнопки сохранения
    bool confirmShown = false; // чтобы диалог не показывался дважды
    String? newlyAddedId; // id заметки, которая только что добавлена (для анимации)

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // НЕ закрываем по тапу вне и по свайпу — это предотвращает потерю незасэйвенной заметки.
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setModalState) {
          // локальные флаги для модалки


          void refreshFromMemory() {
            final mem = notesByDate[dateKey];
            setModalState(() {
              items.clear();
              if (mem != null && mem['items'] != null) {
                items.addAll((mem['items'] as List).map((e) => Map<String, dynamic>.from(e)));
              }
            });
          }

          return WillPopScope(
            onWillPop: () async {
              // перехват аппаратной кнопки "назад"
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
              onTap: () {}, // не закрываем по тапу
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
                        // header
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Записи на ${day.day}.${day.month}.${day.year}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkTheme ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: purple),
                              onPressed: () async {
                                if (!confirmShown && newController.text.trim().isNotEmpty && editingId == null) {
                                  confirmShown = true;
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text("Закрыть без сохранения?"),
                                      content: const Text("Текущая заметка не сохранена."),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
                                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Закрыть")),
                                      ],
                                    ),
                                  );
                                  confirmShown = false;
                                  if (confirm != true) return;
                                }
                                Navigator.of(ctx).pop(); // корректно закрываем
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // input area: height smaller / nicer
                        TextField(
                          controller: newController,
                          maxLines: 3, // <-- здесь можно поменять высоту
                          minLines: 2,
                          decoration: InputDecoration(
                            hintText: editingId == null ? 'Напишите новую заметку...' : 'Редактирование заметки...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), // радиус поля
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), // <-- тут можно поменять высоту внутреннего отступа
                            filled: true,
                            fillColor: isDarkTheme ? Colors.grey[850] : Colors.grey[100],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // save button row
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check, color: Colors.white),
                              label: const Text("Сохранить", style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(backgroundColor: purple),
                              onPressed: () async {
                                final txt = newController.text.trim();
                                if (txt.isEmpty) return;

                                if (editingId == null) {
                                  // ---------- СОЗДАНИЕ НОВОЙ ЗАМЕТКИ ----------
                                  final id = await _addNoteForDay(day, txt);

                                  final newItem = {
                                    "id": id,
                                    "text": txt,
                                    "createdAt": DateTime.now().toIso8601String(),
                                  };

                                  // новые заметки сверху
                                  items.insert(0, newItem);

                                  // обновление глобального кэша (обязательно!)
                                  notesByDate[dateKey] = {
                                    "items": List<Map<String, dynamic>>.from(items),
                                    "text": items.first["text"] ?? "",
                                    "createdAt": items.first["createdAt"] ?? "",
                                  };

                                  newlyAddedId = id;
                                  newController.clear(); // очистка поля ввода
                                }
                                else {
                                  // ------------- РЕДАКТИРОВАНИЕ -------------
                                  await _updateNoteForDay(day, editingId!, txt);

                                  final idx = items.indexWhere((e) => e["id"] == editingId);
                                  if (idx != -1) {
                                    items[idx]["text"] = txt;
                                    items[idx]["createdAt"] = DateTime.now().toIso8601String();
                                  }

                                  // обновление глобального кэша
                                  notesByDate[dateKey] = {
                                    "items": List<Map<String, dynamic>>.from(items),
                                    "text": items.first["text"] ?? "",
                                    "createdAt": items.first["createdAt"] ?? "",
                                  };

                                  editingId = null;
                                  newController.clear(); // ←←← САМОЕ ВАЖНОЕ!
                                }

                                if (context.mounted) setModalState(() {});
                                if (mounted) setState(() {});

                                Future.delayed(const Duration(milliseconds: 700), () {
                                  if (context.mounted) {
                                    setModalState(() => newlyAddedId = null);
                                  }
                                });
                              },
                            ),

                            const SizedBox(width: 12),

                            if (editingId != null)
                              OutlinedButton(
                                onPressed: () {
                                  editingId = null;
                                  newController.clear();
                                  setModalState(() {});
                                },
                                child: const Text('Отмена'),
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // list of notes — с анимацией для только что добавленной
                        if (items.isEmpty)
                          Text('Заметок пока нет.', style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54))
                        else
                          Column(
                            children: items.map((note) {
                              final id = note['id']?.toString() ?? '';
                              final text = note['text']?.toString() ?? '';
                              final createdAt = note['createdAt']?.toString() ?? '';

                              final bool isNew = (id == newlyAddedId);

                              final Widget card = Card(
                                color: isDarkTheme ? Colors.grey[850] : Colors.white,
                                child: ListTile(
                                  title: Text(
                                    text,
                                    style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black87),
                                  ),
                                  subtitle: Text(
                                    formatDate(createdAt),
                                    style: TextStyle(fontSize: 11, color: isDarkTheme ? Colors.white60 : Colors.black54),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // ---- EDIT ----
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.deepPurple),
                                        onPressed: () {
                                          editingId = id;
                                          newController.text = text;
                                          setModalState(() {});
                                        },
                                      ),

                                      // ---- DELETE ----
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent),
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

                                            notesByDate[dateKey] = {
                                              "items": List<Map<String, dynamic>>.from(items),
                                              "text": items.isNotEmpty ? items.first["text"] : "",
                                              "createdAt": items.isNotEmpty ? items.first["createdAt"] : "",
                                            };

                                            if (editingId == id) {
                                              editingId = null;
                                              newController.clear();
                                            }

                                            setModalState(() {});
                                            if (mounted) setState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              if (!isNew) return card;

                              // ---- АНІМАЦИЯ: Появление сверху ----
                              return TweenAnimationBuilder<double>(
                                key: ValueKey(id),
                                tween: Tween(begin: -20.0, end: 0.0),
                                duration: const Duration(milliseconds: 350),
                                builder: (context, value, child) {
                                  return Transform.translate(
                                    offset: Offset(0, value),
                                    child: Opacity(opacity: 1 - (value.abs() / 20), child: child),
                                  );
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
    final double topBarHeight = 85; // <-- регулируй высоту верхней плашки
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
                              'Здравствуйте, $fullName',
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
                                      duration: const Duration(milliseconds: 1100),
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
                                  duration: const Duration(milliseconds: 1100),
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

                    // breathing card (updated)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const BreathingScreen()),
                          );
                        },
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
                              SizedBox(
                                width: 65,
                                height: 65,
                                child: Image.asset(
                                  'assets/images/meditation.png',
                                  fit: BoxFit.contain,
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Быстрая дыхательная практика',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Короткая практика для снижения стресса',
                                      style: TextStyle(color: textColor, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),

                              Icon(Icons.play_circle_fill, color: purple, size: 36),
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

          // ---------- FIXED TOP BAR (CENTERED LOTUS) ----------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: topBarHeight,
              color: cardColor,
              child: SafeArea(
                bottom: false,
                child: Stack(
                  alignment: Alignment.center,
                  children: [

                    // ------------- ROW (menu + points) -------------
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.menu, color: purple, size: 28),
                          onPressed: widget.onOpenProfile, // просто вызываем колбэк родителя
                        ),

                        const Spacer(),

                        Padding(
                          padding: const EdgeInsets.only(right: 8), // ← регулируешь тут
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ShopPlaceholderScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 5,
                                    offset: Offset(2, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.star, color: purple, size: 22),
                                  const SizedBox(width: 5),
                                  Text(
                                    '$userPoints',
                                    style: TextStyle(
                                      color: purple,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      ],
                    ),

                    // ------------- ABSOLUTELY CENTERED LOTUS -------------
                    IgnorePointer(
                      child: Image.asset(
                        'assets/images/lotus.png',
                        height: topBarHeight * 49,
                      ),
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