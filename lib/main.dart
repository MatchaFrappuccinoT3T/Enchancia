import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const EnchanciaApp());
}

class EnchanciaApp extends StatelessWidget {
  const EnchanciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enchancia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC0CB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String? text;
  final File? image;
  final bool isMe;
  final DateTime time;

  ChatMessage({
    this.text,
    this.image,
    required this.isMe,
    required this.time,
  });
}

const List<String> _placeholderReplies = [
  '收到啦~',
  '嗯嗯，知道了',
  '好呀好呀',
  '在忙，等下回你',
  '哈哈哈是这样嘛',
];

/// Which bottom panel is currently open below the input bar.
enum _Panel { none, emoji, functions }

const List<String> _commonEmojis = [
  '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😜',
  '😎', '🤗', '🤔', '😴', '😭', '😅', '😉', '🙃',
  '😌', '😏', '😢', '😤', '👍', '👎', '👌', '🙏',
  '👏', '💪', '🤝', '✌️', '🤟', '👋', '❤️', '💔',
  '💕', '💖', '✨', '🌟', '🔥', '🎉', '🌸', '🍺',
];

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
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointLeft != pointLeft;
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  final Random _random = Random();
  final ImagePicker _picker = ImagePicker();

  File? _myAvatar;
  _Panel _panel = _Panel.none;

  @override
  void initState() {
    super.initState();
    // Rebuild so the send button / emoji icon reflect the current text.
    _controller.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _panel != _Panel.none) {
        setState(() => _panel = _Panel.none);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isMe: true,
        time: DateTime.now(),
      ));
    });
    _controller.clear();
    _scrollToBottom();
    _replyLater();
  }

  void _replyLater() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: _placeholderReplies[_random.nextInt(_placeholderReplies.length)],
          isMe: false,
          time: DateTime.now(),
        ));
      });
      _scrollToBottom();
    });
  }

  // --- Panels -------------------------------------------------------------

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
    final newText = value.text.replaceRange(start, end, emoji);
    _controller.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
      composing: TextRange.empty,
    );
  }

  // --- Image picking ----------------------------------------------------

  Future<void> _pickAvatar() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 480,
        imageQuality: 90,
      );
      if (file == null) return;
      setState(() => _myAvatar = File(file.path));
    } catch (e) {
      _showError('无法读取图片：$e');
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
      setState(() {
        _messages.add(ChatMessage(
          image: File(file.path),
          isMe: true,
          time: DateTime.now(),
        ));
      });
      _scrollToBottom();
      _replyLater();
    } catch (e) {
      _showError('无法打开：$e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // --- Long-press copy menu -------------------------------------------

  Future<void> _showCopyMenu(
      BuildContext context, Offset position, String text) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        const PopupMenuItem<String>(
          value: 'copy',
          height: 36,
          child: Text('复制', style: TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ],
    );

    if (selected == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  // --- Top bar actions -------------------------------------------------

  void _onBack() {
    Navigator.of(context).maybePop().then((popped) {
      if (!popped) SystemNavigator.pop();
    });
  }

  void _onSearch() {
    showSearch<String>(
      context: context,
      delegate: _MessageSearchDelegate(_messages),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'clear':
        setState(_messages.clear);
        break;
      case 'search':
        _onSearch();
        break;
      case 'mute':
      case 'settings':
        _showError('功能暂未实现');
        break;
    }
  }

  // --- Avatars / bubbles --------------------------------------------

  Widget _buildAvatar(bool isMe) {
    Widget inner;
    if (isMe && _myAvatar != null) {
      inner = Image.file(_myAvatar!, width: 40, height: 40, fit: BoxFit.cover);
    } else {
      inner = Container(
        width: 40,
        height: 40,
        color: isMe ? const Color(0xFFB0E0E6) : const Color(0xFFE0D0D0),
        alignment: Alignment.center,
        child: Text(
          isMe ? '辰' : '哥',
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
      );
    }
    return GestureDetector(
      onTap: isMe ? _pickAvatar : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: inner,
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, ChatMessage msg) {
    final bubbleColor =
        msg.isMe ? const Color(0xFFFBF0F5) : Colors.white;
    final bool isImage = msg.image != null;

    Widget inner;
    if (isImage) {
      inner = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180, maxHeight: 220),
          child: Image.file(msg.image!, fit: BoxFit.cover),
        ),
      );
    } else {
      inner = Text(
        msg.text ?? '',
        style: const TextStyle(fontSize: 15, color: Colors.black, height: 1.3),
      );
    }

    final bubbleContainer = GestureDetector(
      onLongPressStart: msg.text != null
          ? (details) =>
              _showCopyMenu(context, details.globalPosition, msg.text!)
          : null,
      child: Container(
        padding: isImage
            ? const EdgeInsets.all(3)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: inner,
      ),
    );

    final tail = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: CustomPaint(
        size: const Size(6, 11),
        painter: _BubbleTailPainter(color: bubbleColor, pointLeft: !msg.isMe),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: msg.isMe
          ? [Flexible(child: bubbleContainer), tail]
          : [tail, Flexible(child: bubbleContainer)],
    );
  }

  Widget _buildMessageRow(BuildContext context, ChatMessage msg) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.68;
    final avatar = _buildAvatar(msg.isMe);
    final content = Flexible(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: _buildMessageContent(context, msg),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: msg.isMe
            ? [content, const SizedBox(width: 6), avatar]
            : [avatar, const SizedBox(width: 6), content],
      ),
    );
  }

  // --- Input bar ----------------------------------------------------

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 28, color: Colors.black54),
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
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F7),
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Voice button — keeps its existing (no-op) behaviour.
          _iconBtn(Icons.settings_voice_outlined, () {}),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
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
                style: const TextStyle(fontSize: 16, color: Colors.black),
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
      color: const Color(0xFFF7F7F7),
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(8),
        children: [
          for (final e in _commonEmojis)
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 30, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  Widget _buildFunctionPanel() {
    return Container(
      height: 200,
      width: double.infinity,
      color: const Color(0xFFF7F7F7),
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

  Widget _buildBackButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: _onBack,
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            child: const Text(
              '1',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 10, height: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
          ),
          child: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: _buildBackButton(),
            centerTitle: true,
            title: const Text(
              '哥哥宝宝',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: Colors.black87),
                onPressed: _onSearch,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.black87),
                onSelected: _onMenuSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'search', child: Text('搜索聊天记录')),
                  PopupMenuItem(value: 'mute', child: Text('消息免打扰')),
                  PopupMenuItem(value: 'clear', child: Text('清空聊天记录')),
                  PopupMenuItem(value: 'settings', child: Text('设置')),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissAll,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) =>
                    _buildMessageRow(context, _messages[index]),
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
    );
  }
}

class _MessageSearchDelegate extends SearchDelegate<String> {
  final List<ChatMessage> messages;

  _MessageSearchDelegate(this.messages) : super(searchFieldLabel: '搜索聊天记录');

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _resultList();

  @override
  Widget buildSuggestions(BuildContext context) => _resultList();

  Widget _resultList() {
    final q = query.trim();
    if (q.isEmpty) {
      return const Center(
        child: Text('输入关键字搜索聊天记录',
            style: TextStyle(color: Colors.grey)),
      );
    }
    final results = messages
        .where((m) => (m.text ?? '').contains(q))
        .toList()
        .reversed
        .toList();
    if (results.isEmpty) {
      return const Center(
        child: Text('没有找到相关聊天记录',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final m = results[index];
        return ListTile(
          leading: Icon(m.isMe ? Icons.person : Icons.face,
              color: Colors.black45),
          title: Text(m.text ?? ''),
          subtitle: Text(_fmt(m.time)),
          onTap: () => close(context, m.text ?? ''),
        );
      },
    );
  }

  static String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
