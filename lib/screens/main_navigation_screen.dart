import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'SpecialistSelectionScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'PsychologistDashboard.dart';

class MainNavigationScreen extends StatefulWidget {
  // 🟣 Добавляем параметр для принудительной роли (для тестов)
  final String? forcedRole;

  const MainNavigationScreen({Key? key, this.forcedRole}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final Color purple = const Color(0xFF5E3B8C);
  final Color cardColor = const Color(0xFFF6F6FF);

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

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFFF6F6FF),
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  // 🟣 Обновленный метод загрузки данных
  void _loadUserData() {
    // 1. Если роль передана принудительно (через тестовую кнопку)
    if (widget.forcedRole != null) {
      setState(() {
        userRole = widget.forcedRole!;
        userName = userRole == 'specialist' ? "Тестовый Профи" : "Тестовый Клиент";
        userEmail = "test@example.com";
      });
      return; // Прекращаем выполнение, не опрашивая Supabase
    }

    // 2. Стандартная логика для реальных пользователей
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
    final double bottomBgHeight = 60;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final double panelWidth = MediaQuery.of(context).size.width * 0.8;

    final List<Widget> screens = [
      HomeScreen(onOpenProfile: () => setState(() => isProfileOpen = true)),
      ChatScreen(),
      userRole == 'specialist'
          ? PsychologistDashboard()
          : SpecialistListScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.fastOutSlowIn,
            switchOutCurve: Curves.fastOutSlowIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex + (userRole == 'specialist' ? 10 : 0)), // ключ меняется при смене роли
              child: screens[_selectedIndex],
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: bottomBgHeight + bottomInset,
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: BoxDecoration(
                color: cardColor,
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavButton(icon: Icons.home_rounded, selected: _selectedIndex == 0, color: purple, onTap: () => _onItemTapped(0)),
                  _NavButton(icon: Icons.chat_bubble_outline_rounded, selected: _selectedIndex == 1, color: purple, onTap: () => _onItemTapped(1)),
                  _NavButton(
                      icon: userRole == 'specialist' ? Icons.dashboard_customize_outlined : Icons.people_alt_outlined,
                      selected: _selectedIndex == 2,
                      color: purple,
                      onTap: () => _onItemTapped(2)
                  ),
                ],
              ),
            ),
          ),

          if (isProfileOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => isProfileOpen = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: panelWidth,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(30), bottomRight: Radius.circular(30)),
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
                              backgroundColor: purple.withOpacity(0.1),
                              radius: 25,
                              child: Icon(Icons.person, color: purple),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(userRole == 'specialist' ? "Специалист" : "Клиент",
                                      style: TextStyle(color: purple, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            IconButton(icon: Icon(Icons.close, color: purple), onPressed: () => setState(() => isProfileOpen = false)),
                          ],
                        ),
                        const SizedBox(height: 30),
                        _profileInfoItem(Icons.wc, "Пол", userGender),
                        _profileInfoItem(Icons.cake_outlined, "Возраст", "$userAge лет"),
                        _profileInfoItem(Icons.email_outlined, "Email", userEmail),
                        const Divider(height: 40),

                        if (userRole == 'specialist')
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.verified_user_outlined, color: Colors.green),
                            title: const Text("Статус верификации"),
                            onTap: () {},
                          ),

                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.settings_outlined, color: Colors.grey),
                          label: const Text("Настройки", style: TextStyle(color: Colors.grey)),
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
                              backgroundColor: purple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
        ],
      ),
    );
  }

  Widget _profileInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
  final Color color;
  final VoidCallback onTap;

  const _NavButton({required this.icon, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: selected ? color : Colors.grey[400], size: 28),
      ),
    );
  }
}