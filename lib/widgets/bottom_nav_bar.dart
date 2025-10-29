import 'package:flutter/material.dart';

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabSelected;

  const BottomNavBar({super.key, required this.selectedIndex, required this.onTabSelected});

  @override
  Widget build(BuildContext context) {
    final Color purple = const Color(0xFF6C4AB6);
    final Color inactive = Colors.grey;

    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(Icons.calendar_month, 0, purple, inactive),
          _navItem(Icons.favorite, 1, purple, inactive),
          _navItem(Icons.menu_book, 2, purple, inactive),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, int index, Color active, Color inactive) {
    final bool isActive = index == selectedIndex;
    return IconButton(
      onPressed: () => onTabSelected(index),
      icon: Icon(icon, color: isActive ? active : inactive, size: 30),
    );
  }
}
