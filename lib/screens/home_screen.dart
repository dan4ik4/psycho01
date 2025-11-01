// lib/home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_screen.dart';
import 'chat_screen.dart';
import 'plan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

/// NOTE:
/// - This HomeScreen uses SharedPreferences to store:
///   - 'full_name' : string (user full name)
///   - 'note_YYYY-MM-DD' : json string { "text": "...", "createdAt": "ISO" }
/// - No external calendar package — simple month grid implemented here.
class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool isDarkMode = false;

  bool isProfileOpen = false;
  bool isNotificationsOpen = false;
  bool hasNotifications = true;

  final Color purple = const Color(0xFF5E3B8C);
  final Color darkWhite = const Color(0xFFF2F2F2);
  final Color pureWhite = Colors.white;

  // state
  String fullName = 'Пользователь';
  Map<String, Map<String, dynamic>> notesByDate = {}; // key: 'YYYY-MM-DD' -> {text, createdAt}

  // breathing animation
  bool breathingOpen = false;
  late AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _loadAll();
    // transparent nav bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      fullName = prefs.getString('full_name') ?? 'Пользователь';
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });

    // Try to get Supabase user metadata if available (prefer Supabase over prefs)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final meta = user.userMetadata ?? {};
        final supaName = (meta['full_name'] ?? meta['fullName'] ?? meta['name'])?.toString();
        if (supaName != null && supaName.isNotEmpty) {
          setState(() {
            fullName = supaName;
          });
        }
      }
    } catch (_) {
      // ignore if supabase not initialized
    }

    // load notes from prefs
    final keys = prefs.getKeys();
    for (final k in keys) {
      if (k.startsWith('note_')) {
        try {
          final raw = prefs.getString(k);
          if (raw != null) {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            notesByDate[k.substring(5)] = {
              'text': map['text'] ?? '',
              'createdAt': map['createdAt'] ?? '',
            };
          }
        } catch (_) {}
      }
    }
    setState(() {});
  }

  Future<void> _saveNoteForDay(DateTime day, String text) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dateKey(day);
    final nowIso = DateTime.now().toIso8601String();
    final data = jsonEncode({'text': text, 'createdAt': nowIso});
    await prefs.setString('note_$key', data);
    notesByDate[key] = {'text': text, 'createdAt': nowIso};
    setState(() {});
  }

  Future<void> _deleteNoteForDay(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dateKey(day);
    await prefs.remove('note_$key');
    notesByDate.remove(key);
    setState(() {});
  }

  String _dateKey(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Map<String,dynamic>? _noteForDay(DateTime day) {
    return notesByDate[_dateKey(day)];
  }

  // Helpers for calendar
  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  // open detail sheet for a day
  void _openDaySheet(DateTime day) {
    final key = _dateKey(day);
    final existing = _noteForDay(day);
    final textController = TextEditingController(text: existing != null ? existing['text'] as String : '');
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return GestureDetector(
            onTap: (){}, // prevent closing by tapping the sheet itself
            child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.95,
              builder: (context, controller) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[900] : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Записи на ${day.day}.${day.month}.${day.year}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87))),
                          IconButton(
                            icon: Icon(Icons.close, color: purple),
                            onPressed: () => Navigator.pop(context),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textController,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: 'Напишите что-то хорошее, что произошло сегодня...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Сохранить'),
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
                          if (existing != null) ...[
                            OutlinedButton(
                              onPressed: () async {
                                // confirm delete once
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Удалить заметку?'),
                                    content: const Text('Вы действительно хотите удалить заметку?'),
                                    actionsAlignment: MainAxisAlignment.start,
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogContext, true),
                                        child: const Text('Да'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogContext, false),
                                        child: const Text('Нет'),
                                      ),
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
                          ]
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Info about scoring
                      Builder(builder: (c) {
                        final note = _noteForDay(day);
                        if (note == null) return const SizedBox.shrink();
                        final createdAt = DateTime.tryParse(note['createdAt'] as String? ?? '');
                        if (createdAt == null) return const SizedBox.shrink();
                        final sameDay = createdAt.year==day.year && createdAt.month==day.month && createdAt.day==day.day;
                        return Text(
                          sameDay ? 'Эта запись учтена для сегодняшних очков.' : 'Эта запись НЕ была создана в этот день — очки не начисляются.',
                          style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87),
                        );
                      })
                    ],
                  ),
                ),
              ),
            ),
          );
        }
    ).whenComplete(() => setState((){}));
  }

  // Breathing overlay
  void _openBreathOverlay() {
    setState(() => breathingOpen = true);
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return WillPopScope(
            onWillPop: () async { setState(()=>breathingOpen=false); return true; },
            child: Scaffold(
              backgroundColor: Colors.black54,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: BreathingWidget(controller: _breathController, color: purple),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          setState(()=>breathingOpen=false);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
    ).whenComplete(() => setState(()=>breathingOpen=false));
  }

  // UI building
  @override
  Widget build(BuildContext context) {
    final Color bgColor = isDarkMode ? const Color(0xFF121212) : darkWhite;
    final Color cardColor = isDarkMode ? const Color(0xFF1E1E1E) : pureWhite;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;

    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom; // to avoid system nav overlap

    final now = DateTime.now();
    final firstOfMonth = _firstDayOfMonth(now);
    final daysInMonth = _daysInMonth(now);
    final firstWeekday = firstOfMonth.weekday % 7; // Sunday=0 .. Saturday=6 (make Sunday first)
    // build list of DateTimes for grid
    List<DateTime?> gridDates = List.filled(42, null);
    for (int i=0;i<daysInMonth;i++) {
      final pos = firstWeekday + i;
      gridDates[pos] = DateTime(now.year, now.month, i+1);
    }

    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Scaffold(
          key: ValueKey(isDarkMode),
          backgroundColor: bgColor,
          body: Stack(
            children: [
              Column(
                children: [
                  // top bar
                  Container(
                    height: 100,
                    color: cardColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.menu, color: purple, size: 30),
                          onPressed: () { setState(()=>isProfileOpen=true); },
                        ),
                        const Spacer(),
                        Image.asset('assets/images/lotus.png', height: 60),
                        const Spacer(),
                        Stack(
                          children: [
                            IconButton(
                              icon: Icon(Icons.notifications_none, color: purple, size: 30),
                              onPressed: () { setState(()=>isNotificationsOpen=true); },
                            ),
                            if (hasNotifications)
                              Positioned(
                                top: 6, right: 6,
                                child: Container(width:10, height:10, decoration: BoxDecoration(color: purple, shape: BoxShape.circle)),
                              ),
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  // logo higher + Welcome handled by top bar and greeting below
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

                  // Calendar widget area (calendar "Календарь позитивных моментов")
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: purple.withOpacity(0.08), // widget background colored
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text('Календарь позитивных моментов', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                              const Spacer(),
                              Text('${now.month}.${now.year}', style: TextStyle(color: textColor)),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // days of week header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: ['Вс','Пн','Вт','Ср','Чт','Пт','Сб'].map((d) =>
                                Expanded(child: Center(child: Text(d, style: TextStyle(color: textColor, fontSize: 12)))) )
                                .toList(),
                          ),
                          const SizedBox(height: 8),

                          // calendar grid
                          SizedBox(
                            height: 240,
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  childAspectRatio: 1.0
                              ),
                              itemCount: gridDates.length,
                              itemBuilder: (context, idx) {
                                final d = gridDates[idx];
                                if (d==null) return const SizedBox.shrink();
                                final note = _noteForDay(d);
                                // Determine decoration:
                                // - if note exists AND note.createdAt date == d -> mark as "today note" style A
                                // - if note exists but createdAt date != d -> style B
                                Color bg = Colors.transparent;
                                BoxBorder? border;
                                final isToday = d.year==now.year && d.month==now.month && d.day==now.day;
                                if (note!=null) {
                                  final created = DateTime.tryParse(note['createdAt'] as String? ?? '');
                                  if (created!=null && created.year==d.year && created.month==d.month && created.day==d.day) {
                                    bg = purple.withOpacity(0.45); // same-day note (strong highlight)
                                  } else {
                                    bg = purple.withOpacity(0.22); // note exists but created on different day (lighter)
                                  }
                                }
                                return GestureDetector(
                                  onTap: () => _openDaySheet(d),
                                  child: Container(
                                    margin: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Stack(
                                      children: [
                                        Center(child: Text('${d.day}', style: TextStyle(color: textColor))),
                                        if (isToday)
                                          Positioned(top:4, right:4, child: Container(width:6,height:6, decoration: BoxDecoration(shape:BoxShape.circle, color: purple))),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Quick breathing widget card (compact)
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
                            // simple icon representation of the "broken line"
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

                  const Spacer(),
                ],
              ),

              // ---------- REPLACED PROFILE DRAWER & OVERLAY ----------
              // 🟣 Профильная панель (перекрывает всё, включая нижнюю навигацию)
              if (isProfileOpen) ...[
                // Тёмный фон-затемнение
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => isProfileOpen = false),
                    child: Container(color: Colors.black.withOpacity(0.4)),
                  ),
                ),

                // Сама панель
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: 0, // 🟣 чтобы перекрывала всю ширину, включая нижнюю панель
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.8,
                    child: Container(
                      color: cardColor,
                      padding: const EdgeInsets.all(18),
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 🟣 Верхняя строка с именем и переключателем темы
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    fullName,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
                                    color: purple,
                                  ),
                                  onPressed: () async {
                                    setState(() => isDarkMode = !isDarkMode);
                                    final prefs = await SharedPreferences.getInstance();
                                    prefs.setBool('isDarkMode', isDarkMode);
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),
                            Text('Пол: ---', style: TextStyle(color: textColor)),
                            Text('Возраст: ---', style: TextStyle(color: textColor)),
                            Text('Email: ---', style: TextStyle(color: textColor)),

                            const Spacer(),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Настройки'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.clear();
                                setState(() {
                                  fullName = 'Пользователь';
                                });
                              },
                              child: const Text('Выйти'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // ---------- REPLACED NOTIFICATIONS PANEL ----------
              if (isNotificationsOpen) ...[
                // overlay that closes notifications when tapping outside
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(()=>isNotificationsOpen=false),
                    child: Container(color: Colors.black.withOpacity(0.05)),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  right: isNotificationsOpen ? 0 : -MediaQuery.of(context).size.width,
                  top: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: SafeArea(
                      child: Container(
                        color: cardColor,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(icon: Icon(Icons.arrow_back, color: purple), onPressed: ()=>setState(()=>isNotificationsOpen=false)),
                                const SizedBox(width: 8),
                                Text('Уведомления', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                const Spacer(),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(child: Center(child: Text('Уведомлений пока нет', style: TextStyle(color: textColor)))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // bottom navigation — raised above system nav
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset + 10.0), // raise above system nav
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0,2))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          icon: Icon(Icons.home, color: _selectedIndex==0 ? purple : Colors.grey),
                          onPressed: () { setState(()=>_selectedIndex=0); },
                        ),
                        // circular chat icon (message bubble circle with tail to the right)
                        GestureDetector(
                          onTap: ()=> setState(()=>_selectedIndex=1),
                          child: Container(
                            decoration: BoxDecoration(color: _selectedIndex==1 ? purple : Colors.white, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.message, color: _selectedIndex==1 ? Colors.white : Colors.grey, size: 28),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.person_outline, color: _selectedIndex==2 ? purple : Colors.grey),
                          onPressed: () { setState(()=>_selectedIndex=2); },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
    );
  }
}


/// Simple custom painter for the compact breathing preview (a broken line)
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
    // dot
    final dotPaint = Paint()..color=color;
    canvas.drawCircle(Offset(size.width*0.1, size.height*0.65), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full breathing widget — animates a dot along a path (simple)
class BreathingWidget extends StatefulWidget {
  final AnimationController controller;
  final Color color;
  const BreathingWidget({required this.controller, required this.color, super.key});
  @override
  State<BreathingWidget> createState() => _BreathingWidgetState();
}

class _BreathingWidgetState extends State<BreathingWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.repeat(reverse: true);
  }
  @override
  void dispose() {
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.9;
    return SizedBox(
      width: size,
      height: size*0.5,
      child: Stack(
        children: [
          Center(
            child: CustomPaint(
              size: Size(size, size*0.5),
              painter: _BreathPathPainter(color: widget.color),
            ),
          ),
          // moving dot using AnimatedBuilder
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) {
              final t = widget.controller.value; // 0..1
              // simple mapping along 3 segments
              final w = size;
              final h = size*0.5;
              // piecewise param
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
              return Positioned(left: p.dx-8, top: p.dy-8, child: Container(width:16, height:16, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)));
            },
          ),
          // small timer / label
          Positioned(top: 8, right: 16, child: Container(
            padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
            child: const Text('00:45', style: TextStyle(color: Colors.white, fontSize: 12)),
          ))
        ],
      ),
    );
  }
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
