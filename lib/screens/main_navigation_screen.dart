import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'SpecialistSelectionScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final Color purple = const Color(0xFF5E3B8C);
  final Color cardColor = const Color(0xFFF6F6FF);

  bool isProfileOpen = false; // <-- управление панелью настроек

  final List<Widget> _screensPlaceholder = []; // not used directly

  @override
  void initState() {
    super.initState();

    // Настраиваем цвет системной панели (фон кнопок "назад", "домой")
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: const Color(0xFFF6F6FF), // фон нижней панели
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent, // прозрачный верхний бар
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final double bottomBgHeight = 60; // настройка высоты
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // динамическая ширина панели настроек: 80% от ширины экрана
    final double panelWidth = MediaQuery.of(context).size.width * 0.8;

    // Список экранов: передаём колбэк открытия панели в HomeScreen
    final List<Widget> screens = [
      HomeScreen(onOpenProfile: () => setState(() => isProfileOpen = true)),
      ChatScreen(),
      SpecialistListScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          /// --- Основное содержимое ---
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.fastOutSlowIn,
            switchOutCurve: Curves.fastOutSlowIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0.15, 0.0),
                end: Offset.zero,
              ).animate(animation);

              return SlideTransition(
                position: slideAnimation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: screens[_selectedIndex],
            ),
          ),

          /// --- Кастомная нижняя панель ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              // Используем clamp, чтобы высота не стала меньше 0
              height: (bottomBgHeight + bottomInset).clamp(0.0, 200.0),
              padding: EdgeInsets.only(
                // math.max гарантирует, что значение не упадет ниже 0
                bottom: (bottomInset - 2).clamp(0.0, 100.0),
              ),
              decoration: BoxDecoration(
                color: cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavButton(
                      icon: Icons.home,
                      selected: _selectedIndex == 0,
                      color: purple,
                      onTap: () => _onItemTapped(0),
                    ),
                    _NavButton(
                      icon: Icons.chat,
                      selected: _selectedIndex == 1,
                      color: purple,
                      onTap: () => _onItemTapped(1),
                    ),
                    _NavButton(
                      icon: Icons.person,
                      selected: _selectedIndex == 2,
                      color: purple,
                      onTap: () => _onItemTapped(2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          /// --- PROFILE DRAWER (должен быть выше nav, поэтому добавляем его в конце списка children) ---
          if (isProfileOpen) ...[
            // затемняющий фон
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => isProfileOpen = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),

            // сама панель, слева, ширина = panelWidth
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
                        // header: можно менять размеры здесь (fontSize)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Профиль', // можно заменить на fullName, если прокинуть
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: purple),
                              onPressed: () => setState(() => isProfileOpen = false),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Text('Пол: ---', style: TextStyle(color: Colors.black87)),
                        Text('Возраст: ---', style: TextStyle(color: Colors.black87)),
                        Text('Email: ---', style: TextStyle(color: Colors.black87)),
                        const Spacer(),
                        OutlinedButton(onPressed: () {}, child: const Text('Настройки')),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Supabase.instance.client.auth.signOut();

                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => AuthScreen()),
                                  (route) => false,
                            );
                          },
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Выйти'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: purple,
                            foregroundColor: Colors.white,
                          ),
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
}

/// Навигационные кнопки (оставляем как есть)
class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: selected ? 1.2 : 1.0,
          child: Icon(
            icon,
            color: selected ? color : Colors.grey,
            size: 26,
          ),
        ),
      ),
    );
  }
}
