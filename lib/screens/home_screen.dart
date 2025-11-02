// lib/screens/home_screen.dart
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

  // bottom nav
  int _selectedIndex = 0;

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

    // load notes
    final keys = prefs.getKeys();
    final Map<String, Map<String, dynamic>> tmp = {};
    for (final k in keys) {
      if (k.startsWith('note_')) {
        try {
          final raw = prefs.getString(k);
          if (raw != null) {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final dateKey = k.substring(5);
            tmp[dateKey] = {
              'text': map['text'] ?? '',
              'createdAt': map['createdAt'] ?? '',
            };
          }
        } catch (_) {}
      }
    }
    setState(() => notesByDate = tmp);
  }

  Future<void> _saveNoteForDay(DateTime day, String text) async {
    final prefs = await _prefs();
    final key = _dateKey(day);
    final nowIso = DateTime.now().toIso8601String();
    final data = jsonEncode({'text': text, 'createdAt': nowIso});
    await prefs.setString('note_$key', data);
    // award points only once per date: check flag
    final awardedKey = 'points_awarded_$key';
    final alreadyAwarded = prefs.getBool(awardedKey) ?? false;

    // award only if note created today (same date) and not already awarded
    final createdAt = DateTime.now();
    final sameDay = createdAt.year == day.year && createdAt.month == day.month && createdAt.day == day.day;

    if (!alreadyAwarded && sameDay) {
      userPoints += 1; // simple +1; can be extended to multiplier logic
      await prefs.setInt('user_points', userPoints);
      await prefs.setBool(awardedKey, true);
    }

    setState(() {
      notesByDate[key] = {'text': text, 'createdAt': nowIso};
    });
  }

  Future<void> _deleteNoteForDay(DateTime day) async {
    final prefs = await _prefs();
    final key = _dateKey(day);
    await prefs.remove('note_$key');
    // Note: don't remove awarded flag -> prevents re-awarding on re-create the same day
    setState(() => notesByDate.remove(key));
  }

  // ------------------- Calendar helpers -------------------
  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  // Build grid (Monday first)
  List<DateTime> _buildGridDates(DateTime month) {
    final first = _firstDayOfMonth(month);
    // weekday: Mon=1..Sun=7; we want Mon..Sun
    final int startOffset = first.weekday - 1; // 0 if Mon, 6 if Sun
    final total = 42; // 6 rows x 7 cols
    final List<DateTime> dates = List.generate(total, (i) {
      final dayIndex = i - startOffset;
      return DateTime(month.year, month.month, 1).add(Duration(days: dayIndex));
    });
    return dates;
  }

  // ------------------- UI: Day sheet -------------------
  void _openDaySheet(DateTime day) {
    final key = _dateKey(day);
    final existing = notesByDate[key];
    final textController = TextEditingController(text: existing != null ? existing['text'] as String : '');
    bool hasUnsavedChanges = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async {
            if (hasUnsavedChanges && textController.text.trim().isNotEmpty && (existing == null || existing['text'] != textController.text.trim())) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dctx) => AlertDialog(
                  title: const Text('Вы не сохранили заметку'),
                  content: const Text('При выходе изменения не будут сохранены. Вы хотите выйти?'),
                  actionsAlignment: MainAxisAlignment.start,
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Да')),
                    TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Нет')),
                  ],
                ),
              );
              return confirm == true;
            }
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
                          IconButton(icon: Icon(Icons.close, color: purple), onPressed: () async {
                            // ask if unsaved changes
                            if (hasUnsavedChanges && textController.text.trim().isNotEmpty && (existing == null || existing['text'] != textController.text.trim())) {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (dctx) => AlertDialog(
                                  title: const Text('Вы не сохранили заметку'),
                                  content: const Text('При выходе изменения не будут сохранены. Вы хотите выйти?'),
                                  actionsAlignment: MainAxisAlignment.start,
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Да')),
                                    TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Нет')),
                                  ],
                                ),
                              );
                              if (confirm == true) Navigator.pop(context);
                            } else {
                              Navigator.pop(context);
                            }
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textController,
                        maxLines: 8,
                        onChanged: (_) => hasUnsavedChanges = true,
                        decoration: InputDecoration(
                          hintText: 'Напишите что-то хорошее, что произошло...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Сохранить', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: purple),
                            onPressed: () async {
                              final text = textController.text.trim();
                              if (text.isEmpty) {
                                // nothing to save
                                Navigator.pop(context);
                                return;
                              }
                              await _saveNoteForDay(day, text);
                              Navigator.pop(context);
                            },
                          ),
                          const SizedBox(width: 12),
                          if (existing != null)
                            OutlinedButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dctx) => AlertDialog(
                                    title: const Text('Удалить заметку?'),
                                    content: const Text('Вы действительно хотите удалить заметку?'),
                                    actionsAlignment: MainAxisAlignment.start,
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Да')),
                                      TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Нет')),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await _deleteNoteForDay(day);
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text('Удалить'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Builder(builder: (c) {
                        final note = notesByDate[_dateKey(day)];
                        if (note == null) return const SizedBox.shrink();
                        final createdAt = DateTime.tryParse(note['createdAt'] as String? ?? '');
                        if (createdAt == null) return const SizedBox.shrink();
                        final sameDay = createdAt.year == day.year && createdAt.month == day.month && createdAt.day == day.day;
                        return Text(
                          sameDay ? 'Эта запись учтена для сегодняшних очков.' : 'Эта запись НЕ была создана в этот день — очки не начисляются.',
                          style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black87),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
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

    return Scaffold(
      backgroundColor: bgColor,
        body: Stack(
            children: [
        SafeArea(
        child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
              // Top bar
              Container(
                height: 100,
                color: cardColor,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // menu
                    IconButton(
                      icon: Icon(Icons.menu, color: purple, size: 30),
                      onPressed: () => setState(() => isProfileOpen = true),
                    ),
                    const Spacer(),
                    Image.asset('assets/images/lotus.png', height: 60),
                    const Spacer(),
                    // star + points button
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

              const SizedBox(height: 10),

              // Greeting card
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
                      Text('Welcome', style: TextStyle(color: purple, fontSize: 26, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Добро пожаловать, $fullName', style: TextStyle(fontSize: 16, color: textColor)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Calendar
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
                      // header with month navigation
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() => visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1)),
                          ),
                          Expanded(child: Center(child: Text('${_monthName(visibleMonth.month)} ${visibleMonth.year}', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)))),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() => visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // days of week header (Mon..Sun)
                      Row(
                        children: ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'].map((d) {
                          final isWeekend = d == 'Сб' || d == 'Вс';
                          return Expanded(child: Center(child: Text(d, style: TextStyle(color: isWeekend ? purple : textColor, fontWeight: FontWeight.w600))));
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      // grid
                      SizedBox(
                        height: 260,
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.0),
                          itemCount: gridDates.length,
                          itemBuilder: (context, idx) {
                            final d = gridDates[idx];
                            final dKey = _dateKey(d);
                            final note = notesByDate[dKey];
                            // days from other months: gray
                            final isOtherMonth = d.month != visibleMonth.month;
                            // today highlight
                            final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
                            // note style: if note exists and note.createdAt matches date -> strong highlight,
                            // if note exists but createdAt differs -> light highlight
                            Color bg = Colors.transparent;
                            if (note != null) {
                              final created = DateTime.tryParse(note['createdAt'] as String? ?? '');
                              if (created != null && created.year == d.year && created.month == d.month && created.day == d.day) {
                                bg = purple.withOpacity(0.45);
                              } else {
                                bg = purple.withOpacity(0.22);
                              }
                            }
                            return GestureDetector(
                              onTap: () {
                                // if tapped day belongs to another month -> switch month
                                if (isOtherMonth) {
                                  setState(() => visibleMonth = DateTime(d.year, d.month));
                                  // open after small delay to allow month switch UI update
                                  Future.delayed(const Duration(milliseconds: 150), () => _openDaySheet(d));
                                } else {
                                  _openDaySheet(d);
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  children: [
                                    Center(child: Text('${d.day}', style: TextStyle(color: isOtherMonth ? Colors.grey : textColor))),
                                    if (isToday) Positioned(top: 4, right: 4, child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: purple))),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // breathing card
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
  final AnimationController animation;
  const _BreathingFull({required this.controller, required this.animation, super.key});

  @override
  State<_BreathingFull> createState() => _BreathingFullState();
}

class _BreathingFullState extends State<_BreathingFull> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    // animation already controlled by parent (breathController)
    widget.animation.repeat();
  }

  @override
  void dispose() {
    widget.animation.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.9;
    return SizedBox(
      width: size,
      height: size * 0.6,
      child: Stack(
        children: [
          Center(child: CustomPaint(size: Size(size, size*0.5), painter: _BreathPathPainter(color: widget.controller.purple))),
          AnimatedBuilder(
            animation: widget.animation,
            builder: (context, _) {
              final t = widget.animation.value; // 0..1
              final w = size; final h = size*0.5;
              Offset p;
              if (t < 0.33) {
                final local = t/0.33;
                p = Offset(w*0.0 + (w*0.5 - 0.0)*local, h*0.7 - (h*0.5)*local);
              } else if (t < 0.66) {
                final local = (t-0.33)/0.33;
                p = Offset(w*0.5 + (w*0.9 - w*0.5)*local, h*0.2 + (h*0.5)*local);
              } else {
                final local = (t-0.66)/0.34;
                p = Offset(w*0.9 + (w - w*0.9)*local, h*0.7 - (h*0.1)*local);
              }
              return Positioned(left: p.dx-10, top: p.dy-10, child: Container(width:20, height:20, decoration: BoxDecoration(color: widget.controller.purple, shape: BoxShape.circle)));
            },
          ),
          Positioned(top: 8, right: 16, child: Container(
            padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
            child: const Text('00:45', style: TextStyle(color: Colors.white, fontSize: 12)),
          )),
          Positioned(bottom: 16, left: 0, right: 0, child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: widget.controller.purple, borderRadius: BorderRadius.circular(12)),
              child: Text('Стоп', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          )),
        ],
      ),
    );
  }
}
