import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'settings.dart';

/// Long-press menu action keys.
class MsgMenu {
  static const copy = 'copy';
  static const forward = 'forward';
  static const favorite = 'favorite';
  static const delete = 'delete';
  static const multi = 'multi';
  static const quote = 'quote';
  static const remind = 'remind';
  static const search = 'search';
}

const Color _menuBg = Color(0xFF4A4A4A);

/// WeChat-style long-press bubble menu (requirement 一). Dims the background,
/// scales in 0.8 -> 1.0 over 150ms, and points a small triangle at [anchor].
Future<String?> showMessageMenu(
  BuildContext context, {
  required Offset anchor,
  required bool isFavorite,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.3),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, _, __) =>
        _MessageMenu(anchor: anchor, isFavorite: isFavorite),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _MessageMenu extends StatefulWidget {
  final Offset anchor;
  final bool isFavorite;

  const _MessageMenu({required this.anchor, required this.isFavorite});

  @override
  State<_MessageMenu> createState() => _MessageMenuState();
}

class _MessageMenuState extends State<_MessageMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _item(IconData icon, String label, String value) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final menuWidth = math.min(size.width - 24, 300.0);
    final cellWidth = menuWidth / 5;
    // Container below has no horizontal padding, so 5 cells == menuWidth.

    final row1 = <Widget>[
      _item(Icons.content_copy, '复制', MsgMenu.copy),
      _item(Icons.ios_share, '转发', MsgMenu.forward),
      _item(widget.isFavorite ? Icons.star : Icons.star_border,
          widget.isFavorite ? '取消收藏' : '收藏', MsgMenu.favorite),
      _item(Icons.delete_outline, '删除', MsgMenu.delete),
      _item(Icons.checklist, '多选', MsgMenu.multi),
    ];
    final row2 = <Widget>[
      _item(Icons.format_quote, '引用', MsgMenu.quote),
      _item(Icons.alarm, '提醒', MsgMenu.remind),
      _item(Icons.search, '搜一搜', MsgMenu.search),
    ];

    // Two rows of cells + vertical padding.
    const rowHeight = 62.0;
    const menuHeight = 8.0 + rowHeight * 2 + 8.0;
    const triangleH = 7.0;

    var left = widget.anchor.dx - menuWidth / 2;
    left = left.clamp(12.0, math.max(12.0, size.width - 12 - menuWidth));
    final roomAbove = widget.anchor.dy - menuHeight - triangleH - 24;
    final above = roomAbove > 0;
    final rawTop = above
        ? widget.anchor.dy - menuHeight - triangleH - 10
        : widget.anchor.dy + 10;
    final maxTop =
        math.max(8.0, size.height - menuHeight - triangleH - 8);
    final top = rawTop.clamp(8.0, maxTop);
    final triX = (widget.anchor.dx - left)
        .clamp(18.0, math.max(18.0, menuWidth - 18));
    final triFrac = (triX / menuWidth) * 2 - 1;

    Widget triangle(bool pointDown) => SizedBox(
          width: menuWidth,
          height: triangleH,
          child: Align(
            alignment: Alignment(triFrac, 0),
            child: CustomPaint(
              size: const Size(16, triangleH),
              painter: _TrianglePainter(pointDown: pointDown, color: _menuBg),
            ),
          ),
        );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
        Positioned(
          left: left,
          top: top,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: _c, curve: Curves.easeOut),
            ),
            alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!above) triangle(false),
                Container(
                  width: menuWidth,
                  decoration: BoxDecoration(
                    color: _menuBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          for (final w in row1)
                            SizedBox(width: cellWidth, child: w),
                        ],
                      ),
                      Row(
                        children: [
                          for (final w in row2)
                            SizedBox(width: cellWidth, child: w),
                        ],
                      ),
                    ],
                  ),
                ),
                if (above) triangle(true),
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final bool pointDown;
  final Color color;

  _TrianglePainter({required this.pointDown, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (pointDown) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      path.moveTo(size.width / 2, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) =>
      old.pointDown != pointDown || old.color != color;
}

/// Three dots that bounce in sequence — "对方正在输入…" (requirement 四).
class TypingDots extends StatefulWidget {
  final Color color;
  const TypingDots({super.key, this.color = Colors.grey});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value - i * 0.18) % 1.0;
            final lift = math.sin((phase.clamp(0.0, 0.5)) * 2 * math.pi) * 3;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.translate(
                offset: Offset(0, -lift.abs()),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Slide + elastic entry for a freshly added message bubble (requirement 五).
class MessageEntry extends StatefulWidget {
  final bool fromRight;
  final Widget child;

  const MessageEntry({
    super.key,
    required this.fromRight,
    required this.child,
  });

  @override
  State<MessageEntry> createState() => _MessageEntryState();
}

class _MessageEntryState extends State<MessageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final begin = Offset(widget.fromRight ? 0.12 : -0.12, 0.18);
    return SlideTransition(
      position: Tween<Offset>(begin: begin, end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut)),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _c,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
        ),
        child: widget.child,
      ),
    );
  }
}

/// A heart that floats up and fades — spawned on a double-tap (requirement 六).
class FloatingHeart extends StatefulWidget {
  final VoidCallback onDone;
  const FloatingHeart({super.key, required this.onDone});

  @override
  State<FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<FloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        final fadeIn = v < 0.25 ? v / 0.25 : 1.0;
        final opacity = (fadeIn * (1 - v)).clamp(0.0, 1.0);
        final scale = 0.6 + 0.6 * Curves.easeOutBack.transform(math.min(v * 2, 1.0));
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -60 * Curves.easeOut.transform(v)),
            child: Transform.scale(
              scale: scale,
              child: const Icon(Icons.favorite,
                  color: Color(0xFFE8577D), size: 30),
            ),
          ),
        );
      },
    );
  }
}

/// Actions emitted by [FunctionSheet].
class FnAction {
  static const photo = 'photo';
  static const camera = 'camera';
  static const file = 'file';
  static const video = 'video';
  static const voiceCall = 'voiceCall';
  static const music = 'music';
  static const model = 'model';
}

/// Bottom sheet shown by the "+" button: 2x4 grid, rounded white top,
/// dismissed by tapping outside or dragging down (requirement 四).
class FunctionSheet extends StatelessWidget {
  final AppSettings settings;
  final ValueChanged<String> onPick;

  const FunctionSheet({
    super.key,
    required this.settings,
    required this.onPick,
  });

  Widget _item(BuildContext context, IconData icon, String label, String key) {
    final s = settings;
    return InkWell(
      onTap: () => onPick(key),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: s.isDark
                  ? const Color(0xFF3A3A3A)
                  : const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                size: 26,
                color: s.isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color: s.isDark ? Colors.white70 : Colors.black54,
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<List<Object>>>[
      [
        [Icons.photo_outlined, '照片', FnAction.photo],
        [Icons.camera_alt_outlined, '拍摄', FnAction.camera],
        [Icons.insert_drive_file_outlined, '文件', FnAction.file],
        [Icons.videocam_outlined, '视频', FnAction.video],
      ],
      [
        [Icons.call_outlined, '语音通话', FnAction.voiceCall],
        [Icons.music_note_outlined, '音乐', FnAction.music],
        [Icons.smart_toy_outlined, '模型', FnAction.model],
      ],
    ];

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: settings.isDark ? const Color(0xFF1F1F1F) : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: i < row.length
                            ? _item(
                                context,
                                row[i][0] as IconData,
                                row[i][1] as String,
                                row[i][2] as String,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
