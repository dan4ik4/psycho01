import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CatalogScreen extends StatefulWidget {
  @override
  _CatalogScreenState createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final client = Supabase.instance.client;
  List<Map<String, dynamic>> _psychologists = [];

  @override
  void initState() {
    super.initState();
    _loadPsychologists();
  }

  Future<void> _loadPsychologists() async {
    final data = await client.from('psychologists').select();
    setState(() => _psychologists = List<Map<String, dynamic>>.from(data));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Каталог психологов')),
      body: _psychologists.isEmpty
          ? Center(child: CircularProgressIndicator())
          : GridView.builder(
        padding: EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.8,
        ),
        itemCount: _psychologists.length,
        itemBuilder: (context, index) {
          final p = _psychologists[index];
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PsychologistScreen(p: p),
                  ),
                );
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(p['photo']),
                  ),
                  SizedBox(height: 10),
                  Text(p['name'], style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${p['experience']} лет опыта', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class PsychologistScreen extends StatelessWidget {
  final Map<String, dynamic> p;
  final client = Supabase.instance.client;

  PsychologistScreen({required this.p});

  Future<void> _selectPsychologist(BuildContext context) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    await client.from('users').update({'psychologist_id': p['id']}).eq('id', user.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Вы выбрали ${p['name']}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p['name'])),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(radius: 60, backgroundImage: NetworkImage(p['photo'])),
            SizedBox(height: 20),
            Text(p['specialty'], style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text('Опыт: ${p['experience']} лет'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _selectPsychologist(context),
              child: Text('Выбрать'),
            ),
          ],
        ),
      ),
    );
  }
}