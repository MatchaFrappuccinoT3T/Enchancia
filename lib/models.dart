/// Plain data models + shared formatting helpers. No Flutter imports so this
/// file stays cheap to reuse everywhere.

/// A generous set of emojis reused by the chat emoji panel and the mood picker.
const List<String> kCommonEmojis = [
  '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😜', '😎', '🤗',
  '🤔', '😴', '😭', '😅', '😉', '🙃', '😌', '😏', '😢', '😤',
  '🥰', '😗', '🙂', '😇', '🤩', '🥳', '😋', '😝', '🤤', '😐',
  '😶', '😑', '😒', '🙄', '😬', '😔', '😪', '😷', '🤒', '🤕',
  '👍', '👎', '👌', '🙏', '👏', '💪', '🤝', '✌️', '🤟', '👋',
  '❤️', '💔', '💕', '💖', '✨', '🌟', '🔥', '🎉', '🌸', '🍺',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// HH:mm:ss — the per-message timestamp under avatars.
String formatClock(DateTime dt) =>
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

/// "x月x日 下午xx:xx" — the in-chat time separator.
String formatSeparator(DateTime dt) {
  final period = dt.hour < 12 ? '上午' : '下午';
  var h = dt.hour % 12;
  if (h == 0) h = 12;
  return '${dt.month}月${dt.day}日 $period${_two(h)}:${_two(dt.minute)}';
}

/// Relative time shown in the conversation list (今天时间 / 昨天 / 星期X / M/D).
String formatListTime(DateTime dt) {
  final now = DateTime.now();
  final d = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff <= 0) return '${_two(dt.hour)}:${_two(dt.minute)}';
  if (diff == 1) return '昨天';
  if (diff < 7) {
    const wk = ['一', '二', '三', '四', '五', '六', '日'];
    return '星期${wk[d.weekday - 1]}';
  }
  return '${dt.month}/${dt.day}';
}

String formatFullStamp(DateTime dt) =>
    '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

/// Stable per-day key, e.g. 2026-09-08.
String dateKey(DateTime dt) => '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

/// 42-slot (6 week x 7 day) matrix for [month]; leading/trailing padding slots
/// are null. Weeks start on Sunday to match WeChat's calendar.
List<DateTime?> monthMatrix(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday % 7; // Sunday -> 0
  final cells = <DateTime?>[];
  for (var i = 0; i < leading; i++) {
    cells.add(null);
  }
  for (var d = 1; d <= daysInMonth; d++) {
    cells.add(DateTime(month.year, month.month, d));
  }
  while (cells.length < 42) {
    cells.add(null);
  }
  return cells;
}

const List<String> kWeekdayLabels = ['日', '一', '二', '三', '四', '五', '六'];

enum MessageKind { text, image, video, file }

class ChatMessage {
  final String id;
  final String? text;

  /// Local file path for image / video / file messages (already copied into
  /// permanent app storage by [Store.persistFile]).
  final String? mediaPath;
  final String? fileName;
  final MessageKind kind;
  final bool isMe;
  final DateTime time;

  /// For outgoing user messages this carries `timestamp` (ISO 8601) so the
  /// backend can answer time-aware questions.
  final Map<String, dynamic> metadata;
  bool favorite;

  ChatMessage({
    required this.id,
    this.text,
    this.mediaPath,
    this.fileName,
    this.kind = MessageKind.text,
    required this.isMe,
    required this.time,
    Map<String, dynamic>? metadata,
    this.favorite = false,
  }) : metadata = metadata ?? const {};

  static String newId() =>
      'm_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
  static int _seq = 0;

  static Map<String, dynamic> outgoingMeta(DateTime now) => {
        'timestamp': now.toIso8601String(),
        'timezone': now.timeZoneName,
        'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
      };

  bool get isMedia => kind == MessageKind.image || kind == MessageKind.video;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'mediaPath': mediaPath,
        'fileName': fileName,
        'kind': kind.name,
        'isMe': isMe,
        'time': time.toIso8601String(),
        'metadata': metadata,
        'favorite': favorite,
      };

  factory ChatMessage.fromJson(Map json) {
    final m = json.cast<String, dynamic>();
    return ChatMessage(
      id: m['id'] as String,
      text: m['text'] as String?,
      mediaPath: m['mediaPath'] as String?,
      fileName: m['fileName'] as String?,
      kind: MessageKind.values.firstWhere(
        (k) => k.name == m['kind'],
        orElse: () => MessageKind.text,
      ),
      isMe: m['isMe'] as bool? ?? false,
      time: DateTime.parse(m['time'] as String),
      metadata: (m['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
      favorite: m['favorite'] as bool? ?? false,
    );
  }
}

class Conversation {
  final String id;
  String name;
  String? aiAvatarPath;
  final DateTime createdAt;
  final List<ChatMessage> messages;

  Conversation({
    required this.id,
    required this.name,
    this.aiAvatarPath,
    required this.createdAt,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  static String newId() => 'c_${DateTime.now().microsecondsSinceEpoch}';

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  DateTime get sortTime => lastMessage?.time ?? createdAt;

  String get preview {
    final m = lastMessage;
    if (m == null) return '';
    return switch (m.kind) {
      MessageKind.image => '[图片]',
      MessageKind.video => '[视频]',
      MessageKind.file => '[文件] ${m.fileName ?? ''}',
      MessageKind.text => m.text ?? '',
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aiAvatarPath': aiAvatarPath,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((e) => e.toJson()).toList(),
      };

  factory Conversation.fromJson(Map json) {
    final m = json.cast<String, dynamic>();
    return Conversation(
      id: m['id'] as String,
      name: m['name'] as String? ?? '对话',
      aiAvatarPath: m['aiAvatarPath'] as String?,
      createdAt:
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      messages: ((m['messages'] as List?) ?? const [])
          .map((e) => ChatMessage.fromJson(e as Map))
          .toList(),
    );
  }
}

class MoodEntry {
  final String date; // dateKey
  String? aiEmoji;
  String? meEmoji;

  MoodEntry({required this.date, this.aiEmoji, this.meEmoji});

  bool get isEmpty => aiEmoji == null && meEmoji == null;

  Map<String, dynamic> toJson() =>
      {'date': date, 'ai': aiEmoji, 'me': meEmoji};

  factory MoodEntry.fromJson(Map json) {
    final m = json.cast<String, dynamic>();
    return MoodEntry(
      date: m['date'] as String,
      aiEmoji: m['ai'] as String?,
      meEmoji: m['me'] as String?,
    );
  }
}
