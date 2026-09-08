import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'image_viewer.dart';
import 'models.dart';
import 'mood_calendar_screen.dart';
import 'search_screen.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'store.dart';

const List<String> _placeholderReplies = [
  '收到啦~',
  '嗯嗯，知道了',
  '好呀好呀',
  '在忙，等下回你',
  '哈哈哈是这样嘛',
];

enum _Panel { none, emoji, functions }

/// Show a time separator when the gap since the previous message is >= this.
const Duration _timeSeparatorGap = Duration(minutes: 5);

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool pointLeft;

  _BubbleTailPainter({required this.color, required this.pointLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (pointLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointLeft != pointLeft;
}

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  final AppSettings settings;

  const ChatScreen({
    super.key,
    required this.conversation,
    required this.settings,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _player = AudioPlayer();
  final Map<String, GlobalKey> _rowKeys = {};

  _Panel _panel = _Panel.none;
  String? _highlightId;
  Timer? _highlightTimer;

  AppSettings get _s => widget.settings;
  List<ChatMessage> get _messages => widget.conversation.messages;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _panel != _Panel.none) {
        setState(() => _panel = _Panel.none);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  void _persist() => Store.saveConversation(widget.conversation);

  Future<void> _playNotificationSound() async {
    final asset = _s.sound.asset;
    if (asset == null) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {/* non-critical */}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Sending ------------------------------------------------------

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final msg = ChatMessage(
      id: ChatMessage.newId(),
      text: text,
      isMe: true,
      time: now,
      metadata: ChatMessage.outgoingMeta(now),
    );
    setState(() => _messages.add(msg));
    _persist();
    _controller.clear();
    _scrollToBottom();
    _sendToBackend(msg);
  }

  /// Payload posted to the chat backend. `metadata.timestamp` (ISO 8601) lets
  /// the model answer time-aware questions (requirement 一.7).
  Map<String, dynamic> _buildPayload(ChatMessage msg) => {
        'role': 'user',
        'content': msg.text,
        if (msg.kind != MessageKind.text) 'attachmentType': msg.kind.name,
        'metadata': {
          ...msg.metadata,
          'clientSentAt': DateTime.now().toIso8601String(),
        },
      };

  Future<void> _sendToBackend(ChatMessage msg) async {
    debugPrint('chat payload -> ${jsonEncode(_buildPayload(msg))}');
    // TODO: replace with a real request to the chat backend.
    _replyLater();
  }

  void _replyLater() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          id: ChatMessage.newId(),
          text:
              _placeholderReplies[_random.nextInt(_placeholderReplies.length)],
          isMe: false,
          time: DateTime.now(),
        ));
      });
      _persist();
      _scrollToBottom();
      _playNotificationSound();
    });
  }

  // --- Panels -----------------------------------------------------

  void _togglePanel(_Panel target) {
    if (_panel == target) {
      setState(() => _panel = _Panel.none);
      _focusNode.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _panel = target);
      _scrollToBottom();
    }
  }

  void _dismissAll() {
    FocusScope.of(context).unfocus();
    if (_panel != _Panel.none) setState(() => _panel = _Panel.none);
  }

  void _insertEmoji(String emoji) {
    final value = _controller.value;
    final sel = value.selection;
    final start = sel.start < 0 ? value.text.length : sel.start;
    final end = sel.end < 0 ? value.text.length : sel.end;
    _controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
      composing: TextRange.empty,
    );
  }

  // --- Image handling ------------------------------------------

  Future<void> _pickAvatar(bool isMe) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 480,
        imageQuality: 90,
      );
      if (file == null) return;
      if (isMe) {
        await _s.setMyAvatar(file.path);
      } else {
        final p = await Store.persistFile(file.path, 'aiavatar');
        if (!mounted) return;
        setState(() => widget.conversation.aiAvatarPath = p);
        _persist();
      }
    } catch (e) {
      _showSnack('无法读取图片：$e');
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    setState(() => _panel = _Panel.none);
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final persisted = await Store.persistFile(file.path, 'img');
      if (!mounted) return;
      final now = DateTime.now();
      final msg = ChatMessage(
        id: ChatMessage.newId(),
        mediaPath: persisted,
        kind: MessageKind.image,
        isMe: true,
        time: now,
        metadata: ChatMessage.outgoingMeta(now),
      );
      setState(() => _messages.add(msg));
      _persist();
      _scrollToBottom();
      _sendToBackend(msg);
    } catch (e) {
      _showSnack('无法打开：$e');
    }
  }

  void _openImage(ChatMessage msg) {
    if (msg.mediaPath == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImageViewerScreen(path: msg.mediaPath!, heroTag: msg.id),
    ));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // --- Long-press message menu (requirement 四.1) --------------

  Future<void> _showMessageMenu(
      BuildContext context, Offset position, ChatMessage msg) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    PopupMenuItem<String> item(String v, String label) => PopupMenuItem<String>(
          value: v,
          height: 40,
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        );

    final selected = await showMenu<String>(
      context: context,
      color: Colors.black87,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (msg.kind == MessageKind.text) item('copy', '复制'),
        item('favorite', msg.favorite ? '取消收藏' : '收藏'),
        item('delete', '删除'),
      ],
    );

    switch (selected) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: msg.text ?? ''));
        _showSnack('已复制');
        break;
      case 'favorite':
        setState(() => msg.favorite = !msg.favorite);
        _persist();
        break;
      case 'delete':
        setState(() => _messages.removeWhere((m) => m.id == msg.id));
        _persist();
        break;
    }
  }

  // --- Top bar ---------------------------------------------------

  Future<void> _onSearch() async {
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) =>
            SearchScreen(conversation: widget.conversation, settings: _s),
      ),
    );
    if (picked != null && mounted) _jumpToDate(picked);
  }

  void _jumpToDate(DateTime day) {
    final key = dateKey(day);
    final idx = _messages.indexWhere((m) => dateKey(m.time) == key);
    if (idx < 0) {
      _showSnack('那天没有聊天记录');
      return;
    }
    final count = _messages.length;
    if (_scrollController.hasClients && count > 0) {
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo((idx / count * max).clamp(0.0, max));
    }
    setState(() => _highlightId = _messages[idx].id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[_messages[idx].id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.15, duration: const Duration(milliseconds: 350));
      }
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _renameConversation() async {
    final controller =
        TextEditingController(text: widget.conversation.name);
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
    final name = result?.trim();
    if (name != null && name.isNotEmpty && mounted) {
      setState(() => widget.conversation.name = name);
      _persist();
    }
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'search':
        _onSearch();
        break;
      case 'rename':
        _renameConversation();
        break;
      case 'mood':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MoodCalendarScreen(settings: _s),
        ));
        break;
      case 'clear':
        setState(_messages.clear);
        _persist();
        break;
      case 'settings':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              SettingsScreen(settings: _s, onExportChat: _exportChatLog),
        ));
        break;
    }
  }

  // --- Export (requirement 二.9) ------------------------------

  Future<void> _exportChatLog() async {
    if (_messages.isEmpty) {
      _showSnack('还没有聊天记录');
      return;
    }
    final name = widget.conversation.name;
    final buf = StringBuffer()
      ..writeln('$name 聊天记录')
      ..writeln('导出时间：${formatFullStamp(DateTime.now())}')
      ..writeln('共 ${_messages.length} 条')
      ..writeln('=' * 32);
    for (final m in _messages) {
      final who = m.isMe ? '我' : name;
      final body = switch (m.kind) {
        MessageKind.text => m.text ?? '',
        MessageKind.image => '[图片] ${m.mediaPath ?? ''}',
        MessageKind.video => '[视频] ${m.mediaPath ?? ''}',
        MessageKind.file => '[文件] ${m.fileName ?? m.mediaPath ?? ''}',
      };
      buf.writeln('[${formatFullStamp(m.time)}] $who：$body');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final n = DateTime.now();
      String two(int x) => x.toString().padLeft(2, '0');
      final fname = 'chat_${n.year}${two(n.month)}${two(n.day)}'
          '_${two(n.hour)}${two(n.minute)}${two(n.second)}.txt';
      final file = File('${dir.path}/$fname');
      await file.writeAsString(buf.toString());
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: '聊天记录导出');
      _showSnack('已导出到：${file.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  // --- Avatars / bubbles -------------------------------------

  String? _avatarPath(bool isMe) => isMe
      ? _s.myAvatarPath
      : (widget.conversation.aiAvatarPath ?? _s.aiAvatarPath);

  Widget _buildAvatar(bool isMe) {
    final path = _avatarPath(isMe);
    Widget inner;
    if (path != null && File(path).existsSync()) {
      inner = Image.file(File(path), width: 44, height: 44, fit: BoxFit.cover);
    } else {
      inner = Container(
        width: 44,
        height: 44,
        color: isMe ? const Color(0xFFB0E0E6) : const Color(0xFFE0D0D0),
        alignment: Alignment.center,
        child: Text(isMe ? '辰' : '哥',
            style: const TextStyle(fontSize: 16, color: Colors.black87)),
      );
    }
    return GestureDetector(
      onTap: () => _pickAvatar(isMe),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(6), child: inner),
    );
  }

  Widget _buildAvatarColumn(ChatMessage msg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAvatar(msg.isMe),
        const SizedBox(height: 3),
        Text(
          formatClock(msg.time),
          style: TextStyle(
            fontSize: 9,
            color: _s.isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final bubbleColor = msg.isMe ? _s.myBubbleColor : _s.aiBubbleColor;
    final isImage = msg.kind == MessageKind.image;

    Widget inner;
    if (isImage && msg.mediaPath != null) {
      inner = GestureDetector(
        onTap: () => _openImage(msg),
        child: Hero(
          tag: msg.id,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 180, maxHeight: 220),
              child: Image.file(File(msg.mediaPath!), fit: BoxFit.cover),
            ),
          ),
        ),
      );
    } else {
      inner = Text(
        msg.text ?? '',
        style: TextStyle(
          fontSize: _s.messageFontSize,
          color: _s.bubbleTextColor,
          height: 1.3,
        ),
      );
    }

    final bubble = GestureDetector(
      onLongPressStart: (d) => _showMessageMenu(context, d.globalPosition, msg),
      child: Container(
        padding: isImage
            ? const EdgeInsets.all(3)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: inner,
      ),
    );

    final tail = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CustomPaint(
        size: const Size(6, 11),
        painter: _BubbleTailPainter(color: bubbleColor, pointLeft: !msg.isMe),
      ),
    );

    final star = msg.favorite
        ? const Padding(
            padding: EdgeInsets.only(top: 14, left: 2, right: 2),
            child: Icon(Icons.star, size: 13, color: Color(0xFFF5A623)),
          )
        : const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: msg.isMe
          ? [star, Flexible(child: bubble), tail]
          : [tail, Flexible(child: bubble), star],
    );
  }

  Widget _buildMessageRow(ChatMessage msg) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.66;
    final avatarColumn = _buildAvatarColumn(msg);
    final content = Flexible(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: _buildBubble(msg),
      ),
    );

    return Container(
      key: _rowKeys.putIfAbsent(msg.id, () => GlobalKey()),
      color: msg.id == _highlightId
          ? const Color(0x33F5A623)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: msg.isMe
            ? [content, const SizedBox(width: 6), avatarColumn]
            : [avatarColumn, const SizedBox(width: 6), content],
      ),
    );
  }

  Widget _buildTimeSeparator(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _s.isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            formatSeparator(dt),
            style: TextStyle(
              fontSize: 12,
              color: _s.isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  // --- Input bar ---------------------------------------------

  Color get _iconColor => _s.isDark ? Colors.white60 : Colors.black54;

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 28, color: _iconColor),
      ),
    );
  }

  Widget _buildSendButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ElevatedButton(
        onPressed: _sendMessage,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF07C160),
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(56, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        child: const Text('发送', style: TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _controller.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: _s.panelColor,
        border: Border(
          top: BorderSide(
            color:
                _s.isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _iconBtn(Icons.settings_voice_outlined, () {}),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _s.isDark ? const Color(0xFF2C2C2C) : Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                cursorColor: const Color(0xFF07C160),
                style: TextStyle(fontSize: 16, color: _s.bubbleTextColor),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _iconBtn(
            _panel == _Panel.emoji
                ? Icons.keyboard_outlined
                : Icons.emoji_emotions_outlined,
            () => _togglePanel(_Panel.emoji),
          ),
          const SizedBox(width: 2),
          hasText
              ? _buildSendButton()
              : _iconBtn(Icons.add_circle_outline,
                  () => _togglePanel(_Panel.functions)),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _buildEmojiPanel() {
    return Container(
      height: 240,
      color: _s.panelColor,
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(8),
        children: [
          for (final e in kCommonEmojis)
            GestureDetector(
              onTap: () => _insertEmoji(e),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _funcItem(IconData icon, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _s.menuColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 30, color: _iconColor),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: _iconColor)),
      ],
    );
  }

  Widget _buildFunctionPanel() {
    return Container(
      height: 200,
      width: double.infinity,
      color: _s.panelColor,
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _funcItem(Icons.photo_outlined, '相册',
              () => _pickAndSendImage(ImageSource.gallery)),
          const SizedBox(width: 24),
          _funcItem(Icons.camera_alt_outlined, '拍照',
              () => _pickAndSendImage(ImageSource.camera)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = _s.wallpaperImagePath;
    return Scaffold(
      backgroundColor: _s.chatBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: _s.appBarColor,
            border: Border(
              bottom: BorderSide(
                color: _s.isDark
                    ? const Color(0xFF333333)
                    : const Color(0xFFE0E0E0),
                width: 0.5,
              ),
            ),
          ),
          child: AppBar(
            backgroundColor: _s.appBarColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: _s.appBarTextColor),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            centerTitle: true,
            title: Text(
              widget.conversation.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _s.appBarTextColor,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.search, color: _s.appBarTextColor),
                onPressed: _onSearch,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: _s.appBarTextColor),
                color: _s.menuColor,
                surfaceTintColor: Colors.transparent,
                onSelected: _onMenuSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'search', child: Text('搜索聊天记录')),
                  PopupMenuItem(value: 'rename', child: Text('修改聊天名称')),
                  PopupMenuItem(value: 'mood', child: Text('心情日历')),
                  PopupMenuItem(value: 'clear', child: Text('清空聊天记录')),
                  PopupMenuItem(value: 'settings', child: Text('设置')),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          if (wallpaper != null && File(wallpaper).existsSync())
            Positioned.fill(
              child: Image.file(File(wallpaper), fit: BoxFit.cover),
            ),
          Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismissAll,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final showTime = index == 0 ||
                          msg.time
                                  .difference(_messages[index - 1].time)
                                  .abs() >=
                              _timeSeparatorGap;
                      return Column(
                        children: [
                          if (showTime) _buildTimeSeparator(msg.time),
                          _buildMessageRow(msg),
                        ],
                      );
                    },
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInputBar(),
                    if (_panel == _Panel.emoji) _buildEmojiPanel(),
                    if (_panel == _Panel.functions) _buildFunctionPanel(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
