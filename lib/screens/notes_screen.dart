import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotesScreen extends StatefulWidget {
  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final client = Supabase.instance.client;
  final noteController = TextEditingController();
  List<Map<String, dynamic>> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final res = await client
        .from('notes')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    setState(() => _notes = List<Map<String, dynamic>>.from(res));
  }

  Future<void> _addNote() async {
    final user = client.auth.currentUser;
    if (user == null || noteController.text.isEmpty) return;

    await client.from('notes').insert({
      'user_id': user.id,
      'text': noteController.text,
      'created_at': DateTime.now().toIso8601String(),
    });

    noteController.clear();
    _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Мои заметки')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                hintText: 'Введите заметку...',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addNote,
              child: Text('Добавить'),
            ),
            SizedBox(height: 20),
            Expanded(
              child: _notes.isEmpty
                  ? Center(child: Text('Заметок пока нет'))
                  : ListView.builder(
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final n = _notes[index];
                  return Card(
                    child: ListTile(
                      title: Text(n['text']),
                      subtitle: Text(n['created_at']),
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