import 'package:flutter/material.dart';

class ProfileDrawer extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final VoidCallback onLogout;
  final VoidCallback onSettings;

  const ProfileDrawer({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.onLogout,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final Color purple = const Color(0xFF6C4AB6);
    final Color bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;

    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      color: bgColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Верхняя панель
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Профиль', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: onThemeToggle,
                icon: Icon(isDarkMode ? Icons.wb_sunny : Icons.nightlight_round, color: purple),
              ),
            ],
          ),
          const Spacer(),
          TextButton(
            onPressed: onSettings,
            child: Text('Настройки', style: TextStyle(color: textColor, fontSize: 18)),
          ),
          TextButton(
            onPressed: onLogout,
            child: Text('Выйти из аккаунта', style: TextStyle(color: textColor, fontSize: 18)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
