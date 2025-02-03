import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'home_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    _messageController.addListener(() {
      if (_messageController.text.isNotEmpty) _scrollToBottom();
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.offset >=
            _scrollController.position.maxScrollExtent - 50) {
      setState(() => _isAtBottom = true);
    } else {
      setState(() => _isAtBottom = false);
    }
  }

  void _scrollToBottom({bool immediate = false}) {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 50,
          duration: immediate
              ? const Duration(milliseconds: 200)
              : const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startTypingIndicator() {
    setState(() => _isTyping = true);
    _scrollToBottom();
  }

  void _stopTypingIndicator() {
    if (!mounted) return;
    setState(() => _isTyping = false);
  }

  Future<void> _sendMessage() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    String message = _messageController.text.trim();
    _messageController.clear();

    if (message.isEmpty) return;

    chatProvider.addMessage(widget.chatId, message, isUser: true);
    _startTypingIndicator();

    try {
      String response = await chatProvider.sendCommand(widget.chatId, message);
      _stopTypingIndicator();
      chatProvider.addMessage(widget.chatId, response, isUser: false);
      _scrollToBottom();
    } catch (e) {
      _stopTypingIndicator();
      chatProvider.addMessage(widget.chatId, "❌ SSH Error: $e", isUser: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(widget.chatId);
    final chatName = chatProvider.getChatName(widget.chatId);
    final isConnected = chatProvider.isChatActive(widget.chatId);

    return Scaffold(
      appBar: AppBar(
        title: Text(chatName, style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? Icons.check_circle : Icons.cancel,
              color: isConnected ? Colors.green : Colors.grey,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  itemCount: messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isTyping && index == messages.length) {
                      return const _TypingIndicator();
                    }

                    final message = messages[index];
                    final bool isUserMessage = message['isUser'] ?? false;

                    return Align(
                      alignment: isUserMessage
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child:
                          _buildMessageBubble(message['text'], isUserMessage),
                    );
                  },
                ),
              ),
              _chatInputBox(),
            ],
          ),
          if (!_isAtBottom)
            Positioned(
              right: 10,
              bottom: 75,
              child: FloatingActionButton.small(
                backgroundColor: Colors.black.withOpacity(0.7),
                elevation: 2,
                onPressed: _scrollToBottom,
                child:
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  /// ✅ **Formats messages to look like Bash output**
  Widget _buildMessageBubble(String text, bool isUserMessage) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUserMessage
            ? Colors.grey[300]
            : const Color(0xFFF0F0F0), // ✅ Correct ARGB format
        borderRadius: BorderRadius.circular(12),
      ),
      child: isUserMessage
          ? Text(
              text,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Bash",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey, // ✅ Light grey text
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14, // ✅ Reduced font size for SSH output
                    fontFamily: "monospace",
                    color: Color.fromARGB(255, 66, 66,
                        66), // ✅ Slightly darker grey text for contrast
                  ),
                ),
              ],
            ),
    );
  }

  Widget _chatInputBox() {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: "Message...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25.0)),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.black),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}

/// ✅ Messenger-style animated typing indicator
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  _TypingIndicatorState createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Opacity(
                opacity: (_animation.value - (index * 0.2)).clamp(0.3, 1.0),
                child: const Text(
                  "•",
                  style: TextStyle(fontSize: 24, color: Colors.black),
                ),
              );
            },
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
