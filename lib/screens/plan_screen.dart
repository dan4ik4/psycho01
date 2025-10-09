import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanScreen extends StatefulWidget {
  @override
  _PlanScreenState createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final client = Supabase.instance.client;
  final planController = TextEditingController();
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final response = await client
        .from('plans')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    setState(() => _plans = List<Map<String, dynamic>>.from(response));
  }

  Future<void> _addPlan() async {
    final user = client.auth.currentUser;
    if (user == null || planController.text.isEmpty) return;

    await client.from('plans').insert({
      'user_id': user.id,
      'text': planController.text,
      'version': _plans.length + 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    planController.clear();
    _loadPlans();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Мой план')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: planController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Опиши свой план...',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addPlan,
              child: Text('Опубликовать'),
            ),
            SizedBox(height: 20),
            Expanded(
              child: _plans.isEmpty
                  ? Center(child: Text('Планов пока нет'))
                  : ListView.builder(
                itemCount: _plans.length,
                itemBuilder: (context, index) {
                  final p = _plans[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text('Версия ${p['version']}'),
                      subtitle: Text(p['text']),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}