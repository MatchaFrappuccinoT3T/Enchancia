import 'package:flutter/material.dart';

import 'models.dart';
import 'settings.dart';
import 'store.dart';

const Color _accent = Color(0xFF07C160);

/// Emojis offered in the mood picker (mostly faces).
const List<String> _moodEmojis = [
  '😀', '😁', '😂', '🤣', '😊', '😍', '🥰', '😘',
  '😎', '🤗', '🤔', '😴', '😭', '😅', '🙃', '😌',
  '😏', '😢', '😤', '😐', '😑', '🙄', '😔', '😪',
  '😷', '🤒', '🥳', '😇', '🤩', '😋', '😬', '🥺',
];

enum _MoodView { all, month, calendar }

class MoodCalendarScreen extends StatefulWidget {
  final AppSettings settings;
  const MoodCalendarScreen({super.key, required this.settings});

  @override
  State<MoodCalendarScreen> createState() => _MoodCalendarScreenState();
}

class _MoodCalendarScreenState extends State<MoodCalendarScreen> {
  _MoodView _view = _MoodView.calendar;
  late DateTime _month;
  List<MoodEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _reload();
  }

  void _reload() => setState(() => _entries = Store.allMoods());

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Map<String, MoodEntry> get _byDate => {for (final e in _entries) e.date: e};

  // --- Editor -------------------------------------------------------

  Future<void> _editDay(DateTime day) async {
    final entry = Store.moodFor(day);
    String? ai = entry.aiEmoji;
    String? me = entry.meEmoji;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Widget section(
                String title, String? current, ValueChanged<String?> onPick) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text(current ?? '未选择',
                          style: const TextStyle(color: Colors.grey)),
                      const Spacer(),
                      if (current != null)
                        TextButton(
                          onPressed: () => setModal(() => onPick(null)),
                          child: const Text('清除'),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in _moodEmojis)
                        GestureDetector(
                          onTap: () => setModal(() => onPick(e)),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: e == current
                                  ? _accent.withValues(alpha: 0.15)
                                  : null,
                            ),
                            child: Text(e,
                                style: const TextStyle(fontSize: 24)),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${day.year}年${day.month}月${day.day}日 心情',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    section('AI 的心情（暂由后端填入，可手动）', ai, (v) => ai = v),
                    const SizedBox(height: 20),
                    section('我的心情', me, (v) => me = v),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          await Store.saveMood(MoodEntry(
                            date: dateKey(day),
                            aiEmoji: ai,
                            meEmoji: me,
                          ));
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) _reload();
  }

  // --- Views ------------------------------------------------------

  Widget _monthSwitcher() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }

  Widget _calendarView() {
    final cells = monthMatrix(_month);
    final map = _byDate;
    return Column(
      children: [
        _monthSwitcher(),
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
            childAspectRatio: 0.8,
            children: [
              for (final day in cells)
                if (day == null)
                  const SizedBox.shrink()
                else
                  _MoodDayCell(
                    day: day,
                    entry: map[dateKey(day)],
                    onTap: () => _editDay(day),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _listView({bool filterMonth = false}) {
    var entries = _entries;
    if (filterMonth) {
      final prefix =
          '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      entries = entries.where((e) => e.date.startsWith(prefix)).toList();
    }
    return Column(
      children: [
        if (filterMonth) _monthSwitcher(),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text('还没有记录心情',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    final parts = e.date.split('-');
                    final day = DateTime(int.parse(parts[0]),
                        int.parse(parts[1]), int.parse(parts[2]));
                    return ListTile(
                      title: Text('${day.month}月${day.day}日'),
                      subtitle: Text(e.date,
                          style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('AI ',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          Text(e.aiEmoji ?? '—',
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Text('我 ',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          Text(e.meEmoji ?? '—',
                              style: const TextStyle(fontSize: 22)),
                        ],
                      ),
                      onTap: () => _editDay(day),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('心情日历')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<_MoodView>(
              segments: const [
                ButtonSegment(value: _MoodView.all, label: Text('All')),
                ButtonSegment(value: _MoodView.month, label: Text('月份')),
                ButtonSegment(
                    value: _MoodView.calendar, label: Text('Calendar')),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(
            child: switch (_view) {
              _MoodView.all => _listView(),
              _MoodView.month => _listView(filterMonth: true),
              _MoodView.calendar => _calendarView(),
            },
          ),
        ],
      ),
    );
  }
}

class _MoodDayCell extends StatelessWidget {
  final DateTime day;
  final MoodEntry? entry;
  final VoidCallback onTap;

  const _MoodDayCell({
    required this.day,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = dateKey(day) == dateKey(DateTime.now());
    final ai = entry?.aiEmoji;
    final me = entry?.meEmoji;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11,
                color: isToday ? _accent : Colors.black54,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ai ?? '·',
                    style: TextStyle(
                        fontSize: ai != null ? 14 : 12,
                        color: ai != null ? null : Colors.black26)),
                const SizedBox(width: 1),
                Text(me ?? '·',
                    style: TextStyle(
                        fontSize: me != null ? 14 : 12,
                        color: me != null ? null : Colors.black26)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
