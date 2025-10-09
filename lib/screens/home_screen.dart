import 'package:flutter/material.dart';
import 'plan_screen.dart';
import 'catalog_screen.dart';
import 'notes_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final _screens = [
    PlanScreen(),
    CatalogScreen(),
    NotesScreen(),
    ChatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'План'),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'Психологи'),
          BottomNavigationBarItem(icon: Icon(Icons.note), label: 'Заметки'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Чат'),
        ],
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}