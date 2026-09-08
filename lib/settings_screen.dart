import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'settings.dart';

const Color _accent = Color(0xFF07C160);

/// Preset swatches offered by the colour / wallpaper pickers.
const List<Color> _swatches = [
  Color(0xFFFFFFFF), Color(0xFFEDEDED), Color(0xFFD9D9D9), Color(0xFF2C2C2E),
  Color(0xFF95EC69), Color(0xFF07C160), Color(0xFFB7E5C2), Color(0xFF3A6E43),
  Color(0xFFFBF0F5), Color(0xFFFFD6E7), Color(0xFFFF9EC4), Color(0xFFF3C6D8),
  Color(0xFFCDE7FF), Color(0xFF9FC8F5), Color(0xFFFFF3C4), Color(0xFFE7D9FF),
];

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;

  /// Supplied by the chat screen: writes the current chat log to a txt file
  /// and opens the share sheet (requirement 二.9).
  final Future<void> Function()? onExportChat;

  const SettingsScreen({
    super.key,
    required this.settings,
    this.onExportChat,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _preview = AudioPlayer();

  AppSettings get _s => widget.settings;

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _playPreview(NotificationSound snd) async {
    final asset = snd.asset;
    if (asset == null) return;
    try {
      await _preview.stop();
      await _preview.play(AssetSource(asset));
    } catch (_) {/* preview is non-critical */}
  }

  Future<String?> _pickImagePath() async {
    try {
      final XFile? f = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      return f?.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法读取图片：$e')));
      }
      return null;
    }
  }

  // --- 二.1 chat name ------------------------------------------------

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _s.chatTitle);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改聊天名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '输入聊天名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('确定')),
        ],
      ),
    );
    if (result != null) await _s.setChatTitle(result);
  }

  // --- 二.2 / 二.3 avatars ----------------------------------------

  Future<void> _editAvatar({required bool isMe}) async {
    final path = await _pickImagePath();
    if (path == null) return;
    if (isMe) {
      await _s.setMyAvatar(path);
    } else {
      await _s.setAiAvatar(path);
    }
  }

  // --- 二.4 bubble colours --------------------------------------

  Future<void> _editBubbleColor({required bool isMe}) async {
    final current = isMe ? _s.myBubbleColor : _s.aiBubbleColor;
    final picked = await _showSwatchSheet(title: '选择气泡颜色', current: current);
    if (picked == null) return;
    if (isMe) {
      await _s.setMyBubbleColor(picked);
    } else {
      await _s.setAiBubbleColor(picked);
    }
  }

  Future<Color?> _showSwatchSheet(
      {required String title, required Color current}) {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: _s.menuColor,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final c in _swatches)
                    _SwatchDot(
                      color: c,
                      selected: c.toARGB32() == current.toARGB32(),
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 二.5 wallpaper -------------------------------------------

  Future<void> _editWallpaper() async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: _s.menuColor,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('聊天背景',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('从相册选择图片'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('恢复默认背景'),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text('或选择纯色', style: TextStyle(color: Colors.grey)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final c in _swatches)
                    _SwatchDot(
                      color: c,
                      selected: _s.wallpaperColorValue == c.toARGB32(),
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (result == 'image') {
      final path = await _pickImagePath();
      if (path != null) await _s.setWallpaperImage(path);
    } else if (result == 'reset') {
      await _s.clearWallpaper();
    } else if (result is Color) {
      await _s.setWallpaperColor(result);
    }
  }

  String get _wallpaperSummary {
    if (_s.wallpaperImagePath != null) return '图片';
    if (_s.wallpaperColorValue != null) return '纯色';
    return '默认';
  }

  // --- 二.8 notification sound --------------------------------

  Future<void> _pickSound() async {
    final result = await showModalBottomSheet<NotificationSound>(
      context: context,
      backgroundColor: _s.menuColor,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('消息提示音',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final snd in NotificationSound.values)
              ListTile(
                leading: snd.asset == null
                    ? const SizedBox(width: 40)
                    : IconButton(
                        icon: const Icon(Icons.volume_up_outlined),
                        tooltip: '试听',
                        onPressed: () => _playPreview(snd),
                      ),
                title: Text(snd.label),
                trailing: snd == _s.sound
                    ? const Icon(Icons.check, color: _accent)
                    : null,
                onTap: () => Navigator.pop(ctx, snd),
              ),
          ],
        ),
      ),
    );
    if (result != null) await _s.setSound(result);
  }

  // --- widgets -------------------------------------------------

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
      );

  Widget _colorDot(Color c) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26),
        ),
      );

  Widget _avatarPreview(String? path) {
    if (path == null) {
      return const Text('未设置', style: TextStyle(color: Colors.grey));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(File(path), width: 32, height: 32, fit: BoxFit.cover),
    );
  }

  Widget _navTile({
    required String title,
    Widget? trailingWidget,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(trailingText, style: const TextStyle(color: Colors.grey)),
          if (trailingWidget != null) trailingWidget,
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            children: [
              _sectionHeader('个性化'),
              _navTile(
                title: '聊天名称',
                trailingText: _s.chatTitle,
                onTap: _editTitle,
              ),
              _navTile(
                title: '我的头像',
                trailingWidget: _avatarPreview(_s.myAvatarPath),
                onTap: () => _editAvatar(isMe: true),
              ),
              _navTile(
                title: '对方头像',
                trailingWidget: _avatarPreview(_s.aiAvatarPath),
                onTap: () => _editAvatar(isMe: false),
              ),
              _sectionHeader('外观'),
              _navTile(
                title: '我的气泡颜色',
                trailingWidget: _colorDot(_s.myBubbleColor),
                onTap: () => _editBubbleColor(isMe: true),
              ),
              _navTile(
                title: '对方气泡颜色',
                trailingWidget: _colorDot(_s.aiBubbleColor),
                onTap: () => _editBubbleColor(isMe: false),
              ),
              _navTile(
                title: '聊天背景',
                trailingText: _wallpaperSummary,
                onTap: _editWallpaper,
              ),
              ListTile(
                title: const Text('字体大小'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<FontSizeLevel>(
                    segments: const [
                      ButtonSegment(
                          value: FontSizeLevel.small, label: Text('小')),
                      ButtonSegment(
                          value: FontSizeLevel.medium, label: Text('中')),
                      ButtonSegment(
                          value: FontSizeLevel.large, label: Text('大')),
                    ],
                    selected: {_s.fontSize},
                    showSelectedIcon: false,
                    onSelectionChanged: (set) => _s.setFontSize(set.first),
                  ),
                ),
              ),
              _sectionHeader('主题（切换会重置气泡颜色和壁纸）'),
              for (final preset in ThemePreset.values)
                ListTile(
                  title: Text(preset.label),
                  trailing: preset == _s.theme
                      ? const Icon(Icons.check, color: _accent)
                      : null,
                  onTap: () => _s.applyPreset(preset),
                ),
              _sectionHeader('提示'),
              _navTile(
                title: '消息提示音',
                trailingText: _s.sound.label,
                onTap: _pickSound,
              ),
              _sectionHeader('聊天记录'),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('导出聊天记录'),
                subtitle: const Text('保存为 txt 文件'),
                enabled: widget.onExportChat != null,
                onTap: () => widget.onExportChat?.call(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _SwatchDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _accent : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check,
                size: 20,
                color: color.computeLuminance() > 0.5
                    ? Colors.black54
                    : Colors.white)
            : null,
      ),
    );
  }
}
