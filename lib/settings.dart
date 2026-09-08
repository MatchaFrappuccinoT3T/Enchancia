import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Asset path (relative to `assets/`) passed to audioplayers' AssetSource.
  String? get asset => switch (this) {
        NotificationSound.none => null,
        NotificationSound.ding => 'sounds/ding.wav',
        NotificationSound.dingdong => 'sounds/dingdong.wav',
        NotificationSound.bubble => 'sounds/bubble.wav',
      };
}

/// All user-configurable settings, persisted with SharedPreferences.
///
/// A single instance lives at the top of the widget tree; screens listen to it
/// and mutate it through the setters, each of which persists and notifies.
class AppSettings extends ChangeNotifier {
  static const _kTitle = 'chatTitle';
  static const _kMyBubble = 'myBubbleColor';
  static const _kAiBubble = 'aiBubbleColor';
  static const _kWallpaperColor = 'wallpaperColor';
  static const _kWallpaperImage = 'wallpaperImagePath';
  static const _kMyAvatar = 'myAvatarPath';
  static const _kAiAvatar = 'aiAvatarPath';
  static const _kFontSize = 'fontSizeLevel';
  static const _kTheme = 'themePreset';
  static const _kSound = 'notificationSound';

  late SharedPreferences _prefs;

  String chatTitle = '哥哥宝宝';
  Color myBubbleColor = ThemePreset.minimalWhite.myBubble;
  Color aiBubbleColor = ThemePreset.minimalWhite.aiBubble;
  int? wallpaperColorValue;
  String? wallpaperImagePath;
  String? myAvatarPath;
  String? aiAvatarPath;
  FontSizeLevel fontSize = FontSizeLevel.medium;
  ThemePreset theme = ThemePreset.minimalWhite;
  NotificationSound sound = NotificationSound.ding;

  // --- Derived values -------------------------------------------------

  bool get isDark => theme.isDark;

  /// Solid chat background: explicit wallpaper colour, else the preset's.
  Color get chatBackgroundColor =>
      wallpaperColorValue != null ? Color(wallpaperColorValue!) : theme.chatBackground;

  Color get bubbleTextColor =>
      isDark ? const Color(0xFFEDEDED) : Colors.black87;

  Color get appBarColor => isDark ? const Color(0xFF1F1F1F) : Colors.white;
  Color get appBarTextColor => isDark ? Colors.white : Colors.black;
  Color get panelColor => isDark ? const Color(0xFF262626) : const Color(0xFFF7F7F7);
  Color get menuColor => isDark ? const Color(0xFF2C2C2C) : Colors.white;

  double get messageFontSize => fontSize.messageFontSize;

  // --- Loading ------------------------------------------------------

  static Future<AppSettings> load() async {
    final s = AppSettings();
    s._prefs = await SharedPreferences.getInstance();
    s._readAll();
    return s;
  }

  void _readAll() {
    final p = _prefs;
    chatTitle = p.getString(_kTitle) ?? chatTitle;
    myBubbleColor = _colorOr(p.getInt(_kMyBubble), myBubbleColor);
    aiBubbleColor = _colorOr(p.getInt(_kAiBubble), aiBubbleColor);
    wallpaperColorValue = p.getInt(_kWallpaperColor);
    wallpaperImagePath = _existingPath(p.getString(_kWallpaperImage));
    myAvatarPath = _existingPath(p.getString(_kMyAvatar));
    aiAvatarPath = _existingPath(p.getString(_kAiAvatar));
    fontSize = FontSizeLevel
        .values[(p.getInt(_kFontSize) ?? fontSize.index).clamp(0, 2)];
    theme = ThemePreset
        .values[(p.getInt(_kTheme) ?? theme.index).clamp(0, 2)];
    sound = NotificationSound
        .values[(p.getInt(_kSound) ?? sound.index).clamp(0, 3)];
  }

  static Color _colorOr(int? v, Color fallback) =>
      v != null ? Color(v) : fallback;

  /// Drop a stored path if the file is gone (e.g. app data cleared).
  static String? _existingPath(String? path) {
    if (path == null) return null;
    return File(path).existsSync() ? path : null;
  }

  // --- Setters (persist + notify) ---------------------------------

  Future<void> setChatTitle(String value) async {
    chatTitle = value.trim().isEmpty ? '哥哥宝宝' : value.trim();
    await _prefs.setString(_kTitle, chatTitle);
    notifyListeners();
  }

  Future<void> setMyBubbleColor(Color c) async {
    myBubbleColor = c;
    await _prefs.setInt(_kMyBubble, _argb(c));
    notifyListeners();
  }

  Future<void> setAiBubbleColor(Color c) async {
    aiBubbleColor = c;
    await _prefs.setInt(_kAiBubble, _argb(c));
    notifyListeners();
  }

  Future<void> setWallpaperColor(Color c) async {
    wallpaperColorValue = _argb(c);
    wallpaperImagePath = null;
    await _prefs.setInt(_kWallpaperColor, wallpaperColorValue!);
    await _prefs.remove(_kWallpaperImage);
    notifyListeners();
  }

  Future<void> setWallpaperImage(String srcPath) async {
    final stored = await _persistImage(srcPath, 'wallpaper', wallpaperImagePath);
    wallpaperImagePath = stored;
    wallpaperColorValue = null;
    await _prefs.setString(_kWallpaperImage, stored);
    await _prefs.remove(_kWallpaperColor);
    notifyListeners();
  }

  Future<void> clearWallpaper() async {
    wallpaperImagePath = null;
    wallpaperColorValue = null;
    await _prefs.remove(_kWallpaperImage);
    await _prefs.remove(_kWallpaperColor);
    notifyListeners();
  }

  Future<void> setMyAvatar(String srcPath) async {
    myAvatarPath = await _persistImage(srcPath, 'my_avatar', myAvatarPath);
    await _prefs.setString(_kMyAvatar, myAvatarPath!);
    notifyListeners();
  }

  Future<void> setAiAvatar(String srcPath) async {
    aiAvatarPath = await _persistImage(srcPath, 'ai_avatar', aiAvatarPath);
    await _prefs.setString(_kAiAvatar, aiAvatarPath!);
    notifyListeners();
  }

  Future<void> setFontSize(FontSizeLevel level) async {
    fontSize = level;
    await _prefs.setInt(_kFontSize, level.index);
    notifyListeners();
  }

  Future<void> setSound(NotificationSound value) async {
    sound = value;
    await _prefs.setInt(_kSound, value.index);
    notifyListeners();
  }

  /// Applying a preset also resets the bubble colours and clears any custom
  /// wallpaper, so the preset looks the way it is meant to out of the box.
  Future<void> applyPreset(ThemePreset preset) async {
    theme = preset;
    myBubbleColor = preset.myBubble;
    aiBubbleColor = preset.aiBubble;
    wallpaperColorValue = null;
    wallpaperImagePath = null;
    await _prefs.setInt(_kTheme, preset.index);
    await _prefs.setInt(_kMyBubble, _argb(preset.myBubble));
    await _prefs.setInt(_kAiBubble, _argb(preset.aiBubble));
    await _prefs.remove(_kWallpaperColor);
    await _prefs.remove(_kWallpaperImage);
    notifyListeners();
  }

  // --- Helpers ----------------------------------------------------

  static int _argb(Color c) => c.toARGB32();

  /// Copy a picked image into app-support storage under a fresh, unique name
  /// so FileImage's path-keyed cache always picks up the new file. Deletes the
  /// previous copy if there was one.
  static Future<String> _persistImage(
      String srcPath, String name, String? previous) async {
    final dir = await getApplicationSupportDirectory();
    final ext = srcPath.split('.').last.split('?').first;
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
