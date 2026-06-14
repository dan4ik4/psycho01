import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'SpecialistSelectionScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'PsychologistDashboard.dart';

class MainNavigationScreen extends StatefulWidget {
  final String? forcedRole;
  const MainNavigationScreen({Key? key, this.forcedRole}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  // Цветовая палитра
  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFFFF9F2);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);

  // Твой выбранный цвет (смесь 50/50)[cite: 7]
  final Color solidPanelColor = const Color(0xFFDFD8EE);

  bool isProfileOpen = false;

  String userName = "Пользователь";
  String userEmail = "";
  String userRole = "client";
  String userGender = "---";
  int userAge = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _hideSystemUI();
  }

  // Максимальное скрытие системных кнопок[cite: 7]
  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  void _loadUserData() {
    if (widget.forcedRole != null) {
      setState(() {
        userRole = widget.forcedRole!;
        userName = userRole == 'specialist' ? "Тестовый Профи" : "Тестовый Клиент";
        userEmail = "test@example.com";
      });
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        userEmail = user.email ?? "";
        userName = user.userMetadata?['full_name'] ?? "Не указано";
        userRole = user.userMetadata?['role'] ?? "client";
        userGender = user.userMetadata?['gender'] ?? "---";
        userAge = user.userMetadata?['age'] ?? 0;
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Вызываем скрытие UI при каждом билде, чтобы система не вернула кнопки[cite: 7]
    _hideSystemUI();

    final double bottomBgHeight = 65; // Вернули компактную высоту
    final double panelWidth = MediaQuery.of(context).size.width * 0.8;

    final List<Widget> screens = [
      HomeScreen(onOpenProfile: () => setState(() => isProfileOpen = true)),
      ChatScreen(),
      userRole == 'specialist' ? PsychologistDashboard() : SpecialistListScreen(),
    ];

    return Scaffold(
      backgroundColor: deepPurple,
      resizeToAvoidBottomInset: false, // Игнорируем клавиатуру для UI
      body: Stack(
        children: [
          // 1. Контент экрана
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: screens[_selectedIndex],
            ),
          ),

          // 2. Нижняя панель (Цвет 0xFFD7D0ED)[cite: 7]
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: bottomBgHeight,
              decoration: BoxDecoration(
                color: solidPanelColor,
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavButton(
                      icon: Icons.home_rounded,
                      selected: _selectedIndex == 0,
                      activeBg: accentPurple.withOpacity(0.2), // Прозрачнее и приплюснуто
                      inactiveColor: textSecondary, // Цвет по умолчанию
                      iconActiveColor: accentPurple,
                      onTap: () => _onItemTapped(0)
                  ),
                  _NavButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      selected: _selectedIndex == 1,
                      activeBg: accentPurple.withOpacity(0.2),
                      inactiveColor: textSecondary,
                      iconActiveColor: accentPurple,
                      onTap: () => _onItemTapped(1)
                  ),
                  _NavButton(
                      icon: userRole == 'specialist' ? Icons.dashboard_customize_outlined : Icons.people_alt_outlined,
                      selected: _selectedIndex == 2,
                      activeBg: accentPurple.withOpacity(0.2),
                      inactiveColor: textSecondary,
                      iconActiveColor: accentPurple,
                      onTap: () => _onItemTapped(2)
                  ),
                ],
              ),
            ),
          ),

          // 3. Затемнение
          if (isProfileOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => isProfileOpen = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),

          // 4. Левая шторка (Цвет 0xFFD7D0ED)[cite: 7]
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            left: isProfileOpen ? 0 : -panelWidth,
            top: 0, bottom: 0,
            child: Container(
              width: panelWidth,
              decoration: BoxDecoration(
                color: solidPanelColor,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(30), bottomRight: Radius.circular(30)),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: accentPurple.withOpacity(0.2),
                            radius: 25,
                            child: Icon(Icons.person, color: accentPurple),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(userName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary)),
                                Text(userRole == 'specialist' ? "Специалист" : "Клиент",
                                    style: TextStyle(color: accentPurple, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _infoItem(Icons.wc, "Пол", userGender),
                      _infoItem(Icons.cake_outlined, "Возраст", "$userAge лет"),
                      _infoItem(Icons.email_outlined, "Email", userEmail),
                      const Divider(height: 40, color: Colors.black12),

                      const Spacer(),

                      TextButton.icon(
                        onPressed: () {},
                        icon: Icon(Icons.settings_outlined, color: textPrimary),
                        label: Text("Настройки", style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Supabase.instance.client.auth.signOut();
                            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => AuthScreen()), (route) => false);
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text("Выйти"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentPurple,
                            foregroundColor: warmWhite,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: textSecondary)),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color activeBg;
  final Color inactiveColor;
  final Color iconActiveColor;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.selected,
    required this.activeBg,
    required this.inactiveColor,
    required this.iconActiveColor,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), // Приплюснутая форма[cite: 7]
        decoration: BoxDecoration(
          color: selected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20), // Овальная капсула
        ),
        child: Icon(
          icon,
          color: selected ? iconActiveColor : inactiveColor,
          size: 24, // Уменьшенный размер[cite: 7]
        ),
      ),
    );
  }
}