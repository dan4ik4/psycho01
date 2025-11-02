import 'package:flutter/material.dart';
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

  final PageController _pageController = PageController();

  final purple = const Color(0xFF5E3B8C);
  final cardColor = const Color(0xFFF6F6FF);

  final List<Widget> _screens = [
    HomeScreen(),
    ChatScreen(),
    CatalogScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // отключаем свайпы
        children: _screens,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: bottomInset + 8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 🏠 Главная
              IconButton(
                icon: Icon(
                  Icons.home,
                  color: _selectedIndex == 0 ? purple : Colors.grey,
                ),
                onPressed: () => _onItemTapped(0),
              ),

              // 💬 Чат
              GestureDetector(
                onTap: () => _onItemTapped(1),
                child: Container(
                  decoration: BoxDecoration(
                    color: _selectedIndex == 1 ? purple : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.message,
                    color: _selectedIndex == 1 ? Colors.white : Colors.grey,
                    size: 28,
                  ),
                ),
              ),

              // 👤 Каталог / Профиль
              IconButton(
                icon: Icon(
                  Icons.person,
                  color: _selectedIndex == 2 ? purple : Colors.grey,
                ),
                onPressed: () => _onItemTapped(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
