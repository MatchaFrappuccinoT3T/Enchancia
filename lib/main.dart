import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final String text;
  final bool isMe;
  final DateTime time;

  ChatMessage({
    required this.text,
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
  final List<ChatMessage> _messages = [];
  final Random _random = Random();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  Future<void> _showCopyMenu(BuildContext context, Offset position, String text) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 36,
          child: Text(
            '复制',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
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

  Widget _buildAvatar(bool isMe) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        color: isMe ? const Color(0xFFB0E0E6) : const Color(0xFFE0D0D0),
        alignment: Alignment.center,
        child: Text(
          isMe ? '辰' : '哥',
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, ChatMessage msg) {
    final bubbleColor = msg.isMe ? const Color(0xFFFFE4E1) : Colors.white;

    final bubbleContent = GestureDetector(
      onLongPressStart: (details) => _showCopyMenu(context, details.globalPosition, msg.text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          msg.text,
          style: const TextStyle(fontSize: 15, color: Colors.black),
        ),
      ),
    );

    final tail = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CustomPaint(
        size: const Size(6, 10),
        painter: _BubbleTailPainter(color: bubbleColor, pointLeft: !msg.isMe),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: msg.isMe
          ? [Flexible(child: bubbleContent), tail]
          : [tail, Flexible(child: bubbleContent)],
    );
  }

  Widget _buildMessageRow(BuildContext context, ChatMessage msg) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.7;
    final avatar = _buildAvatar(msg.isMe);
    final bubble = Flexible(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: _buildBubble(context, msg),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: msg.isMe
            ? [bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
      ),
    );
  }

  Widget _buildBarIcon(
    IconData icon, {
    double size = 24,
    Color color = Colors.black54,
    double boxSize = 36,
  }) {
    return IconButton(
      icon: Icon(icon, size: size, color: color),
      onPressed: () {},
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: boxSize, minHeight: boxSize),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildBarIcon(Icons.mic_none, size: 20, color: Colors.grey, boxSize: 32),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 36,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _buildBarIcon(Icons.emoji_emotions_outlined),
            _buildBarIcon(Icons.add_circle_outline),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE0D0D0),
              child: const Text('哥', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('哥哥宝宝',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                Text('在线', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessageRow(context, _messages[index]),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }
}
