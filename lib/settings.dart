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
  static const _kMyBubbleOpacity = 'myBubbleOpacity';
  static const _kAiBubbleOpacity = 'aiBubbleOpacity';
  static const _kWallpaperBlur = 'wallpaperBlur';
  static const _kOverlayOpacity = 'overlayOpacity';

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

  /// 0.0 = fully transparent bubble, 1.0 = opaque. (requirement 一)
  double myBubbleOpacity = 1.0;
  double aiBubbleOpacity = 1.0;

  /// Gaussian blur sigma applied to the wallpaper image, 0..20. (requirement 二)
  double wallpaperBlur = 0.0;

  /// Opacity of the tint layer over the wallpaper, 0..1. (requirement 三)
  double overlayOpacity = 0.0;

  // --- Derived values -------------------------------------------------

  bool get isDark => theme.isDark;

  /// Solid chat background: explicit wallpaper colour, else the preset's.
  Color get chatBackgroundColor =>
      wallpaperColorValue != null ? Color(wallpaperColorValue!) : theme.chatBackground;

  Color get appBarColor => isDark ? const Color(0xFF1F1F1F) : Colors.white;
  Color get appBarTextColor => isDark ? Colors.white : Colors.black;
  Color get panelColor => isDark ? const Color(0xFF262626) : const Color(0xFFF7F7F7);
  Color get menuColor => isDark ? const Color(0xFF2C2C2C) : Colors.white;

  double get messageFontSize => fontSize.messageFontSize;

  // --- Wallpaper / bubble compositing ------------------------------

  /// Tint layer painted over the wallpaper: white in light themes, black in
  /// dark ones, so raising [overlayOpacity] always calms the wallpaper down.
  Color get overlayColor => isDark ? Colors.black : Colors.white;

  Color get effectiveMyBubbleColor => myBubbleColor
      .withValues(alpha: (myBubbleColor.a * myBubbleOpacity).clamp(0.0, 1.0));

  Color get effectiveAiBubbleColor => aiBubbleColor
      .withValues(alpha: (aiBubbleColor.a * aiBubbleOpacity).clamp(0.0, 1.0));

  /// Best guess at the colour sitting behind the wallpaper image. We cannot
  /// sample the image itself, so assume a middling grey biased by the theme.
  Color get _wallpaperBaseColor {
    if (wallpaperColorValue != null) return Color(wallpaperColorValue!);
    if (wallpaperImagePath != null) {
      return isDark ? const Color(0xFF333333) : const Color(0xFFBFBFBF);
    }
    return theme.chatBackground;
  }

  /// The colour a reader effectively sees behind bubble text on [isMe]'s side,
  /// after the wallpaper, the tint layer and the (possibly translucent) bubble
  /// are composited. Used to pick a legible text colour.
  Color _behindBubbleText(bool isMe) {
    var bg = _wallpaperBaseColor;
    if (overlayOpacity > 0) {
      bg = Color.alphaBlend(
          overlayColor.withValues(alpha: overlayOpacity.clamp(0.0, 1.0)), bg);
    }
    final bubble = isMe ? effectiveMyBubbleColor : effectiveAiBubbleColor;
    return Color.alphaBlend(bubble, bg);
  }

  /// Auto dark/light bubble text depending on what is behind it (requirement 一.3).
  Color bubbleTextColorFor(bool isMe) =>
      _behindBubbleText(isMe).computeLuminance() > 0.5
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFF2F2F2);

  /// When the bubble is very translucent, a faint outline keeps text readable
  /// over an unknown wallpaper (requirement 一 / 五).
  bool bubbleTextNeedsHalo(bool isMe) {
    final a = (isMe ? effectiveMyBubbleColor : effectiveAiBubbleColor).a;
    return a < 0.35;
  }

  /// Retained for callers that still want a plain theme-based colour.
  Color get bubbleTextColor =>
      isDark ? const Color(0xFFEDEDED) : Colors.black87;

  // --- Input field (judged on its own background, requirement 四) --

  Color get inputFieldColor =>
      isDark ? const Color(0xFF2C2C2C) : Colors.white;

  Color get inputTextColor => inputFieldColor.computeLuminance() > 0.5
      ? const Color(0xFF1A1A1A)
      : const Color(0xFFF2F2F2);

  Color get inputCursorColor => const Color(0xFF07C160);

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
    myBubbleOpacity =
        (p.getDouble(_kMyBubbleOpacity) ?? myBubbleOpacity).clamp(0.0, 1.0);
    aiBubbleOpacity =
        (p.getDouble(_kAiBubbleOpacity) ?? aiBubbleOpacity).clamp(0.0, 1.0);
    wallpaperBlur =
        (p.getDouble(_kWallpaperBlur) ?? wallpaperBlur).clamp(0.0, 20.0);
    overlayOpacity =
        (p.getDouble(_kOverlayOpacity) ?? overlayOpacity).clamp(0.0, 1.0);
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

  /// Slider setters notify on every drag tick for a live preview but only write
  /// to disk when [save] is true (pass `false` on `onChanged`, `true` on
  /// `onChangeEnd`).
  Future<void> setMyBubbleOpacity(double v, {bool save = true}) async {
    myBubbleOpacity = v.clamp(0.0, 1.0);
    if (save) await _prefs.setDouble(_kMyBubbleOpacity, myBubbleOpacity);
    notifyListeners();
  }

  Future<void> setAiBubbleOpacity(double v, {bool save = true}) async {
    aiBubbleOpacity = v.clamp(0.0, 1.0);
    if (save) await _prefs.setDouble(_kAiBubbleOpacity, aiBubbleOpacity);
    notifyListeners();
  }

  Future<void> setWallpaperBlur(double v, {bool save = true}) async {
    wallpaperBlur = v.clamp(0.0, 20.0);
    if (save) await _prefs.setDouble(_kWallpaperBlur, wallpaperBlur);
    notifyListeners();
  }

  Future<void> setOverlayOpacity(double v, {bool save = true}) async {
    overlayOpacity = v.clamp(0.0, 1.0);
    if (save) await _prefs.setDouble(_kOverlayOpacity, overlayOpacity);
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

  /// Copy a picked image into the app documents directory (persistent, never a
  /// temp dir — requirement 五) under a fresh, unique name so FileImage's
  /// path-keyed cache always picks up the new file. Deletes the previous copy.
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
