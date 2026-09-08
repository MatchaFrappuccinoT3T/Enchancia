import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'chat_widgets.dart';
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

enum _Panel { none, emoji }

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

  /// Conversations searchable together (the project's, or just this one).
  final List<Conversation> siblings;

  /// Mood calendar scope for this conversation (project id or default).
  final String moodScope;

  /// If set, scroll to the message at this time once loaded.
  final DateTime? initialJumpTime;

  const ChatScreen({
    super.key,
    required this.conversation,
    required this.settings,
    List<Conversation>? siblings,
    this.moodScope = Store.defaultMoodScope,
    this.initialJumpTime,
  }) : siblings = siblings ?? const [];

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _pageSize = 20;
  static const int _initialWindow = 30;

  /// Fraction of sends that fail, so the failed / tap-to-resend state is
  /// visible without a real backend. Set to 0 to disable simulated failures.
  static const double _failRate = 0.1;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _player = AudioPlayer();
  final Map<String, GlobalKey> _rowKeys = {};
  final Set<String> _animatedIds = {};
  final Set<String> _selectedIds = {};

  _Panel _panel = _Panel.none;
  String? _highlightId;
  Timer? _highlightTimer;
  bool _multiSelect = false;
  ChatMessage? _quoted;
  bool _aiTyping = false;
  int _visibleCount = 0;
  bool _showJumpBtn = false;
  int _unread = 0;
  Offset? _lastDoubleTapPos;

  AppSettings get _s => widget.settings;
  List<ChatMessage> get _messages => widget.conversation.messages;

  List<ChatMessage> get _visible {
    final total = _messages.length;
    final start = (total - _visibleCount).clamp(0, total);
    return _messages.sublist(start);
  }

  bool get _allHistoryShown => _visibleCount >= _messages.length;

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    _controller.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _panel != _Panel.none) {
        setState(() => _panel = _Panel.none);
      }
    });
    // Repair any send that was interrupted by an app kill.
    for (final m in _messages) {
      if (m.isMe && m.status == MessageStatus.sending) {
        m.status = MessageStatus.sent;
      }
    }
    // History should not play the entry animation.
    _animatedIds.addAll(_messages.map((m) => m.id));
    _visibleCount =
        _messages.length <= _initialWindow ? _messages.length : _initialWindow;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final jump = widget.initialJumpTime;
      if (jump != null) {
        _jumpToTime(jump);
      } else {
        _scrollToBottom();
      }
    });
  }

  List<Conversation> get _searchScope =>
      widget.siblings.isEmpty ? [widget.conversation] : widget.siblings;

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _highlightTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  void _persist() => Store.saveConversation(widget.conversation);

  void _appendMessage(ChatMessage m) {
    _messages.add(m);
    _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
  }

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

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final fromBottom = pos.maxScrollExtent - pos.pixels;
    final show = fromBottom > MediaQuery.of(context).size.height;
    if (show != _showJumpBtn) setState(() => _showJumpBtn = show);
    if (fromBottom < 60 && _unread != 0) setState(() => _unread = 0);
  }

  // --- Sending ------------------------------------------------------

  /// "发送人：摘要" for a quoted message, summary capped at 30 chars.
  String _quoteLine(ChatMessage q) {
    final who = q.isMe ? '我' : widget.conversation.name;
    return '$who：${q.summary}';
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final q = _quoted;
    final msg = ChatMessage(
      id: ChatMessage.newId(),
      text: text,
      isMe: true,
      time: now,
      metadata: ChatMessage.outgoingMeta(now),
      status: MessageStatus.sending,
      quotedSummary: q == null ? null : _quoteLine(q),
      quotedMessageId: q?.id,
    );
    setState(() {
      _appendMessage(msg);
      _quoted = null;
    });
    _persist();
    _controller.clear();
    _scrollToBottom();
    _dispatch(msg);
  }

  Map<String, dynamic> _buildPayload(ChatMessage msg) => {
        'role': 'user',
        'content': msg.text,
        if (msg.kind != MessageKind.text) 'attachmentType': msg.kind.name,
        if (msg.quotedMessageId != null) 'quoteOf': msg.quotedMessageId,
        'metadata': {
          ...msg.metadata,
          'clientSentAt': DateTime.now().toIso8601String(),
        },
      };

  /// sending -> (sent | failed); on success the AI "types" then replies, and
  /// the delivered user messages flip to `read` (requirement 三 / 四).
  Future<void> _dispatch(ChatMessage msg) async {
    _setTyping(true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final failed = _random.nextDouble() < _failRate;
    setState(() => msg.status =
        failed ? MessageStatus.failed : MessageStatus.sent);
    _persist();
    if (failed) {
      _setTyping(false);
      return;
    }

    debugPrint('chat payload -> ${jsonEncode(_buildPayload(msg))}');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _addAiReply();
  }

  void _setTyping(bool v) {
    if (_aiTyping == v) return;
    setState(() => _aiTyping = v);
    if (v) _scrollToBottom();
  }

  void _addAiReply() {
    final reply = ChatMessage(
      id: ChatMessage.newId(),
      text: _placeholderReplies[_random.nextInt(_placeholderReplies.length)],
      isMe: false,
      time: DateTime.now(),
    );
    setState(() {
      _appendMessage(reply);
      _aiTyping = false;
      for (final m in _messages) {
        if (m.isMe && m.status == MessageStatus.sent) {
          m.status = MessageStatus.read;
        }
      }
    });
    _persist();
    _playNotificationSound();
    if (_showJumpBtn) {
      setState(() => _unread += 1);
    } else {
      _scrollToBottom();
    }
  }

  void _resend(ChatMessage msg) {
    setState(() => msg.status = MessageStatus.sending);
    _persist();
    _dispatch(msg);
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
        status: MessageStatus.sending,
      );
      setState(() => _appendMessage(msg));
      _persist();
      _scrollToBottom();
      _dispatch(msg);
    } catch (e) {
      _showSnack('无法打开：$e');
    }
  }

  void _openImage(ChatMessage msg) {
    if (_multiSelect) {
      _toggleSelect(msg);
      return;
    }
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

  // --- Long-press menu (requirement 一) -----------------------

  Future<void> _onLongPressMessage(Offset pos, ChatMessage msg) async {
    if (_multiSelect) return;
    final action =
        await showMessageMenu(context, anchor: pos, isFavorite: msg.favorite);
    if (!mounted || action == null) return;
    switch (action) {
      case MsgMenu.copy:
        await Clipboard.setData(
            ClipboardData(text: msg.text ?? msg.summary));
        _showSnack('已复制');
        break;
      case MsgMenu.favorite:
        setState(() => msg.favorite = !msg.favorite);
        _persist();
        break;
      case MsgMenu.delete:
        setState(() {
          _messages.removeWhere((m) => m.id == msg.id);
          _visibleCount = _visibleCount.clamp(0, _messages.length);
        });
        _persist();
        break;
      case MsgMenu.multi:
        setState(() {
          _multiSelect = true;
          _selectedIds
            ..clear()
            ..add(msg.id);
        });
        break;
      case MsgMenu.quote:
        setState(() => _quoted = msg);
        _focusNode.requestFocus();
        break;
      case MsgMenu.forward:
      case MsgMenu.remind:
      case MsgMenu.search:
        _showSnack('功能开发中');
        break;
    }
  }

  // --- Multi-select ------------------------------------------

  void _toggleSelect(ChatMessage msg) {
    setState(() {
      if (!_selectedIds.add(msg.id)) _selectedIds.remove(msg.id);
      if (_selectedIds.isEmpty) _multiSelect = false;
    });
  }

  void _exitMultiSelect() {
    setState(() {
      _multiSelect = false;
      _selectedIds.clear();
    });
  }

  void _deleteSelected() {
    setState(() {
      _messages.removeWhere((m) => _selectedIds.contains(m.id));
      _visibleCount = _visibleCount.clamp(0, _messages.length);
      _multiSelect = false;
      _selectedIds.clear();
    });
    _persist();
  }

  // --- Double-tap like (requirement 六) ---------------------

  void _handleDoubleTap(ChatMessage msg) {
    if (_multiSelect) return;
    final wasLiked = msg.liked;
    setState(() => msg.liked = !msg.liked);
    _persist();
    if (!wasLiked && _lastDoubleTapPos != null) {
      _spawnHeart(_lastDoubleTapPos!);
    }
  }

  void _spawnHeart(Offset globalPos) {
    final overlayState = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: globalPos.dx - 15,
        top: globalPos.dy - 44,
        child: IgnorePointer(
          child: FloatingHeart(onDone: () => entry.remove()),
        ),
      ),
    );
    overlayState.insert(entry);
  }

  // --- Jump / highlight ------------------------------------

  void _highlightAndScroll(String id) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    final needed = _messages.length - idx;
    setState(() {
      if (needed > _visibleCount) _visibleCount = _messages.length;
      _highlightId = id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.2, duration: const Duration(milliseconds: 350));
      } else if (_scrollController.hasClients) {
        final total = _messages.length;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo((idx / total * max).clamp(0.0, max));
      }
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  void _jumpToDate(DateTime day) {
    final key = dateKey(day);
    final idx = _messages.indexWhere((m) => dateKey(m.time) == key);
    if (idx < 0) {
      _showSnack('那天没有聊天记录');
      return;
    }
    _highlightAndScroll(_messages[idx].id);
  }

  void _jumpToQuoted(String? id) {
    if (id == null) return;
    if (_messages.indexWhere((m) => m.id == id) < 0) {
      _showSnack('原消息已删除');
      return;
    }
    _highlightAndScroll(id);
  }

  // --- Pull to refresh: older history (requirement 七) -----

  Future<void> _loadMoreHistory() async {
    if (_allHistoryShown) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _visibleCount =
        (_visibleCount + _pageSize).clamp(0, _messages.length));
  }

  // --- Top bar ---------------------------------------------------

  Future<void> _onSearch() async {
    final hit = await Navigator.of(context).push<SearchHit>(
      MaterialPageRoute(
        builder: (_) =>
            SearchScreen(conversations: _searchScope, settings: _s),
      ),
    );
    if (hit == null || !mounted) return;
    if (hit.conversationId == widget.conversation.id) {
      _jumpToTime(hit.time);
      return;
    }
    final matches =
        _searchScope.where((c) => c.id == hit.conversationId).toList();
    if (matches.isEmpty) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversation: matches.first,
        settings: _s,
        siblings: widget.siblings,
        moodScope: widget.moodScope,
        initialJumpTime: hit.time,
      ),
    ));
  }

  void _jumpToTime(DateTime t) {
    final matches = _messages.where((m) => m.time == t).toList();
    if (matches.isNotEmpty) {
      _highlightAndScroll(matches.first.id);
    } else {
      _jumpToDate(t);
    }
  }

  Future<void> _renameConversation() async {
    final controller = TextEditingController(text: widget.conversation.name);
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
          builder: (_) =>
              MoodCalendarScreen(settings: _s, scope: widget.moodScope),
        ));
        break;
      case 'clear':
        setState(() {
          _messages.clear();
          _visibleCount = 0;
        });
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

  // --- Export (requirement 二.9 from earlier round) ---------

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
      onTap: _multiSelect ? null : () => _pickAvatar(isMe),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(6), child: inner),
    );
  }

  Widget _statusIndicator(ChatMessage msg) {
    if (!msg.isMe) {
      return Text(
        formatClock(msg.time),
        style: TextStyle(
            fontSize: 9,
            color: _s.isDark ? Colors.white38 : Colors.black38),
      );
    }
    return switch (msg.status) {
      MessageStatus.sending => const SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
      MessageStatus.failed => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _resend(msg),
          child: const Icon(Icons.error, size: 14, color: Color(0xFFE53935)),
        ),
      MessageStatus.sent || MessageStatus.read => AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            fontSize: 9,
            color: msg.status == MessageStatus.read
                ? const Color(0xFFB0B0B0)
                : const Color(0xFFE8A0BF),
          ),
          child: Text(formatClock(msg.time)),
        ),
    };
  }

  Widget _buildAvatarColumn(ChatMessage msg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAvatar(msg.isMe),
        const SizedBox(height: 3),
        SizedBox(height: 14, child: Center(child: _statusIndicator(msg))),
      ],
    );
  }

  /// Compact row for a video / file message bubble.
  Widget _mediaChip(ChatMessage msg, IconData icon, String label, Color color,
      String tapHint) {
    return GestureDetector(
      onTap: () {
        if (_multiSelect) {
          _toggleSelect(msg);
        } else {
          _showSnack(tapHint);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final bubbleColor =
        msg.isMe ? _s.effectiveMyBubbleColor : _s.effectiveAiBubbleColor;
    final isImage = msg.kind == MessageKind.image;
    final textColor = _s.bubbleTextColorFor(msg.isMe);

    Widget body;
    if (isImage && msg.mediaPath != null) {
      body = GestureDetector(
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
    } else if (msg.kind == MessageKind.video) {
      body = _mediaChip(msg, Icons.play_circle_outline,
          msg.fileName ?? '视频', textColor, '视频播放开发中');
    } else if (msg.kind == MessageKind.file) {
      body = _mediaChip(msg, Icons.insert_drive_file_outlined,
          msg.fileName ?? '文件', textColor, '文件预览开发中');
    } else {
      final halo = _s.bubbleTextNeedsHalo(msg.isMe);
      body = Text(
        msg.text ?? '',
        style: TextStyle(
          fontSize: _s.messageFontSize,
          color: textColor,
          height: 1.3,
          shadows: halo
              ? [
                  Shadow(
                    blurRadius: 3,
                    color: (textColor.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white)
                        .withValues(alpha: 0.6),
                  ),
                ]
              : null,
        ),
      );
    }

    Widget inner = body;
    if (msg.quotedSummary != null) {
      inner = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _jumpToQuoted(msg.quotedMessageId),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                msg.quotedSummary!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.65)),
              ),
            ),
          ),
          body,
        ],
      );
    }

    final bubbleBox = GestureDetector(
      onLongPressStart: (d) => _onLongPressMessage(d.globalPosition, msg),
      onDoubleTapDown: (d) => _lastDoubleTapPos = d.globalPosition,
      onDoubleTap: () => _handleDoubleTap(msg),
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

    final bubbleWithHeart = Stack(
      clipBehavior: Clip.none,
      children: [
        bubbleBox,
        if (msg.liked)
          Positioned(
            right: -3,
            bottom: -5,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: _s.chatBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite,
                  size: 12, color: Color(0xFFE8577D)),
            ),
          ),
      ],
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
          ? [star, Flexible(child: bubbleWithHeart), tail]
          : [tail, Flexible(child: bubbleWithHeart), star],
    );
  }

  Widget _buildMessageRow(ChatMessage msg) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.62;
    final avatarColumn = _buildAvatarColumn(msg);
    final content = Flexible(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: _buildBubble(msg),
      ),
    );

    Widget row = Row(
      mainAxisAlignment:
          msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: msg.isMe
          ? [content, const SizedBox(width: 6), avatarColumn]
          : [avatarColumn, const SizedBox(width: 6), content],
    );

    if (_multiSelect) {
      final selected = _selectedIds.contains(msg.id);
      row = Row(
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: selected ? const Color(0xFF07C160) : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(child: row),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _multiSelect ? () => _toggleSelect(msg) : null,
      child: Container(
        color: msg.id == _highlightId
            ? const Color(0x33F5A623)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        child: row,
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

  Widget _typingRow() {
    final tc = _s.bubbleTextColorFor(false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(false),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _s.effectiveAiBubbleColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('对方正在输入',
                    style: TextStyle(fontSize: 13, color: tc)),
                const SizedBox(width: 6),
                TypingDots(color: tc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Message list ---------------------------------------

  Widget _messageList() {
    final vis = _visible;
    // Only worth telling the user "没有更多了" once there was actually more.
    final headerCount =
        (_allHistoryShown && _messages.length > _initialWindow) ? 1 : 0;
    final typingCount = _aiTyping ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _loadMoreHistory,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: headerCount + vis.length + typingCount,
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text('没有更多了',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            );
          }
          final i = index - headerCount;
          if (i == vis.length) return _typingRow();

          final msg = vis[i];
          final prev = i > 0 ? vis[i - 1] : null;
          final showTime = prev == null ||
              msg.time.difference(prev.time).abs() >= _timeSeparatorGap;

          final animate = !_animatedIds.contains(msg.id);
          if (animate) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _animatedIds.add(msg.id));
          }

          final row = _buildMessageRow(msg);
          return KeyedSubtree(
            key: _rowKeys.putIfAbsent(msg.id, () => GlobalKey()),
            child: Column(
              children: [
                if (showTime) _buildTimeSeparator(msg.time),
                animate
                    ? MessageEntry(
                        key: ValueKey('entry_${msg.id}'),
                        fromRight: msg.isMe,
                        child: row,
                      )
                    : row,
              ],
            ),
          );
        },
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

  Widget _quoteBar() {
    final q = _quoted!;
    return Container(
      width: double.infinity,
      color: _s.panelColor,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Container(width: 3, height: 28, color: const Color(0xFF07C160)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${q.isMe ? "我" : widget.conversation.name}：${q.summary}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: _s.inputTextColor.withValues(alpha: 0.7)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: _iconColor,
            onPressed: () => setState(() => _quoted = null),
          ),
        ],
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
                color: _s.inputFieldColor,
                borderRadius: BorderRadius.circular(5),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                cursorColor: _s.inputCursorColor,
                style: TextStyle(fontSize: 16, color: _s.inputTextColor),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintStyle: TextStyle(
                      color: _s.inputTextColor.withValues(alpha: 0.4)),
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
              : _iconBtn(Icons.add_circle_outline, _showFunctionSheet),
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

  // --- "+" function sheet (requirement 四) -------------------

  void _showFunctionSheet() {
    FocusScope.of(context).unfocus();
    setState(() => _panel = _Panel.none);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FunctionSheet(
        settings: _s,
        onPick: (action) {
          Navigator.of(ctx).pop();
          _handleFunctionAction(action);
        },
      ),
    );
  }

  void _handleFunctionAction(String action) {
    switch (action) {
      case FnAction.photo:
        _pickAndSendImage(ImageSource.gallery);
        break;
      case FnAction.camera:
        _pickAndSendImage(ImageSource.camera);
        break;
      case FnAction.file:
        _pickAndSendFile();
        break;
      case FnAction.video:
        _pickAndSendVideo();
        break;
      default:
        _showSnack('功能开发中');
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final XFile? f = await _picker.pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      final persisted = await Store.persistFile(f.path, 'vid');
      if (!mounted) return;
      _sendAttachment(
        persisted,
        kind: MessageKind.video,
        fileName: f.name,
      );
    } catch (e) {
      _showSnack('无法选择视频：$e');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final res = await FilePicker.platform.pickFiles();
      final picked = res?.files.isNotEmpty == true ? res!.files.first : null;
      final path = picked?.path;
      if (path == null) return;
      final persisted = await Store.persistFile(path, 'file');
      if (!mounted) return;
      _sendAttachment(
        persisted,
        kind: MessageKind.file,
        fileName: picked!.name,
      );
    } catch (e) {
      _showSnack('无法选择文件：$e');
    }
  }

  void _sendAttachment(String path,
      {required MessageKind kind, String? fileName}) {
    final now = DateTime.now();
    final msg = ChatMessage(
      id: ChatMessage.newId(),
      mediaPath: path,
      fileName: fileName,
      kind: kind,
      isMe: true,
      time: now,
      metadata: ChatMessage.outgoingMeta(now),
      status: MessageStatus.sending,
    );
    setState(() => _appendMessage(msg));
    _persist();
    _scrollToBottom();
    _dispatch(msg);
  }

  /// Fixed layer under everything (blur + tint mask). Never scrolls.
  Widget _wallpaperLayer() {
    final img = _s.wallpaperImagePath;
    final hasImage = img != null && File(img).existsSync();
    return Positioned.fill(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _s.chatBackgroundColor),
            if (hasImage) Image.file(File(img!), fit: BoxFit.cover),
            if (hasImage && _s.wallpaperBlur > 0)
              BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: _s.wallpaperBlur,
                  sigmaY: _s.wallpaperBlur,
                ),
                child: const SizedBox.expand(),
              ),
            if (_s.overlayOpacity > 0)
              ColoredBox(
                color: _s.overlayColor.withValues(alpha: _s.overlayOpacity),
              ),
          ],
        ),
      ),
    );
  }

  // --- App bars --------------------------------------------

  PreferredSizeWidget _normalAppBar() {
    return PreferredSize(
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
    );
  }

  PreferredSizeWidget _multiSelectAppBar() {
    return AppBar(
      backgroundColor: _s.appBarColor,
      foregroundColor: _s.appBarTextColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitMultiSelect,
      ),
      title: Text('已选 ${_selectedIds.length} 条'),
      actions: [
        IconButton(
          tooltip: '转发',
          icon: const Icon(Icons.ios_share),
          onPressed:
              _selectedIds.isEmpty ? null : () => _showSnack('功能开发中'),
        ),
        IconButton(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline),
          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _multiSelectBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        color: _s.panelColor,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            TextButton.icon(
              onPressed:
                  _selectedIds.isEmpty ? null : () => _showSnack('功能开发中'),
              icon: const Icon(Icons.ios_share),
              label: const Text('转发'),
            ),
            TextButton.icon(
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jumpButton() {
    return Material(
      color: _s.menuColor,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          _scrollToBottom();
          setState(() => _unread = 0);
        },
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.keyboard_arrow_down, color: _s.appBarTextColor),
              if (_unread > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      _unread > 99 ? '99+' : '$_unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, height: 1.1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _s.chatBackgroundColor,
      appBar: _multiSelect ? _multiSelectAppBar() : _normalAppBar(),
      body: Stack(
        children: [
          _wallpaperLayer(),
          Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismissAll,
                  child: _messageList(),
                ),
              ),
              if (!_multiSelect)
                SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_quoted != null) _quoteBar(),
                      _buildInputBar(),
                      if (_panel == _Panel.emoji) _buildEmojiPanel(),
                    ],
                  ),
                ),
              if (_multiSelect) _multiSelectBottomBar(),
            ],
          ),
          if (_showJumpBtn && !_multiSelect)
            Positioned(right: 14, bottom: 92, child: _jumpButton()),
        ],
      ),
    );
  }
}
