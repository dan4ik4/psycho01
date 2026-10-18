import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/widgets/oakle_notice.dart';
import '../features/chat/data/chat_repository.dart';

const Color _deepPurple = Color(0xFFB0A6E8);
const Color _accentPurple = Color(0xFF7862D6);
const Color _warmWhite = Color(0xFFF6F8FD);
const Color _textPrimary = Color(0xFF323045);
const Color _textSecondary = Color(0xFF706D8C);

class ChatScreen extends StatefulWidget {
  final ApiClient apiClient;
  final bool isPsychologist;
  final VoidCallback? onOpenPsychologistClients;
  const ChatScreen({
    super.key,
    required this.apiClient,
    this.isPsychologist = false,
    this.onOpenPsychologistClients,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatRepository _repository = ChatRepository(
    apiClient: widget.apiClient,
  );
  List<ChatConversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (widget.isPsychologist) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = null;
        _conversations = [];
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final conversations = await _repository.fetchConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _createConversation() async {
    final nameController = TextEditingController();
    var selectedMode = 'self_help';
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: _warmWhite,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_deepPurple, _accentPurple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    'Новый разговор',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Center(
                  child: Text(
                    'Выберите, чем помощник будет полезен',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textSecondary),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Название (необязательно)',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(
                      Icons.edit_note_rounded,
                      color: _accentPurple,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _chatModeOption(
                  selected: selectedMode == 'self_help',
                  icon: Icons.spa_rounded,
                  title: 'Самопомощь',
                  subtitle: 'Обсудить ситуацию и найти следующий шаг',
                  onTap: () => setDialogState(() => selectedMode = 'self_help'),
                ),
                const SizedBox(height: 10),
                _chatModeOption(
                  selected: selectedMode == 'guided',
                  icon: Icons.favorite_rounded,
                  title: 'По плану психолога',
                  subtitle: 'Продолжить работу по рекомендациям специалиста',
                  onTap: () => setDialogState(() => selectedMode = 'guided'),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text(
                          'Отмена',
                          style: TextStyle(color: _textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, {
                          'name': nameController.text,
                          'mode': selectedMode,
                        }),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Создать'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    if (details == null) return;
    try {
      final conversation = await _repository.createConversation(
        details['name'] ?? '',
        mode: details['mode'] ?? 'self_help',
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveChatScreen(
            conversation: conversation,
            repository: _repository,
          ),
        ),
      );
      _loadConversations();
    } catch (error) {
      if (mounted)
        _showError(
          friendlyApiError(
            error,
            fallback: 'Не удалось создать чат. Попробуйте позже.',
          ),
        );
    }
  }

  Widget _chatModeOption({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFECE8FC) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? _accentPurple : const Color(0xFFE8E5F1),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: selected ? _accentPurple : const Color(0xFFECE8FC),
            foregroundColor: selected ? Colors.white : _accentPurple,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textSecondary, fontSize: 12),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? _accentPurple : _textSecondary,
          ),
        ],
      ),
    ),
  );

  Future<void> _renameConversation(ChatConversation conversation) async {
    final controller = TextEditingController(text: conversation.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await _repository.renameConversation(conversation.id, name);
      await _loadConversations();
    } catch (error) {
      if (mounted)
        _showError(
          friendlyApiError(
            error,
            fallback: 'Не удалось переименовать чат. Попробуйте позже.',
          ),
        );
    }
  }

  void _showError(String message) {
    showOakleNotice(context, message, isError: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _deepPurple,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ИИ-ассистент',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _warmWhite,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: _warmWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accentPurple),
                    )
                  : widget.isPsychologist
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.psychology_alt_outlined,
                              size: 56,
                              color: _accentPurple,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Поддержка для психолога',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Личные ИИ-беседы доступны пациентам. Для подготовки работы с клиентом откройте вкладку «Клиенты» и создайте план поддержки — он станет основой для чата пациента с ИИ.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: widget.onOpenPsychologistClients,
                              icon: const Icon(Icons.people_outline),
                              label: const Text('Открыть клиентов'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Не удалось загрузить чаты.\n$_error',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadConversations,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'Пока нет переписок. Создайте новый чат.',
                        style: TextStyle(color: _textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(top: 14, bottom: 100),
                      itemCount: _conversations.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) {
                        final conversation = _conversations[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 5,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE9E4FA),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              color: _accentPurple,
                            ),
                          ),
                          title: Text(
                            conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            conversation.messages.isEmpty
                                ? 'Начать диалог'
                                : conversation.messages.last.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _textSecondary),
                          ),
                          trailing: IconButton(
                            tooltip: 'Переименовать',
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: _textSecondary,
                            ),
                            onPressed: () => _renameConversation(conversation),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ActiveChatScreen(
                                  conversation: conversation,
                                  repository: _repository,
                                ),
                              ),
                            );
                            _loadConversations();
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    ),
    floatingActionButton: widget.isPsychologist
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 76),
            child: FloatingActionButton.extended(
              backgroundColor: _accentPurple,
              onPressed: _createConversation,
              icon: const Icon(Icons.add, color: _warmWhite),
              label: const Text(
                'Новый чат',
                style: TextStyle(color: _warmWhite),
              ),
            ),
          ),
  );
}

class ActiveChatScreen extends StatefulWidget {
  final ChatConversation conversation;
  final ChatRepository repository;

  const ActiveChatScreen({
    super.key,
    required this.conversation,
    required this.repository,
  });

  @override
  State<ActiveChatScreen> createState() => _ActiveChatScreenState();
}

class _ActiveChatScreenState extends State<ActiveChatScreen> {
  static const _uuid = Uuid();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late ChatConversation _conversation = widget.conversation;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  String? _pendingRequestId;
  String? _pendingRequestContent;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final conversation = await widget.repository.fetchConversation(
        _conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _isLoading = false;
        _error = null;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    _controller.clear();
    setState(() => _isSending = true);
    try {
      if (_pendingRequestContent != text) {
        _createPendingRequest(text);
      }
      final exchange = await widget.repository.sendMessage(
        _conversation.id,
        text,
        requestId: _pendingRequestId,
      );
      _pendingRequestId = null;
      _pendingRequestContent = null;
      if (!mounted) return;
      setState(
        () => _conversation = ChatConversation(
          id: _conversation.id,
          name: _conversation.name,
          mode: _conversation.mode,
          createdAt: _conversation.createdAt,
          messages: [..._conversation.messages, ...exchange],
        ),
      );
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      _controller.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyApiError(
              error,
              fallback: 'Сообщение не отправлено. Попробуйте ещё раз.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _createPendingRequest(String content) {
    _pendingRequestId = _uuid.v4();
    _pendingRequestContent = content;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients)
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _warmWhite,
    appBar: AppBar(
      backgroundColor: _warmWhite,
      title: Text(
        _conversation.name,
        style: const TextStyle(color: _textPrimary),
      ),
      iconTheme: const IconThemeData(color: _textPrimary),
    ),
    body: Column(
      children: [
        if (_conversation.messages.any(
          (message) =>
              !message.isMe &&
              message.text.startsWith('Это тестовый ответ AI.'),
        ))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2D8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Сейчас сервер возвращает тестовые ответы. Подключение настоящей ИИ-модели должен завершить разработчик сервера.',
              style: TextStyle(color: _textPrimary, fontSize: 12),
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: _accentPurple),
                )
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Не удалось загрузить переписку.\n$_error',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                            });
                            _loadHistory();
                          },
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      _conversation.messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _conversation.messages.length)
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    final message = _conversation.messages[index];
                    return Align(
                      alignment: message.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * .78,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: message.isMe
                              ? _accentPurple
                              : const Color(0xFFECE9F5),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          message.text,
                          style: TextStyle(
                            color: message.isMe ? Colors.white : _textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Напишите сообщение',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : _sendMessage,
                  style: IconButton.styleFrom(backgroundColor: _accentPurple),
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
