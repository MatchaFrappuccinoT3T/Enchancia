import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'models.dart';
import 'mood_calendar_screen.dart';
import 'settings.dart';
import 'store.dart';

/// App home: the list of all conversations (requirement 一).
class ConversationListScreen extends StatefulWidget {
  final AppSettings settings;
  const ConversationListScreen({super.key, required this.settings});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  AppSettings get _s => widget.settings;
  List<Conversation> _conversations = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _conversations = Store.conversations());

  Future<void> _openConversation(Conversation c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(conversation: c, settings: _s),
    ));
    if (mounted) _reload();
  }

  Future<void> _newConversation() async {
    final controller = TextEditingController(text: _s.chatTitle);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '对话名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('创建')),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null) return;

    final conv = Conversation(
      id: Conversation.newId(),
      name: trimmed.isEmpty ? '新对话' : trimmed,
      createdAt: DateTime.now(),
    );
    await Store.saveConversation(conv);
    if (!mounted) return;
    _reload();
    _openConversation(conv);
  }

  Future<bool> _confirmDelete(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除与「${c.name}」的对话吗？记录将无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _avatar(Conversation c) {
    final path = c.aiAvatarPath ?? _s.aiAvatarPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(path), width: 48, height: 48, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFE0D0D0),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        c.name.isNotEmpty ? c.name.substring(0, 1) : '哥',
        style: const TextStyle(fontSize: 18, color: Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _s.isDark ? const Color(0xFF161616) : Colors.white,
      appBar: AppBar(
        title: const Text('Enchancia',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _s.appBarColor,
        foregroundColor: _s.appBarTextColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: '心情日历',
            icon: const Icon(Icons.emoji_emotions_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MoodCalendarScreen(settings: _s),
            )),
          ),
          IconButton(
            tooltip: '新建对话',
            icon: const Icon(Icons.add),
            onPressed: _newConversation,
          ),
        ],
      ),
      body: _conversations.isEmpty
          ? const Center(
              child: Text('还没有对话，点右上角 + 新建',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              itemCount: _conversations.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 72,
                color: _s.isDark ? Colors.white12 : Colors.black12,
              ),
              itemBuilder: (context, index) {
                final c = _conversations[index];
                return Dismissible(
                  key: ValueKey(c.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(c),
                  onDismissed: (_) {
                    Store.deleteConversation(c.id);
                    _reload();
                  },
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    leading: _avatar(c),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          formatListTime(c.sortTime),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      c.preview.isEmpty ? '（暂无消息）' : c.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    onTap: () => _openConversation(c),
                  ),
                );
              },
            ),
    );
  }
}
