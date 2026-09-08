import 'dart:io';

import 'package:flutter/material.dart';

import 'image_viewer.dart';
import 'models.dart';
import 'settings.dart';

const Color _accent = Color(0xFFE8A0BF);

/// Where a search result points: a conversation + the message's time, so the
/// caller can open that conversation and scroll to it.
class SearchHit {
  final String conversationId;
  final DateTime time;
  const SearchHit(this.conversationId, this.time);
}

class _Located {
  final Conversation conv;
  final ChatMessage msg;
  const _Located(this.conv, this.msg);
}

/// Project-wide search across every conversation in [conversations]
/// (requirement 五.8). Pops with a [SearchHit].
class SearchScreen extends StatefulWidget {
  final List<Conversation> conversations;
  final AppSettings settings;

  const SearchScreen({
    super.key,
    required this.conversations,
    required this.settings,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  bool get _multi => widget.conversations.length > 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Located> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_Located>[];
    for (final c in widget.conversations) {
      for (final m in c.messages.reversed) {
        if ((m.text ?? '').toLowerCase().contains(q)) {
          out.add(_Located(c, m));
        }
      }
    }
    out.sort((a, b) => b.msg.time.compareTo(a.msg.time));
    return out;
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _openDateCalendar() async {
    final hit = await Navigator.of(context).push<SearchHit>(
      MaterialPageRoute(
        builder: (_) => DateCalendarScreen(conversations: widget.conversations),
      ),
    );
    if (hit != null && mounted) Navigator.of(context).pop(hit);
  }

  Widget _categoryChips() {
    Widget chip(IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: onTap,
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          chip(Icons.calendar_today_outlined, '日期', _openDateCalendar),
          chip(Icons.perm_media_outlined, '图片与视频',
              () => _push(MediaGridScreen(conversations: widget.conversations))),
          chip(Icons.insert_drive_file_outlined, '文件',
              () => _push(FileListScreen(conversations: widget.conversations))),
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
          final r = results[index];
          return ListTile(
            leading: Icon(r.msg.isMe ? Icons.person : Icons.face,
                color: Colors.black45),
            title: Text.rich(_highlight(r.msg.text ?? '', _query.trim())),
            subtitle: Text(
              _multi
                  ? '${r.conv.name} · ${formatFullStamp(r.msg.time)}'
                  : formatFullStamp(r.msg.time),
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () =>
                Navigator.of(context).pop(SearchHit(r.conv.id, r.msg.time)),
          );
        },
      ),
    );
  }

  TextSpan _highlight(String text, String query) {
    const base = TextStyle(color: Colors.black87, fontSize: 14);
    const hit = TextStyle(
        color: _accent, fontSize: 14, fontWeight: FontWeight.bold);
    if (query.isEmpty) return const TextSpan(text: '', style: base);
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

/// Calendar "find by date" across all conversations in scope.
class DateCalendarScreen extends StatefulWidget {
  final List<Conversation> conversations;
  const DateCalendarScreen({super.key, required this.conversations});

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
    _daysWithMessages = {
      for (final c in widget.conversations)
        for (final m in c.messages) dateKey(m.time),
    };
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  SearchHit? _hitFor(DateTime day) {
    final key = dateKey(day);
    for (final c in widget.conversations) {
      for (final m in c.messages) {
        if (dateKey(m.time) == key) return SearchHit(c.id, m.time);
      }
    }
    return null;
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
                      hasMessages: _daysWithMessages.contains(dateKey(day)),
                      onTap: _daysWithMessages.contains(dateKey(day))
                          ? () {
                              final hit = _hitFor(day);
                              if (hit != null) Navigator.of(context).pop(hit);
                            }
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
    final isToday = dateKey(day) == dateKey(DateTime.now());
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
                      color: _accent.withValues(alpha: 0.2),
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

/// Grid of every image / video sent across the scoped conversations.
class MediaGridScreen extends StatelessWidget {
  final List<Conversation> conversations;
  const MediaGridScreen({super.key, required this.conversations});

  @override
  Widget build(BuildContext context) {
    final media = [
      for (final c in conversations)
        for (final m in c.messages)
          if (m.isMedia && m.mediaPath != null) m,
    ]..sort((a, b) => b.time.compareTo(a.time));

    return Scaffold(
      appBar: AppBar(title: const Text('图片与视频')),
      body: media.isEmpty
          ? const Center(
              child: Text('还没有图片或视频',
                  style: TextStyle(color: Colors.grey)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: media.length,
              itemBuilder: (context, index) {
                final m = media[index];
                final isVideo = m.kind == MessageKind.video;
                return GestureDetector(
                  onTap: isVideo
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ImageViewerScreen(
                                path: m.mediaPath!, heroTag: 'grid_${m.id}'),
                          )),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (isVideo)
                        Container(
                          color: Colors.black87,
                          alignment: Alignment.center,
                          child: const Icon(Icons.videocam,
                              color: Colors.white70, size: 28),
                        )
                      else
                        Hero(
                          tag: 'grid_${m.id}',
                          child: Image.file(File(m.mediaPath!),
                              fit: BoxFit.cover),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// List of every file sent across the scoped conversations.
class FileListScreen extends StatelessWidget {
  final List<Conversation> conversations;
  const FileListScreen({super.key, required this.conversations});

  @override
  Widget build(BuildContext context) {
    final files = [
      for (final c in conversations)
        for (final m in c.messages)
          if (m.kind == MessageKind.file) m,
    ]..sort((a, b) => b.time.compareTo(a.time));

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
