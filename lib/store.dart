import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'settings.dart';

/// Hive-backed local persistence for projects, conversations, messages, moods
/// and the app-wide default settings. Values are plain JSON-compatible maps.
class Store {
  static const _convBoxName = 'conversations_v1';
  static const _moodBoxName = 'moods_v2'; // v2: keys scoped by project
  static const _projBoxName = 'projects_v1';
  static const _appBoxName = 'app_v1';

  /// Mood scope used for project-less ("New chat") conversations.
  static const defaultMoodScope = '_default';

  static late Box _convBox;
  static late Box _moodBox;
  static late Box _projBox;
  static late Box _appBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _convBox = await Hive.openBox(_convBoxName);
    _moodBox = await Hive.openBox(_moodBoxName);
    _projBox = await Hive.openBox(_projBoxName);
    _appBox = await Hive.openBox(_appBoxName);

    if (_convBox.isEmpty && _projBox.isEmpty) {
      await saveConversation(Conversation(
        id: Conversation.newId(),
        name: '哥哥宝宝',
        createdAt: DateTime.now(),
      ));
    }
  }

  // --- App-wide default settings --------------------------------

  static AppSettings loadGlobalSettings() {
    final raw = _appBox.get('globalSettings');
    final data = raw is Map
        ? Map<String, dynamic>.from(raw.cast<String, dynamic>())
        : <String, dynamic>{};
    return AppSettings.fromMap(
      data,
      writer: (m) async {
        await _appBox.put('globalSettings', m);
      },
    );
  }

  // --- Projects --------------------------------------------------

  static List<Project> projects() {
    final list = _projBox.values
        .map((e) => Project.fromJson(Map.from(e as Map)))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static Project? project(String id) {
    final raw = _projBox.get(id);
    return raw == null ? null : Project.fromJson(Map.from(raw as Map));
  }

  static Future<void> saveProject(Project p) => _projBox.put(p.id, p.toJson());

  static Future<void> deleteProject(String id) async {
    await _projBox.delete(id);
    for (final c in conversationsFor(id)) {
      await _convBox.delete(c.id);
    }
    final moodKeys = _moodBox.keys
        .where((k) => k.toString().startsWith('$id::'))
        .toList();
    for (final k in moodKeys) {
      await _moodBox.delete(k);
    }
  }

  /// A live [AppSettings] view of a project's settings that writes changes
  /// back into the project record.
  static AppSettings projectSettings(Project p) {
    final data = Map<String, dynamic>.from(p.settings);
    data['instructions'] = p.instructions; // top-level field wins
    return AppSettings.fromMap(
      data,
      writer: (m) async {
        p.settings = m;
        await saveProject(p);
      },
    );
  }

  // --- Conversations ------------------------------------------

  /// Conversations whose `projectId` matches [projectId] (null = project-less),
  /// most-recently-active first.
  static List<Conversation> conversationsFor(String? projectId) {
    final list = _convBox.values
        .map((e) => Conversation.fromJson(Map.from(e as Map)))
        .where((c) => c.projectId == projectId)
        .toList();
    list.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return list;
  }

  static Conversation? conversation(String id) {
    final raw = _convBox.get(id);
    return raw == null ? null : Conversation.fromJson(Map.from(raw as Map));
  }

  static Future<void> saveConversation(Conversation c) =>
      _convBox.put(c.id, c.toJson());

  static Future<void> deleteConversation(String id) => _convBox.delete(id);

  // --- Moods (scoped by project) ----------------------------

  static String _moodKey(String scope, String date) => '$scope::$date';

  static List<MoodEntry> allMoods(String scope) {
    final prefix = '$scope::';
    final list = <MoodEntry>[];
    for (final k in _moodBox.keys) {
      if (k.toString().startsWith(prefix)) {
        list.add(MoodEntry.fromJson(Map.from(_moodBox.get(k) as Map)));
      }
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static MoodEntry moodFor(String scope, DateTime day) {
    final raw = _moodBox.get(_moodKey(scope, dateKey(day)));
    if (raw == null) return MoodEntry(date: dateKey(day));
    return MoodEntry.fromJson(Map.from(raw as Map));
  }

  static Future<void> saveMood(String scope, MoodEntry entry) async {
    final key = _moodKey(scope, entry.date);
    if (entry.isEmpty) {
      await _moodBox.delete(key);
    } else {
      await _moodBox.put(key, entry.toJson());
    }
  }

  // --- Media files ------------------------------------------

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
