import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'catalog_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final Color purple = const Color(0xFF5E3B8C);
  final Color cardColor = const Color(0xFFF6F6FF);

  final List<Widget> _screens = [
     HomeScreen(),
     ChatScreen(),
     CatalogScreen(),
  ];

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
              child: _screens[_selectedIndex],
            ),
          ),


          /// --- Кастомная нижняя панель ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: bottomBgHeight + bottomInset,
              padding: EdgeInsets.only(bottom: bottomInset - 2),
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
        ],
      ),
    );
  }
}

/// 🔘 Кастомная кнопка навигации
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
