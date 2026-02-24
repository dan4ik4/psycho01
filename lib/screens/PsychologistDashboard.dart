import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';


class PsychologistDashboard extends StatefulWidget {
  @override
  _PsychologistDashboardState createState() => _PsychologistDashboardState();
}

class _PsychologistDashboardState extends State<PsychologistDashboard> {
  final Color purple = const Color(0xFF5E3B8C);
  final Color bg = const Color(0xFFF6F6FF);
  bool isAcceptingClients = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // Шапка кабинета
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: purple,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("Мой кабинет",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              centerTitle: true,
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Блок статистики
                  Row(
                    children: [
                      _buildStatCard("Сессии", "24", Icons.event_available, Colors.blue),
                      const SizedBox(width: 15),
                      _buildStatCard("Доход", "2100р", Icons.payments_outlined, Colors.green),
                    ],
                  ),
                  const SizedBox(height: 25),

                  // Переключатель доступности
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Статус приема", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("Виден ли профиль клиентам", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        Switch(
                          value: isAcceptingClients,
                          activeColor: purple,
                          onChanged: (v) => setState(() => isAcceptingClients = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Text("Ближайшие записи",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  // Список записей (Заглушка)
                  _buildAppointmentTile(
                    clientName: "Александр В.",
                    time: "Сегодня, 14:00",
                    topic: "Тревожность и стресс",
                    imageUrl: "https://i.pravatar.cc/150?img=11",
                  ),
                  _buildAppointmentTile(
                    clientName: "Мария С.",
                    time: "Завтра, 10:00",
                    topic: "Семейная консультация",
                    imageUrl: "https://i.pravatar.cc/150?img=32",
                  ),
                  _buildAppointmentTile(
                    clientName: "Дмитрий П.",
                    time: "19 Фев, 16:30",
                    topic: "Профессиональное выгорание",
                    imageUrl: "https://i.pravatar.cc/150?img=12",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Виджет карточки статистики
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 15),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // Виджет плитки записи
  Widget _buildAppointmentTile({required String clientName, required String time, required String topic, required String imageUrl}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(time, style: TextStyle(color: purple, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(topic, style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, size: 20, color: Colors.grey),
            onPressed: () {},
          )
        ],
      ),
    );
  }
}