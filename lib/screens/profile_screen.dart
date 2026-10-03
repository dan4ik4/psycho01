import 'package:flutter/material.dart';
import '../features/profile/data/profile_repository.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _profileRepository;

  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFF6F8FD);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);

  String _userName = "Загрузка...";
  String _userEmail = "";
  String _psychologistName = "Др. Елена Воронова";
  bool _notificationsEnabled = true;
  bool _isLoading = true;

  final List<Map<String, dynamic>> _treatmentGoals = [
    {
      'title': 'Снижение уровня тревожности',
      'progress': 0.7,
      'status': 'В процессе',
    },
    {
      'title': 'Дневник эмоций (ежедневно)',
      'progress': 0.9,
      'status': 'Отлично',
    },
    {
      'title': 'Дыхательные практики 4-7-8',
      'progress': 0.4,
      'status': 'Требует внимания',
    },
  ];

  @override
  void initState() {
    super.initState();
    // Инициализация единого экземплярa TokenStorage и его передача в ApiClient
    final tokenStorage = TokenStorage();
    _profileRepository = ProfileRepository(
      apiClient: ApiClient(tokenStorage: tokenStorage),
      tokenStorage: tokenStorage,
    );
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final profileData = await _profileRepository.fetchUserProfile();
      if (!mounted) return;

      setState(() {
        _userName = profileData['full_name'] ?? 'Пользователь';
        _userEmail = profileData['email'] ?? '';
        _psychologistName =
            profileData['psychologist_name'] ?? 'Др. Елена Воронова';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _userName = 'Ошибка загрузки';
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при загрузке профиля: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: warmWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Выход из аккаунта",
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Вы уверены, что хотите выйти?",
          style: TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Отмена", style: TextStyle(color: textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Выйти", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _profileRepository.logout();
      } catch (_) {}

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepPurple,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Профиль",
          style: TextStyle(color: warmWhite, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.logout_rounded, color: warmWhite),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: warmWhite))
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              _buildUserHeader(),
              const SizedBox(height: 20),
              _buildTreatmentPlanCard(),
              const SizedBox(height: 20),
              _buildTherapistCard(),
              const SizedBox(height: 20),
              _buildSettingsBlock(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: warmWhite.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: accentPurple,
            child: Text(
              _userName.isNotEmpty ? _userName[0].toUpperCase() : "U",
              style: TextStyle(
                color: warmWhite,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail,
                  style: TextStyle(color: textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentPlanCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: warmWhite.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment_turned_in_outlined, color: accentPurple),
                  const SizedBox(width: 8),
                  Text(
                    "План лечения",
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentPurple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "AI + Психолог",
                  style: TextStyle(
                    color: accentPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._treatmentGoals.map((goal) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          goal['title'],
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        "${(goal['progress'] * 100).toInt()}%",
                        style: TextStyle(
                          color: accentPurple,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: goal['progress'],
                      backgroundColor: textSecondary.withOpacity(0.15),
                      color: accentPurple,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTherapistCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: warmWhite.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentPurple.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.psychology, color: accentPurple, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ваш психотерапевт",
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _psychologistName,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.video_call_rounded, color: accentPurple, size: 28),
            onPressed: () {
              Navigator.pushNamed(context, '/call', arguments: 'session_room_1');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsBlock() {
    return Container(
      decoration: BoxDecoration(
        color: warmWhite.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          SwitchListTile(
            activeColor: accentPurple,
            title: Text(
              "Уведомления",
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              "Напоминания о дневнике и сессиях",
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
            value: _notificationsEnabled,
            onChanged: (val) {
              setState(() => _notificationsEnabled = val);
            },
          ),
          Divider(height: 1, color: textSecondary.withOpacity(0.15)),
          ListTile(
            leading: Icon(Icons.lock_outline, color: textPrimary, size: 22),
            title: Text(
              "Безопасность и PIN",
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Icon(Icons.arrow_forward_ios, color: textSecondary, size: 14),
            onTap: () {},
          ),
          Divider(height: 1, color: textSecondary.withOpacity(0.15)),
          ListTile(
            leading: Icon(Icons.help_outline, color: textPrimary, size: 22),
            title: Text(
              "Поддержка",
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Icon(Icons.arrow_forward_ios, color: textSecondary, size: 14),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}