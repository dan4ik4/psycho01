import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart'; // Используем для надежных ID

// Цвета из вашей стилистики
const Color kDeepPurple = Color(0xFFB0A6E8);
const Color kAccentPurple = Color(0xFF7862D6);
const Color kWarmWhite = Color(0xFFF6F8FD);
const Color kTextPrimary = Color(0xFF323045);
const Color kTextSecondary = Color(0xFF706D8C);
const Color kWeekendRed = Color(0xFFFF8A80);

// Модели данных для чата и папок
class ChatMessage {
  String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.isUser, required this.timestamp});
}

class ChatThread {
  final String id;
  String title;
  String folder;
  List<ChatMessage> messages;

  ChatThread({
    required this.id,
    required this.title,
    required this.folder,
    required this.messages,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final Uuid _uuid = const Uuid(); // Инициализация генератора UUID

  // Базовые папки (добавлена системная папка Архив)
  List<String> folders = ["Все", "Без папки", "Архив"];
  String selectedFolder = "Все";

  // Глобально выбранная модель ИИ на главном экране
  String _globalAiModel = "Средняя";

  // Стартовые пустые чаты
  List<ChatThread> chats = [];

  // Универсальный диалог подтверждения действия
  Future<bool> _confirmAction(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kWarmWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
        content: Text(content, style: const TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Отмена", style: TextStyle(color: kTextSecondary))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kWeekendRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Удалить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  // Окно создания нового чата
  void _showCreateChatDialog() {
    TextEditingController titleController = TextEditingController();
    String newChatFolder = selectedFolder == "Все" ? "Без папки" : selectedFolder;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kWarmWhite,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Создать новый чат", style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 15),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(color: kTextPrimary),
                          decoration: InputDecoration(
                            hintText: "Название чата",
                            filled: true,
                            fillColor: kDeepPurple.withOpacity(0.1),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text("Выберите папку:", style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Column(
                          children: folders.where((f) => f != "Все").map((f) {
                            bool isSel = newChatFolder == f;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(
                                  isSel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  color: isSel ? kAccentPurple : kTextSecondary.withOpacity(0.5)
                              ),
                              title: Text(f, style: TextStyle(color: isSel ? kAccentPurple : kTextPrimary, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                              onTap: () {
                                setModalState(() => newChatFolder = f);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                            onPressed: () {
                              if (titleController.text.trim().isEmpty) return;
                              setState(() {
                                chats.insert(0, ChatThread(
                                  id: _uuid.v4(), // Использование UUID вместо DateTime
                                  title: titleController.text.trim(),
                                  folder: newChatFolder,
                                  messages: [],
                                ));
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text("Создать", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        )
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  // Менеджер папок
  void _showFolderManager() {
    TextEditingController newFolderController = TextEditingController();

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                    decoration: const BoxDecoration(
                      color: kWarmWhite,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Управление папками", style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: newFolderController,
                                style: const TextStyle(color: kTextPrimary),
                                decoration: InputDecoration(
                                  hintText: "Новая папка...",
                                  filled: true,
                                  fillColor: kDeepPurple.withOpacity(0.1),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              decoration: BoxDecoration(color: kAccentPurple, borderRadius: BorderRadius.circular(15)),
                              child: IconButton(
                                icon: const Icon(Icons.add, color: kWarmWhite),
                                onPressed: () {
                                  String newFolder = newFolderController.text.trim();
                                  if (newFolder.isNotEmpty && !folders.contains(newFolder)) {
                                    setState(() => folders.add(newFolder));
                                    setModalState(() {});
                                    newFolderController.clear();
                                  }
                                },
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 15),
                        const Divider(color: Colors.black12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: folders.length,
                            itemBuilder: (context, index) {
                              String folder = folders[index];
                              bool isSelected = folder == selectedFolder;
                              // Защищаем системные папки от удаления
                              bool isDeletable = folder != "Все" && folder != "Без папки" && folder != "Архив";

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                    isSelected ? Icons.folder_open : Icons.folder,
                                    color: isSelected ? kAccentPurple : kTextSecondary.withOpacity(0.5)
                                ),
                                title: Text(folder, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? kAccentPurple : kTextPrimary)),
                                trailing: isDeletable
                                    ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: kWeekendRed),
                                  onPressed: () async {
                                    bool confirm = await _confirmAction(
                                        "Удалить папку?",
                                        "Вы уверены, что хотите удалить '$folder'? Все чаты из неё будут перемещены в 'Без папки'."
                                    );
                                    if (confirm) {
                                      setState(() {
                                        for (var c in chats) {
                                          if (c.folder == folder) c.folder = "Без папки";
                                        }
                                        folders.remove(folder);
                                        if (selectedFolder == folder) selectedFolder = "Все";
                                      });
                                      setModalState(() {});
                                    }
                                  },
                                )
                                    : null,
                                onTap: () {
                                  setState(() => selectedFolder = folder);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  void _showMoveToFolderDialog(ChatThread chat) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            decoration: const BoxDecoration(
              color: kWarmWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Переместить в папку", style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Column(
                  children: folders.where((f) => f != "Все").map((folder) {
                    final isCurrent = chat.folder == folder;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                          isCurrent ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isCurrent ? kAccentPurple : kTextSecondary.withOpacity(0.5)
                      ),
                      title: Text(folder, style: TextStyle(color: isCurrent ? kAccentPurple : kTextPrimary, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                      onTap: () {
                        setState(() {
                          chat.folder = folder;
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Чат перемещен в "$folder"', style: const TextStyle(color: kWarmWhite)), backgroundColor: kAccentPurple));
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        }
    );
  }

  void _toggleArchiveChat(ChatThread chat) {
    setState(() {
      if (chat.folder == "Архив") {
        chat.folder = "Без папки";
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Чат извлечен из архива"), backgroundColor: kAccentPurple));
      } else {
        chat.folder = "Архив";
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Чат перемещен в архив"), backgroundColor: kAccentPurple));
      }
    });
  }

  void _deleteChat(ChatThread chat) async {
    bool confirm = await _confirmAction(
        "Удалить чат?",
        "Вы уверены, что хотите навсегда удалить чат '${chat.title}'? Это действие нельзя отменить."
    );

    if (confirm) {
      setState(() {
        chats.removeWhere((c) => c.id == chat.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Чат удален"), backgroundColor: kWeekendRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    List<ChatThread> displayedChats = selectedFolder == "Все"
        ? chats
        : chats.where((c) => c.folder == selectedFolder).toList();

    return Scaffold(
      backgroundColor: kDeepPurple,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Шапка с интегрированной кнопкой папок и выбором модели
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showFolderManager,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                      child: const Icon(Icons.menu, color: kWarmWhite, size: 28),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("ИИ-Ассистент", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kWarmWhite)),
                        Text("Папка: $selectedFolder", style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                  // Выбор модели на главном экране
                  PopupMenuButton<String>(
                    initialValue: _globalAiModel,
                    tooltip: "Изменить модель ИИ",
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    onSelected: (val) {
                      setState(() => _globalAiModel = val);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Выбрана модель: $val"), duration: const Duration(seconds: 1)));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: kWarmWhite.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kWarmWhite.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: kWarmWhite, size: 16),
                          const SizedBox(width: 6),
                          Text(_globalAiModel, style: const TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, color: kWarmWhite, size: 16),
                        ],
                      ),
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: "Лёгкая", child: Text("Лёгкая (Быстрая)")),
                      const PopupMenuItem(value: "Средняя", child: Text("Средняя (Баланс)")),
                      const PopupMenuItem(value: "Сильная", child: Text("Сильная (Макс. качество)")),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Список чатов
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: kWarmWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
                ),
                child: displayedChats.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_outline, size: 50, color: kTextSecondary.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text("В этой папке пока нет чатов", style: TextStyle(color: kTextSecondary.withOpacity(0.5), fontSize: 16)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.only(top: 20, bottom: 100),
                  itemCount: displayedChats.length,
                  itemBuilder: (context, index) {
                    final chat = displayedChats[index];
                    final lastMsg = chat.messages.isNotEmpty ? chat.messages.last.text : "Начать диалог...";
                    bool isArchived = chat.folder == "Архив";

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundColor: kAccentPurple.withOpacity(0.1),
                        child: const Icon(Icons.star_outline, color: kAccentPurple),
                      ),
                      title: Text(chat.title, style: const TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(lastMsg, style: const TextStyle(color: kTextSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: kTextSecondary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        onSelected: (value) {
                          if (value == 'move') _showMoveToFolderDialog(chat);
                          if (value == 'archive') _toggleArchiveChat(chat);
                          if (value == 'delete') _deleteChat(chat);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move_outline, color: kTextPrimary, size: 20), SizedBox(width: 8), Text('Переместить')])),
                          PopupMenuItem(
                              value: 'archive',
                              child: Row(
                                  children: [
                                    Icon(isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, color: kTextPrimary, size: 20),
                                    const SizedBox(width: 8),
                                    Text(isArchived ? 'Из архива' : 'В архив')
                                  ]
                              )
                          ),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: kWeekendRed, size: 20), SizedBox(width: 8), Text('Удалить', style: TextStyle(color: kWeekendRed))])),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(builder: (c) => ActiveChatScreen(chat: chat, initialModel: _globalAiModel))
                        ).then((_) => setState((){}));
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton.extended(
          backgroundColor: kAccentPurple,
          onPressed: _showCreateChatDialog,
          icon: const Icon(Icons.add, color: kWarmWhite),
          label: const Text("Новый чат", style: TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// ----------------------------------------------------
// ЭКРАН АКТИВНОГО ЧАТА
// ----------------------------------------------------

class ActiveChatScreen extends StatefulWidget {
  final ChatThread chat;
  final String initialModel;

  const ActiveChatScreen({super.key, required this.chat, required this.initialModel});

  @override
  _ActiveChatScreenState createState() => _ActiveChatScreenState();
}

class _ActiveChatScreenState extends State<ActiveChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isTyping = false;
  late String _aiModel;
  Timer? _typewriterTimer;

  // Новые переменные для плана лечения
  bool _isGuidedMode = false;
  // В реальности это должно приходить из профиля пользователя. Пока для теста ставим true.
  final bool _hasCarePlan = true;

  @override
  void initState() {
    super.initState();
    _aiModel = widget.initialModel;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    setState(() {
      widget.chat.messages.add(ChatMessage(text: _controller.text.trim(), isUser: true, timestamp: DateTime.now()));
      _controller.clear();
      _isTyping = true;
      _scrollToBottom();

      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        // Текст ответа теперь зависит от того, включен ли режим "По плану"
        String prefix = _isGuidedMode ? "[Режим Плана Лечения] " : "";
        _generateAiResponse("$prefixЭто пример ответа от ИИ. Я генерирую текст постепенно, чтобы создать ощущение живого общения. Модель: $_aiModel.");
      });
    });
  }

  void _generateAiResponse(String fullText) {
    setState(() {
      _isTyping = false;
      widget.chat.messages.add(ChatMessage(text: "", isUser: false, timestamp: DateTime.now()));
    });

    int currentIndex = 0;

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (currentIndex < fullText.length) {
        setState(() {
          widget.chat.messages.last.text += fullText[currentIndex];
          currentIndex++;
        });
        _scrollToBottom();
      } else {
        timer.cancel();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kWarmWhite,
      appBar: AppBar(
        backgroundColor: kWarmWhite,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: kTextPrimary), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chat.title, style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Папка: ${widget.chat.folder}", style: const TextStyle(color: kAccentPurple, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          // Новая кнопка "По плану"
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: InkWell(
                onTap: _hasCarePlan ? () {
                  setState(() {
                    _isGuidedMode = !_isGuidedMode;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(_isGuidedMode ? "Включен режим по плану лечения" : "Свободный режим"),
                          duration: const Duration(seconds: 1)
                      )
                  );
                } : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("План лечения еще не назначен специалистом"),
                          backgroundColor: kWeekendRed,
                          duration: Duration(seconds: 2)
                      )
                  );
                },
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _hasCarePlan
                        ? (_isGuidedMode ? kAccentPurple : kWarmWhite)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _hasCarePlan ? kAccentPurple.withOpacity(0.3) : Colors.grey.withOpacity(0.3)
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _isGuidedMode ? Icons.health_and_safety : Icons.chat_bubble_outline,
                          color: _hasCarePlan ? (_isGuidedMode ? kWarmWhite : kAccentPurple) : Colors.grey,
                          size: 16
                      ),
                      const SizedBox(width: 6),
                      Text(
                          "По плану",
                          style: TextStyle(
                              color: _hasCarePlan ? (_isGuidedMode ? kWarmWhite : kAccentPurple) : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13
                          )
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Выбор модели ИИ
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: PopupMenuButton<String>(
                initialValue: _aiModel,
                tooltip: "Изменить модель ИИ",
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                onSelected: (val) {
                  setState(() => _aiModel = val);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Выбрана модель: $val"), duration: const Duration(seconds: 1)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: kAccentPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kAccentPurple.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: kAccentPurple, size: 16),
                      const SizedBox(width: 6),
                      Text(_aiModel, style: const TextStyle(color: kAccentPurple, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, color: kAccentPurple, size: 16),
                    ],
                  ),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: "Лёгкая", child: Text("Лёгкая")),
                  const PopupMenuItem(value: "Средняя", child: Text("Средняя")),
                  const PopupMenuItem(value: "Сильная", child: Text("Сильная")),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: widget.chat.messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == widget.chat.messages.length && _isTyping) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: kDeepPurple,
                          child: Icon(Icons.star_outline, color: kWarmWhite, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: const Text("Анализирует...", style: TextStyle(color: kTextSecondary, fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                  );
                }

                final m = widget.chat.messages[index];
                final isUser = m.isUser;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isUser) ...[
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: kDeepPurple,
                          child: Icon(Icons.star_outline, color: kWarmWhite, size: 16),
                        ),
                        const SizedBox(width: 8),
                      ],

                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: isUser ? kAccentPurple : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isUser ? 20 : 0),
                              bottomRight: Radius.circular(isUser ? 0 : 20),
                            ),
                            boxShadow: [
                              if (!isUser) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                            ],
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              color: isUser ? kWarmWhite : kTextPrimary,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),

                      if (isUser) ...[
                        const SizedBox(width: 8),
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: kDeepPurple,
                          child: Icon(Icons.person, color: kWarmWhite, size: 18),
                        ),
                      ]
                    ],
                  ),
                );
              },
            ),
          ),

          Container(
            padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              color: kWarmWhite,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, -5))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: kDeepPurple.withOpacity(0.3)),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(color: kTextPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Опишите ваши мысли...',
                        hintStyle: TextStyle(color: kTextSecondary),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(color: kAccentPurple, shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: kWarmWhite, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}