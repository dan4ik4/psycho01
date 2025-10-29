import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/profile_drawer.dart';
import '../widgets/calendar/calendar_view.dart';
import '../screens/breathing_screen.dart';
import '../utils/score_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isDarkMode = false;
  bool isDrawerOpen = false;
  int selectedIndex = 0;
  int stars = 0;

  @override
  void initState() {
    super.initState();
    _loadStars(); // ✅ загружаем при старте
  }

  Future<void> _loadStars() async {
    final total = await ScoreManager.getScore();
    setState(() => stars = total);
  }

  void _addStars(int points) async {
    final total = await ScoreManager.getScore();
    setState(() => stars = total);
  }

  void _toggleDrawer() => setState(() => isDrawerOpen = !isDrawerOpen);

  @override
  Widget build(BuildContext context) {
    final Color purple = const Color(0xFF6C4AB6);
    final Color bgColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF2F2F2);
    final Color cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 30),
              // Верхняя панель
              Container(
                height: 90,
                color: cardColor,
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      bottom: 10,
                      child: IconButton(
                        icon: Icon(Icons.menu, color: purple, size: 30),
                        onPressed: _toggleDrawer,
                      ),
                    ),
                    Center(
                      child: Image.asset('assets/images/lotus.png', height: 60),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 10,
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 28),
                          const SizedBox(width: 4),
                          Text(
                            "$stars", // ✅ динамическое количество звёзд
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Приветствие
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: purple, width: 1),
                  ),
                  child: Text(
                    'Добро пожаловать 👋',
                    style: TextStyle(fontSize: 18, color: textColor),
                  ),
                ),
              ),
              // Календарь
              Expanded(
                child: CalendarView(
                  isDarkMode: isDarkMode,
                  onAddStars: _addStars,
                ),
              ),
            ],
          ),
          // Левая плашка профиля
          if (isDrawerOpen)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              left: isDrawerOpen ? 0 : -MediaQuery.of(context).size.width * 0.8,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _toggleDrawer,
                child: Row(
                  children: [
                    ProfileDrawer(
                      isDarkMode: isDarkMode,
                      onThemeToggle: () => setState(() => isDarkMode = !isDarkMode),
                      onLogout: () {},
                      onSettings: () {},
                    ),
                    Expanded(child: GestureDetector(onTap: _toggleDrawer, child: Container(color: Colors.transparent))),
                  ],
                ),
              ),
            ),
          // Нижняя панель
          Align(
            alignment: Alignment.bottomCenter,
            child: BottomNavBar(
              selectedIndex: selectedIndex,
              onTabSelected: (index) {
                setState(() => selectedIndex = index);
                if (index == 1) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BreathingScreen(isDarkMode: isDarkMode),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
