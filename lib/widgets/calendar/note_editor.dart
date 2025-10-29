// lib/widgets/calendar/note_editor.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NoteEditor — выдвижной редактор заметок для конкретной даты.
/// Возвращает через Navigator.pop(context, updatedList) список заметок (List<Map<String,dynamic>>),
/// где каждый элемент: { 'text': String, 'createdAt': ISOString }.
///
/// Важно: CalendarView должен вызывать этот редактор через:
/// final result = await showModalBottomSheet<List<Map<String,dynamic>>>(...);
/// if (result != null) => сохранить notes и возможно начислить очки.
///
/// Точки, где поведение критично:
/// - при удалении показываем ОДИН диалог подтверждения (Yes/No; Да слева, Нет справа)
/// - при закрытии, если есть несохранённые изменения — показываем диалог "Не сохранили, выйти?"
class NoteEditor extends StatefulWidget {
  final DateTime day;
  final List<Map<String, dynamic>> initialNotes; // each: {'text':..., 'createdAt':...}
  final bool isDarkMode;

  const NoteEditor({
    super.key,
    required this.day,
    required this.initialNotes,
    this.isDarkMode = false,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late List<Map<String, dynamic>> _notes;
  final List<TextEditingController> _controllers = [];
  final List<bool> _isSaved = []; // tracks whether note has been saved at least once

  @override
  void initState() {
    super.initState();
    // Deep copy initial notes
    _notes = widget.initialNotes.map((m) => Map<String, dynamic>.from(m)).toList();
    for (var n in _notes) {
      _controllers.add(TextEditingController(text: n['text'] as String? ?? ''));
      _isSaved.add(!(n['text'] as String? ?? '').trim().isEmpty);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasUnsaved {
    // unsaved if any controller text differs from saved text or has a draft (empty but flagged)
    for (int i = 0; i < _controllers.length; i++) {
      final savedText = (i < _notes.length) ? (_notes[i]['text'] as String? ?? '') : '';
      if (_controllers[i].text.trim() != savedText.trim()) return true;
      if (!_isSaved[i] && _controllers[i].text.trim().isNotEmpty) return true;
    }
    return false;
  }

  void _addDraftNote() {
    setState(() {
      final nowIso = DateTime.now().toIso8601String();
      _notes.insert(0, {'text': '', 'createdAt': nowIso});
      _controllers.insert(0, TextEditingController());
      _isSaved.insert(0, false);
    });
  }

  Future<void> _saveNoteAt(int index) async {
    final text = _controllers[index].text.trim();
    if (text.isEmpty) return; // nothing to save
    _notes[index]['text'] = text;
    _notes[index]['createdAt'] = _notes[index]['createdAt'] ?? DateTime.now().toIso8601String();
    _isSaved[index] = true;
    await _persistLocally();
    setState(() {});
  }

  Future<void> _persistLocally() async {
    // Persist all notes for the date under key 'note_YYYY-MM-DD' as json list
    final key = _keyForDate(widget.day);
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_notes);
    await prefs.setString('note_$key', encoded);
  }

  Future<void> _attemptDelete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Удалить запись?'),
          content: const Text('Вы уверены, что хотите удалить эту заметку?'),
          actionsAlignment: MainAxisAlignment.start, // put buttons to the left by default
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Да'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Нет'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      // delete and persist
      setState(() {
        _notes.removeAt(index);
        _controllers[index].dispose();
        _controllers.removeAt(index);
        _isSaved.removeAt(index);
      });
      await _persistLocally();
    }
  }

  Future<bool> _onWillPop() async {
    if (_hasUnsaved) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Несохранённые изменения'),
            content: const Text('Вы не сохранили заметку. При выходе изменения не будут применены. Вы хотите выйти?'),
            actionsAlignment: MainAxisAlignment.start,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, true), // Да (left)
                child: const Text('Да'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false), // Нет (right)
                child: const Text('Нет'),
              ),
            ],
          );
        },
      );
      return leave == true;
    } else {
      return true;
    }
  }

  String _keyForDate(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final bool dark = widget.isDarkMode;
    final Color bg = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = dark ? Colors.white : Colors.black87;
    final Color purple = const Color(0xFF5E3B8C);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                // header with title and close button (cross)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Записи на ${widget.day.day}.${widget.day.month}.${widget.day.year}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final canClose = await _onWillPop();
                        if (canClose) {
                          // on close, return the current notes (without drafts that are empty)
                          final filtered = _notes.where((n) => (n['text'] as String?)?.trim().isNotEmpty ?? false).toList();
                          Navigator.pop(context, filtered);
                        }
                      },
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // notes list
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _notes.length,
                    itemBuilder: (context, idx) {
                      final note = _notes[idx];
                      final ctrl = _controllers[idx];
                      return Card(
                        color: dark ? const Color(0xFF292929) : Colors.grey[50],
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: ctrl,
                                maxLines: null,
                                style: TextStyle(color: textColor),
                                decoration: const InputDecoration.collapsed(hintText: 'Напишите что-то хорошее...'),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Save button with save icon (left) and white text
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      await _saveNoteAt(idx);
                                    },
                                    icon: const Icon(Icons.save, color: Colors.white, size: 18),
                                    label: const Text('Сохранить', style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(backgroundColor: purple),
                                  ),

                                  // metadata + delete
                                  Row(
                                    children: [
                                      if ((note['createdAt'] as String?)?.isNotEmpty ?? false)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8.0),
                                          child: Text(
                                            _shortDate(note['createdAt']),
                                            style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12),
                                          ),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                                        onPressed: () => _attemptDelete(idx),
                                      ),
                                    ],
                                  )
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // add new (text input + + button)
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(),
                        decoration: InputDecoration(
                          hintText: 'Быстрая заметка...',
                          filled: true,
                          fillColor: dark ? Colors.white10 : Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (value) async {
                          final text = value.trim();
                          if (text.isEmpty) return;
                          final nowIso = DateTime.now().toIso8601String();
                          setState(() {
                            _notes.insert(0, {'text': text, 'createdAt': nowIso});
                            _controllers.insert(0, TextEditingController(text: text));
                            _isSaved.insert(0, true);
                          });
                          await _persistLocally();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        // open a small dialog to write quick note (so it is not lost when using ephemeral controller)
                        final result = await showDialog<String>(
                          context: context,
                          builder: (ctx) {
                            final c = TextEditingController();
                            return AlertDialog(
                              title: const Text('Новая заметка'),
                              content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'Напишите заметку...')),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Отмена')),
                                ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Добавить')),
                              ],
                            );
                          },
                        );
                        if (result != null && result.trim().isNotEmpty) {
                          final nowIso = DateTime.now().toIso8601String();
                          setState(() {
                            _notes.insert(0, {'text': result.trim(), 'createdAt': nowIso});
                            _controllers.insert(0, TextEditingController(text: result.trim()));
                            _isSaved.insert(0, true);
                          });
                          await _persistLocally();
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: purple),
                      child: const Icon(Icons.add, color: Colors.white),
                    )
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  String _shortDate(Object? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso as String);
      return '${dt.day}.${dt.month}.${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
