import 'package:flutter/material.dart';

import 'conversation_list_screen.dart';
import 'models.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'store.dart';

/// Outermost home: project-less chats + the list of projects (requirement 五).
class ProjectListScreen extends StatefulWidget {
  final AppSettings globalSettings;
  const ProjectListScreen({super.key, required this.globalSettings});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Project> _projects = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _projects = Store.projects());

  Future<void> _openProject(Project p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationListScreen(
        project: p,
        globalSettings: widget.globalSettings,
      ),
    ));
    if (mounted) _reload();
  }

  Future<void> _openPlainChats() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationListScreen(
        project: null,
        globalSettings: widget.globalSettings,
      ),
    ));
    if (mounted) _reload();
  }

  Future<void> _newProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建项目'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: '项目名称'),
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
    if (trimmed == null || trimmed.isEmpty) return;
    final p = Project(
      id: Project.newId(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    await Store.saveProject(p);
    if (!mounted) return;
    _reload();
    _openProject(p);
  }

  Future<bool> _confirmDelete(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('删除「${p.name}」及其下所有对话和心情日历？不可恢复。'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enchancia',
            style: TextStyle(fontWeight: FontWeight.bold)),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: '默认聊天样式',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(settings: widget.globalSettings),
            )),
          ),
          IconButton(
            tooltip: '新建项目',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _newProject,
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8A0BF),
              child: Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
            title: const Text('普通聊天',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('不属于任何项目 · 默认样式'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: _openPlainChats,
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('项目',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          if (_projects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('还没有项目，点右上角新建',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          for (final p in _projects)
            Dismissible(
              key: ValueKey(p.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(p),
              onDismissed: (_) {
                Store.deleteProject(p.id);
                _reload();
              },
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: ListTile(
                leading: Text(p.icon, style: const TextStyle(fontSize: 28)),
                title: Text(p.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${Store.conversationsFor(p.id).length} 个对话',
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => _openProject(p),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
