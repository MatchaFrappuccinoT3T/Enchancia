import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Hive-backed local persistence for conversations, messages and moods.
///
/// Values are stored as plain JSON-compatible maps (no TypeAdapters, no
/// build_runner), which keeps the schema easy to evolve.
class Store {
  static const _convBoxName = 'conversations_v1';
  static const _moodBoxName = 'moods_v1';

  static late Box _convBox;
  static late Box _moodBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _convBox = await Hive.openBox(_convBoxName);
    _moodBox = await Hive.openBox(_moodBoxName);

    if (_convBox.isEmpty) {
      final now = DateTime.now();
      await saveConversation(Conversation(
        id: Conversation.newId(),
        name: '哥哥宝宝',
        createdAt: now,
      ));
    }
  }

  // --- Conversations ---------------------------------------------------

  /// All conversations, most-recently-active first.
  static List<Conversation> conversations() {
    final list = _convBox.values
        .map((e) => Conversation.fromJson(Map.from(e as Map)))
        .toList();
    list.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return list;
  }

  static Conversation? conversation(String id) {
    final raw = _convBox.get(id);
    if (raw == null) return null;
    return Conversation.fromJson(Map.from(raw as Map));
  }

  static Future<void> saveConversation(Conversation c) =>
      _convBox.put(c.id, c.toJson());

  static Future<void> deleteConversation(String id) => _convBox.delete(id);

  // --- Moods --------------------------------------------------------

  static List<MoodEntry> allMoods() {
    final list = _moodBox.values
        .map((e) => MoodEntry.fromJson(Map.from(e as Map)))
        .toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static MoodEntry moodFor(DateTime day) {
    final key = dateKey(day);
    final raw = _moodBox.get(key);
    if (raw == null) return MoodEntry(date: key);
    return MoodEntry.fromJson(Map.from(raw as Map));
  }

  static Future<void> saveMood(MoodEntry entry) async {
    if (entry.isEmpty) {
      await _moodBox.delete(entry.date);
    } else {
      await _moodBox.put(entry.date, entry.toJson());
    }
  }

  // --- Media files ------------------------------------------------

  /// Copy a picked file into the app documents directory (persistent, never a
  /// temp dir) so it survives restarts and the OS clearing the image_picker
  /// cache. Returns the new path.
  static Future<String> persistFile(String srcPath, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final media = Directory('${dir.path}/media');
    if (!media.existsSync()) media.createSync(recursive: true);
    final ext = srcPath.contains('.')
        ? srcPath.split('.').last.split('?').first
        : 'dat';
    final safeExt = ext.length <= 5 ? ext : 'dat';
    final dest =
        '${media.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}.$safeExt';
    await File(srcPath).copy(dest);
    return dest;
  }
}
