import 'dart:io';

import 'package:flutter/material.dart';

import 'image_viewer.dart';
import 'models.dart';
import 'settings.dart';

const Color _accent = Color(0xFF07C160);

/// In-conversation search (requirement 二). Pops with a [DateTime] when the
/// user picks a day / a result, so the chat screen can scroll there.
class SearchScreen extends StatefulWidget {
  final Conversation conversation;
  final AppSettings settings;

  const SearchScreen({
    super.key,
    required this.conversation,
    required this.settings,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  List<ChatMessage> get _messages => widget.conversation.messages;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDateCalendar() async {
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) =>
            DateCalendarScreen(conversation: widget.conversation),
      ),
    );
    if (picked != null && mounted) Navigator.of(context).pop(picked);
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  List<ChatMessage> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _messages
        .where((m) => (m.text ?? '').toLowerCase().contains(q))
        .toList()
        .reversed
        .toList();
  }

  Widget _categoryChips() {
    Widget chip(IconData icon, String label, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ActionChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          onPressed: onTap,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          chip(Icons.calendar_today_outlined, '日期', _openDateCalendar),
          chip(Icons.perm_media_outlined, '图片与视频',
              () => _push(MediaGridScreen(conversation: widget.conversation))),
          chip(Icons.insert_drive_file_outlined, '文件',
              () => _push(FileListScreen(conversation: widget.conversation))),
        ],
      ),
    );
  }

  Widget _resultsList() {
    if (_query.trim().isEmpty) {
      return const Expanded(
        child: Center(
          child: Text('输入关键词搜索聊天记录',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final results = _results;
    if (results.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text('没有找到相关聊天记录',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return Expanded(
      child: ListView.separated(
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final m = results[index];
          return ListTile(
            leading: Icon(m.isMe ? Icons.person : Icons.face,
                color: Colors.black45),
            title: Text.rich(_highlight(m.text ?? '', _query.trim())),
            subtitle: Text(formatFullStamp(m.time),
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.of(context).pop(m.time),
          );
        },
      ),
    );
  }

  TextSpan _highlight(String text, String query) {
    final base = const TextStyle(color: Colors.black87, fontSize: 14);
    const hit = TextStyle(
        color: _accent, fontSize: 14, fontWeight: FontWeight.bold);
    if (query.isEmpty) return TextSpan(text: text, style: base);
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    var start = 0;
    while (true) {
      final i = lower.indexOf(q, start);
      if (i < 0) {
        spans.add(TextSpan(text: text.substring(start), style: base));
        break;
      }
      if (i > start) {
        spans.add(TextSpan(text: text.substring(start, i), style: base));
      }
      spans.add(TextSpan(text: text.substring(i, i + q.length), style: hit));
      start = i + q.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search,
                              size: 18, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isCollapsed: true,
                                hintText: '搜索',
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              child: const Icon(Icons.cancel,
                                  size: 16, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            _categoryChips(),
            const Divider(height: 1),
            _resultsList(),
          ],
        ),
      ),
    );
  }
}

/// Calendar "find by date" view (requirement 二.4).
class DateCalendarScreen extends StatefulWidget {
  final Conversation conversation;
  const DateCalendarScreen({super.key, required this.conversation});

  @override
  State<DateCalendarScreen> createState() => _DateCalendarScreenState();
}

class _DateCalendarScreenState extends State<DateCalendarScreen> {
  late DateTime _month;
  late Set<String> _daysWithMessages;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _daysWithMessages =
        widget.conversation.messages.map((m) => dateKey(m.time)).toSet();
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final cells = monthMatrix(_month);
    return Scaffold(
      appBar: AppBar(title: const Text('按日期查找')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text('${_month.year} 年 ${_month.month} 月',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final w in kWeekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.count(
              crossAxisCount: 7,
              children: [
                for (final day in cells)
                  if (day == null)
                    const SizedBox.shrink()
                  else
                    _DayCell(
                      day: day,
                      hasMessages:
                          _daysWithMessages.contains(dateKey(day)),
                      onTap: _daysWithMessages.contains(dateKey(day))
                          ? () => Navigator.of(context).pop(day)
                          : null,
                    ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('加粗并有圆点的日期有聊天记录，点击跳转',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool hasMessages;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.hasMessages,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = dateKey(day) == dateKey(now);
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      hasMessages ? FontWeight.bold : FontWeight.normal,
                  color: hasMessages ? Colors.black : Colors.black45,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasMessages ? _accent : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of every image / video sent in the conversation (requirement 二.5).
class MediaGridScreen extends StatelessWidget {
  final Conversation conversation;
  const MediaGridScreen({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final media = conversation.messages
        .where((m) => m.isMedia && m.mediaPath != null)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('图片与视频')),
      body: media.isEmpty
          ? const Center(
              child: Text('还没有图片或视频',
                  style: TextStyle(color: Colors.grey)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: media.length,
              itemBuilder: (context, index) {
                final m = media[index];
                return GestureDetector(
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ImageViewerScreen(
                        path: m.mediaPath!, heroTag: 'grid_${m.id}'),
                  )),
                  child: Hero(
                    tag: 'grid_${m.id}',
                    child: Image.file(File(m.mediaPath!),
                        fit: BoxFit.cover),
                  ),
                );
              },
            ),
    );
  }
}

/// List of every file sent in the conversation (requirement 二.6).
class FileListScreen extends StatelessWidget {
  final Conversation conversation;
  const FileListScreen({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final files = conversation.messages
        .where((m) => m.kind == MessageKind.file)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('文件')),
      body: files.isEmpty
          ? const Center(
              child: Text('还没有文件', style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              itemCount: files.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final m = files[index];
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(m.fileName ?? '文件'),
                  subtitle: Text(formatFullStamp(m.time),
                      style: const TextStyle(fontSize: 12)),
                );
              },
            ),
    );
  }
}
