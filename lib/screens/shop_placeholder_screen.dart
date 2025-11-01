import 'package:flutter/material.dart';

class ShopPlaceholderScreen extends StatelessWidget {
  const ShopPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Магазин')),
      body: const Center(child: Text('Здесь будет экран магазина')),
    );
  }
}