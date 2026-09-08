import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Font size steps offered in the settings page.
enum FontSizeLevel { small, medium, large }

extension FontSizeLevelX on FontSizeLevel {
  double get messageFontSize => switch (this) {
        FontSizeLevel.small => 14,
        FontSizeLevel.medium => 16,
        FontSizeLevel.large => 19,
      };

  String get label => switch (this) {
        FontSizeLevel.small => '小',
        FontSizeLevel.medium => '中',
        FontSizeLevel.large => '大',
      };
}

/// The three bundled visual presets.
enum ThemePreset { pinkPrincess, dark, minimalWhite }

extension ThemePresetX on ThemePreset {
  String get label => switch (this) {
        ThemePreset.pinkPrincess => '粉色公主风',
        ThemePreset.dark => '暗黑风',
        ThemePreset.minimalWhite => '简约白',
      };

  bool get isDark => this == ThemePreset.dark;

  Color get chatBackground => switch (this) {
        ThemePreset.pinkPrincess => const Color(0xFFFBE4EF),
        ThemePreset.dark => const Color(0xFF1A1A1A),
        ThemePreset.minimalWhite => const Color(0xFFEDEDED),
      };

  Color get myBubble => switch (this) {
        ThemePreset.pinkPrincess => const Color(0xFFFFD6E7),
        ThemePreset.dark => const Color(0xFF3A6E43),
        ThemePreset.minimalWhite => const Color(0xFFFBF0F5),
      };

  Color get aiBubble => switch (this) {
        ThemePreset.pinkPrincess => const Color(0xFFFFFFFF),
        ThemePreset.dark => const Color(0xFF2C2C2E),
        ThemePreset.minimalWhite => const Color(0xFFFFFFFF),
      };
}

/// Notification sounds. [none] means silent; the rest map to bundled assets.
enum NotificationSound { none, ding, dingdong, bubble }

extension NotificationSoundX on NotificationSound {
  String get label => switch (this) {
        NotificationSound.none => '关闭',
        NotificationSound.ding => '叮',
        NotificationSound.dingdong => '叮咚',
        NotificationSound.bubble => '泡泡',
      };

  String? get asset => switch (this) {
        NotificationSound.none => null,
        NotificationSound.ding => 'sounds/ding.wav',
        NotificationSound.dingdong => 'sounds/dingdong.wav',
        NotificationSound.bubble => 'sounds/bubble.wav',
      };
}

/// User-configurable chat settings. Backed by a plain map so the same class
/// serves the app-wide default (persisted in Hive) and each project's own
/// settings (persisted inside the project record). The owner supplies [writer].
class AppSettings extends ChangeNotifier {
  /// Persistence sink: given the current [toMap], store it. Set by the owner.
  Future<void> Function(Map<String, dynamic> data)? writer;

  String chatTitle = '哥哥宝宝';
  String instructions = '';
  Color myBubbleColor = ThemePreset.minimalWhite.myBubble;
  Color aiBubbleColor = ThemePreset.minimalWhite.aiBubble;
  int? wallpaperColorValue;
  String? wallpaperImagePath;
  String? myAvatarPath;
  String? aiAvatarPath;
  FontSizeLevel fontSize = FontSizeLevel.medium;
  ThemePreset theme = ThemePreset.minimalWhite;
  NotificationSound sound = NotificationSound.ding;
  double myBubbleOpacity = 1.0;
  double aiBubbleOpacity = 1.0;
  double wallpaperBlur = 0.0;
  double overlayOpacity = 0.0;

  AppSettings();

  factory AppSettings.fromMap(
    Map<String, dynamic> data, {
    Future<void> Function(Map<String, dynamic>)? writer,
  }) {
    final s = AppSettings()..writer = writer;
    s.applyMap(data);
    return s;
  }

  // --- Serialization -------------------------------------------------

  Map<String, dynamic> toMap() => {
        'chatTitle': chatTitle,
        'instructions': instructions,
        'myBubbleColor': myBubbleColor.toARGB32(),
        'aiBubbleColor': aiBubbleColor.toARGB32(),
        'wallpaperColorValue': wallpaperColorValue,
        'wallpaperImagePath': wallpaperImagePath,
        'myAvatarPath': myAvatarPath,
        'aiAvatarPath': aiAvatarPath,
        'fontSize': fontSize.index,
        'theme': theme.index,
        'sound': sound.index,
        'myBubbleOpacity': myBubbleOpacity,
        'aiBubbleOpacity': aiBubbleOpacity,
        'wallpaperBlur': wallpaperBlur,
        'overlayOpacity': overlayOpacity,
      };

  void applyMap(Map<String, dynamic> raw) {
    final m = raw.cast<String, dynamic>();
    double d(Object? v, double fb) => (v as num?)?.toDouble() ?? fb;
    int i(Object? v, int fb) => (v as num?)?.toInt() ?? fb;

    chatTitle = (m['chatTitle'] as String?) ?? chatTitle;
    instructions = (m['instructions'] as String?) ?? instructions;
    myBubbleColor = _colorOr(m['myBubbleColor'] as int?, myBubbleColor);
    aiBubbleColor = _colorOr(m['aiBubbleColor'] as int?, aiBubbleColor);
    wallpaperColorValue = m['wallpaperColorValue'] as int?;
    wallpaperImagePath = _existingPath(m['wallpaperImagePath'] as String?);
    myAvatarPath = _existingPath(m['myAvatarPath'] as String?);
    aiAvatarPath = _existingPath(m['aiAvatarPath'] as String?);
    fontSize =
        FontSizeLevel.values[i(m['fontSize'], fontSize.index).clamp(0, 2)];
    theme = ThemePreset.values[i(m['theme'], theme.index).clamp(0, 2)];
    sound = NotificationSound.values[i(m['sound'], sound.index).clamp(0, 3)];
    myBubbleOpacity = d(m['myBubbleOpacity'], myBubbleOpacity).clamp(0.0, 1.0);
    aiBubbleOpacity = d(m['aiBubbleOpacity'], aiBubbleOpacity).clamp(0.0, 1.0);
    wallpaperBlur = d(m['wallpaperBlur'], wallpaperBlur).clamp(0.0, 20.0);
    overlayOpacity = d(m['overlayOpacity'], overlayOpacity).clamp(0.0, 1.0);
  }

  Future<void> _flush() async {
    await writer?.call(toMap());
  }

  // --- Derived values ---------------------------------------------

  bool get isDark => theme.isDark;

  Color get chatBackgroundColor => wallpaperColorValue != null
      ? Color(wallpaperColorValue!)
      : theme.chatBackground;

  Color get appBarColor => isDark ? const Color(0xFF1F1F1F) : Colors.white;
  Color get appBarTextColor => isDark ? Colors.white : Colors.black;
  Color get panelColor =>
      isDark ? const Color(0xFF262626) : const Color(0xFFF7F7F7);
  Color get menuColor => isDark ? const Color(0xFF2C2C2C) : Colors.white;

  double get messageFontSize => fontSize.messageFontSize;

  Color get overlayColor => isDark ? Colors.black : Colors.white;

  Color get effectiveMyBubbleColor => myBubbleColor
      .withValues(alpha: (myBubbleColor.a * myBubbleOpacity).clamp(0.0, 1.0));

  Color get effectiveAiBubbleColor => aiBubbleColor
      .withValues(alpha: (aiBubbleColor.a * aiBubbleOpacity).clamp(0.0, 1.0));

  Color get _wallpaperBaseColor {
    if (wallpaperColorValue != null) return Color(wallpaperColorValue!);
    if (wallpaperImagePath != null) {
      return isDark ? const Color(0xFF333333) : const Color(0xFFBFBFBF);
    }
    return theme.chatBackground;
  }

  Color _behindBubbleText(bool isMe) {
    var bg = _wallpaperBaseColor;
    if (overlayOpacity > 0) {
      bg = Color.alphaBlend(
          overlayColor.withValues(alpha: overlayOpacity.clamp(0.0, 1.0)), bg);
    }
    final bubble = isMe ? effectiveMyBubbleColor : effectiveAiBubbleColor;
    return Color.alphaBlend(bubble, bg);
  }

  Color bubbleTextColorFor(bool isMe) =>
      _behindBubbleText(isMe).computeLuminance() > 0.5
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFF2F2F2);

  bool bubbleTextNeedsHalo(bool isMe) {
    final a = (isMe ? effectiveMyBubbleColor : effectiveAiBubbleColor).a;
    return a < 0.35;
  }

  Color get bubbleTextColor =>
      isDark ? const Color(0xFFEDEDED) : Colors.black87;

  Color get inputFieldColor =>
      isDark ? const Color(0xFF2C2C2C) : Colors.white;

  Color get inputTextColor => inputFieldColor.computeLuminance() > 0.5
      ? const Color(0xFF1A1A1A)
      : const Color(0xFFF2F2F2);

  Color get inputCursorColor => const Color(0xFFE8A0BF);

  // --- Helpers --------------------------------------------------

  static Color _colorOr(int? v, Color fallback) =>
      v != null ? Color(v) : fallback;

  static String? _existingPath(String? path) {
    if (path == null) return null;
    return File(path).existsSync() ? path : null;
  }

  // --- Setters (flush + notify) --------------------------------

  Future<void> setChatTitle(String value) async {
    chatTitle = value.trim().isEmpty ? '哥哥宝宝' : value.trim();
    await _flush();
    notifyListeners();
  }

  Future<void> setInstructions(String value) async {
    instructions = value;
    await _flush();
    notifyListeners();
  }

  Future<void> setMyBubbleColor(Color c) async {
    myBubbleColor = c;
    await _flush();
    notifyListeners();
  }

  Future<void> setAiBubbleColor(Color c) async {
    aiBubbleColor = c;
    await _flush();
    notifyListeners();
  }

  Future<void> setWallpaperColor(Color c) async {
    wallpaperColorValue = c.toARGB32();
    wallpaperImagePath = null;
    await _flush();
    notifyListeners();
  }

  Future<void> setWallpaperImage(String srcPath) async {
    wallpaperImagePath =
        await _persistImage(srcPath, 'wallpaper', wallpaperImagePath);
    wallpaperColorValue = null;
    await _flush();
    notifyListeners();
  }

  Future<void> clearWallpaper() async {
    wallpaperImagePath = null;
    wallpaperColorValue = null;
    await _flush();
    notifyListeners();
  }

  Future<void> setMyAvatar(String srcPath) async {
    myAvatarPath = await _persistImage(srcPath, 'my_avatar', myAvatarPath);
    await _flush();
    notifyListeners();
  }

  Future<void> setAiAvatar(String srcPath) async {
    aiAvatarPath = await _persistImage(srcPath, 'ai_avatar', aiAvatarPath);
    await _flush();
    notifyListeners();
  }

  Future<void> setFontSize(FontSizeLevel level) async {
    fontSize = level;
    await _flush();
    notifyListeners();
  }

  Future<void> setSound(NotificationSound value) async {
    sound = value;
    await _flush();
    notifyListeners();
  }

  Future<void> setMyBubbleOpacity(double v, {bool save = true}) async {
    myBubbleOpacity = v.clamp(0.0, 1.0);
    if (save) await _flush();
    notifyListeners();
  }

  Future<void> setAiBubbleOpacity(double v, {bool save = true}) async {
    aiBubbleOpacity = v.clamp(0.0, 1.0);
    if (save) await _flush();
    notifyListeners();
  }

  Future<void> setWallpaperBlur(double v, {bool save = true}) async {
    wallpaperBlur = v.clamp(0.0, 20.0);
    if (save) await _flush();
    notifyListeners();
  }

  Future<void> setOverlayOpacity(double v, {bool save = true}) async {
    overlayOpacity = v.clamp(0.0, 1.0);
    if (save) await _flush();
    notifyListeners();
  }

  Future<void> applyPreset(ThemePreset preset) async {
    theme = preset;
    myBubbleColor = preset.myBubble;
    aiBubbleColor = preset.aiBubble;
    wallpaperColorValue = null;
    wallpaperImagePath = null;
    await _flush();
    notifyListeners();
  }

  /// Copy a picked image into the app documents directory (persistent, never a
  /// temp dir) under a fresh, unique name so FileImage's path-keyed cache
  /// always picks up the new file. Deletes the previous copy.
  static Future<String> _persistImage(
      String srcPath, String name, String? previous) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/media');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = srcPath.contains('.')
        ? srcPath.split('.').last.split('?').first
        : 'jpg';
    final safeExt = (ext.length <= 4) ? ext : 'jpg';
    final dest =
        '${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    await File(srcPath).copy(dest);
    if (previous != null && previous != dest) {
      try {
        final old = File(previous);
        if (old.existsSync()) await old.delete();
      } catch (_) {/* best effort */}
    }
    return dest;
  }
}
