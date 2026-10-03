import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'SpecialistSelectionScreen.dart';
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

  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFF6F8FD);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);

  bool isProfileOpen = false;

  String userName = "Загрузка...";
  String userEmail = "";
  String userRole = "client";
  String userGender = "---";
  int userAge = 0;
  String assignedTherapist = "Не назначен";

  late final Dio _dio;
  late final ApiClient _apiClient;

  @override
  void initState() {
    super.initState();
    _initDio();
    _apiClient = ApiClient(tokenStorage: TokenStorage());
    _loadUserData();
    _hideSystemUI();
  }

  void _initDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.yourdomain.com/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  Future<void> _loadUserData() async {
    if (widget.forcedRole != null) {
      setState(() {
        userRole = widget.forcedRole!;
        userName = userRole == 'specialist' ? "Тестовый Профи" : "Тестовый Клиент";
        userEmail = "test@example.com";
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    setState(() {
      userEmail = prefs.getString('user_email') ?? "";
      userName = prefs.getString('user_name') ?? "Пользователь";
      userRole = prefs.getString('user_role') ?? "client";
      userGender = prefs.getString('user_gender') ?? "---";
      userAge = prefs.getInt('user_age') ?? 0;
    });

    try {
      final response = await _dio.get('/user/profile');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;

        setState(() {
          userEmail = data['email'] ?? userEmail;
          userName = data['full_name'] ?? userName;
          userRole = data['role'] ?? userRole;
          userGender = data['gender'] ?? userGender;
          userAge = data['age'] ?? userAge;
          assignedTherapist = data['assigned_therapist'] ?? "Не назначен";
        });

        await prefs.setString('user_email', userEmail);
        await prefs.setString('user_name', userName);
        await prefs.setString('user_role', userRole);
        await prefs.setString('user_gender', userGender);
        await prefs.setInt('user_age', userAge);
      }
    } on DioException catch (e) {
      debugPrint("Ошибка загрузки профиля: ${e.message}");
      if (e.response?.statusCode == 401) {
        await _performLogout();
      }
    }
  }

  Future<void> _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _dio.post('/auth/logout');
    } catch (_) {} finally {
      await prefs.clear();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
              (route) => false,
        );
      }
    }
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    _hideSystemUI();

    final double bottomBgHeight = 65;
    final double panelWidth = MediaQuery.of(context).size.width * 0.8;

    final List<Widget> screens = [
      HomeScreen(
        onOpenProfile: () => setState(() => isProfileOpen = true),
        apiClient: _apiClient,
      ),
      const ChatScreen(),
      userRole == 'specialist' ? PsychologistDashboard() : const SpecialistListScreen(),
    ];

    return Scaffold(
      backgroundColor: deepPurple,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: screens[_selectedIndex],
            ),
          ),

          // Нижняя панель навигации
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: bottomBgHeight,
              decoration: BoxDecoration(
                color: deepPurple,
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Container(
                color: warmWhite.withOpacity(0.8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavButton(
                      icon: Icons.home_rounded,
                      selected: _selectedIndex == 0,
                      activeBg: accentPurple.withOpacity(0.2),
                      inactiveColor: textSecondary,
                      iconActiveColor: accentPurple,
                      onTap: () => _onItemTapped(0),
                    ),
                    _NavButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      selected: _selectedIndex == 1,
                      activeBg: accentPurple.withOpacity(0.2),
                      inactiveColor: textSecondary,
                      iconActiveColor: accentPurple,
                      onTap: () => _onItemTapped(1),
                    ),
                    _NavButton(
                      icon: userRole == 'specialist'
                          ? Icons.dashboard_customize_outlined
                          : Icons.people_alt_outlined,
                      selected: _selectedIndex == 2,
                      activeBg: accentPurple.withOpacity(0.2),
                      inactiveColor: textSecondary,
                      iconActiveColor: accentPurple,
                      onTap: () => _onItemTapped(2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (isProfileOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => isProfileOpen = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),

          // Боковая шторка профиля
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            left: isProfileOpen ? 0 : -panelWidth,
            top: 0, bottom: 0,
            child: Container(
              width: panelWidth,
              decoration: const BoxDecoration(
                color: Color(0xFFB0A6E8),
                borderRadius: BorderRadius.only(topRight: Radius.circular(30), bottomRight: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: warmWhite.withOpacity(0.85),
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
                              backgroundColor: accentPurple,
                              radius: 24,
                              child: Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : "U",
                                style: TextStyle(color: warmWhite, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    userRole == 'specialist' ? "Специалист" : "Клиент",
                                    style: TextStyle(color: accentPurple, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        _infoItem(Icons.wc, "Пол", userGender),
                        _infoItem(Icons.cake_outlined, "Возраст", userAge > 0 ? "$userAge лет" : "Не указан"),
                        _infoItem(Icons.email_outlined, "Email", userEmail.isNotEmpty ? userEmail : "Не указан"),

                        if (userRole != 'specialist') ...[
                          const Divider(height: 32, color: Colors.black12),
                          _infoItem(Icons.psychology, "Ваш специалист", assignedTherapist),
                        ],

                        const Spacer(),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _performLogout,
                            icon: const Icon(Icons.logout_rounded, size: 18),
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
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: textSecondary)),
                Text(
                  value,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: selected ? iconActiveColor : inactiveColor,
          size: 24,
        ),
      ),
    );
  }
}