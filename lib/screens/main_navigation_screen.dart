import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/oakle_notice.dart';
import '../screens/profile_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'SpecialistSelectionScreen.dart';
import 'auth_screen.dart';
import 'PsychologistDashboard.dart';

class MainNavigationScreen extends StatefulWidget {
  final String? forcedRole;
  final ApiClient apiClient;
  const MainNavigationScreen({
    Key? key,
    this.forcedRole,
    required this.apiClient,
  }) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const MethodChannel _emailChannel = MethodChannel('soulbuddy/email');
  int _selectedIndex = 0;

  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFF6F8FD);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);

  bool isProfileOpen = false;

  String userName = "Пользователь";
  String userEmail = "";
  String userRole = "client";
  int userAge = 0;
  String assignedTherapist = "Не назначен";
  bool _openClientsOnDashboard = false;

  @override
  void initState() {
    super.initState();
    userRole = widget.forcedRole ?? userRole;
    _loadUserData();
    _hideSystemUI();
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  Future<void> _loadUserData() async {
    // Показываем последнее сохранённое имя сразу, не ожидая сетевого ответа.
    final prefs = await SharedPreferences.getInstance();
    final cachedName = prefs.getString('profile_display_name');
    final cachedEmail = prefs.getString('profile_email');
    if (mounted && cachedName != null && cachedName.isNotEmpty) {
      setState(() {
        userName = cachedName;
        userEmail = cachedEmail ?? userEmail;
      });
    }
    try {
      final response = await widget.apiClient.dio.get('/users/me');
      final data = Map<String, dynamic>.from(response.data as Map);
      final parts = [data['first_name'], data['last_name']]
          .where((part) => part != null && part.toString().trim().isNotEmpty)
          .join(' ');
      if (!mounted) return;
      final birthDate = DateTime.tryParse(data['birth_date']?.toString() ?? '');
      var age = 0;
      if (birthDate != null) {
        final today = DateTime.now();
        age = today.year - birthDate.year;
        if (today.month < birthDate.month ||
            (today.month == birthDate.month && today.day < birthDate.day)) {
          age--;
        }
      }
      setState(() {
        userEmail = data['email']?.toString() ?? '';
        userName = parts.isEmpty ? 'Пользователь' : parts;
        userRole = data['is_psychologist'] == true ? 'specialist' : 'client';
        userAge = age;
      });
      await prefs.setString('profile_display_name', userName);
      await prefs.setString('profile_email', userEmail);
    } on DioException catch (e) {
      debugPrint("Ошибка загрузки профиля: ${e.message}");
      if (e.response?.statusCode == 401) {
        await _performLogout();
      }
    }
  }

  Future<void> _requestPsychologistStatus() async {
    final subject = 'Заявка на получение статуса психолога';
    final body =
        '''Здравствуйте!

Прошу рассмотреть возможность изменить роль моего аккаунта на психолога.
Имя: $userName
Email аккаунта: $userEmail

Пожалуйста, сообщите, если нужны дополнительные документы или сведения.''';
    try {
      await _emailChannel.invokeMethod<bool>('composeEmail', {
        'subject': subject,
        'body': body,
      });
      if (!mounted) return;
      showOakleNotice(
        context,
        'Черновик письма открыт. Укажите email администратора и отправьте письмо. Роль изменит администратор.',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      showOakleNotice(
        context,
        'Не удалось открыть почту (${error.message ?? 'почтовое приложение не найдено'}). Напишите администратору вручную.',
        isError: true,
      );
    }
  }

  Future<void> _performLogout() async {
    try {
      await widget.apiClient.dio.post('/auth/jwt/logout');
    } catch (_) {
    } finally {
      await TokenStorage().clearToken();
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
        apiClient: widget.apiClient,
        displayName: userName,
        isPsychologist: userRole == 'specialist',
      ),
      ChatScreen(
        apiClient: widget.apiClient,
        isPsychologist: userRole == 'specialist',
        onOpenPsychologistClients: userRole == 'specialist'
            ? () => setState(() {
                _openClientsOnDashboard = true;
                _selectedIndex = 2;
              })
            : null,
      ),
      userRole == 'specialist'
          ? PsychologistDashboard(
              apiClient: widget.apiClient,
              initialTab: _openClientsOnDashboard ? 1 : 0,
            )
          : SpecialistListScreen(apiClient: widget.apiClient),
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
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: bottomBgHeight,
              decoration: BoxDecoration(
                color: deepPurple,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
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
            top: 0,
            bottom: 0,
            child: Container(
              width: panelWidth,
              decoration: const BoxDecoration(
                color: Color(0xFFB0A6E8),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: warmWhite.withOpacity(0.85),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
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
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : "U",
                                style: TextStyle(
                                  color: warmWhite,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    userRole == 'specialist'
                                        ? "Специалист"
                                        : "Клиент",
                                    style: TextStyle(
                                      color: accentPurple,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        if (userAge > 0)
                          _infoItem(
                            Icons.cake_outlined,
                            "Возраст",
                            "$userAge лет",
                          ),
                        _infoItem(
                          Icons.email_outlined,
                          "Email",
                          userEmail.isNotEmpty ? userEmail : "Не указан",
                        ),

                        if (userRole != 'specialist') ...[
                          const Divider(height: 32, color: Colors.black12),
                          _infoItem(
                            Icons.psychology,
                            "Ваш специалист",
                            assignedTherapist,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _requestPsychologistStatus,
                              icon: const Icon(
                                Icons.mark_email_unread_outlined,
                              ),
                              label: const Text('Стать психологом'),
                            ),
                          ),
                        ],

                        const Spacer(),

                        if (userRole == 'specialist') ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProfileScreen(
                                      apiClient: widget.apiClient,
                                    ),
                                  ),
                                );
                                _loadUserData();
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Редактировать профиль'),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _performLogout,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text("Выйти"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentPurple,
                              foregroundColor: warmWhite,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
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
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
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
