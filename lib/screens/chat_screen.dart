import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey _directoryButtonKey = GlobalKey();
  List<String> _filteredSuggestions = []; // Stores filtered directory names
  bool _showTagPopup = false; // Controls tag pop-up visibility
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _isAtBottom = true;
  List<String> _fileSuggestions = []; // Stores the suggested files

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    _messageController.addListener(() async {
      String input = _messageController.text.trim();

      if (input.startsWith("cd ") && input.length > 3) {
        String query = input.substring(3);

        // ✅ Auto-fetch only if _fileSuggestions is empty (prevents duplicate popups)
        if (_fileSuggestions.isEmpty) {
          await Provider.of<ChatProvider>(context, listen: false)
              .updateFileSuggestions(widget.chatId);

          setState(() {
            _fileSuggestions = Provider.of<ChatProvider>(context, listen: false)
                    .chats[widget.chatId]?['fileSuggestions'] ??
                [];
          });
        }

        List<String> matches = _fileSuggestions
            .where((file) => file.startsWith(query))
            .toSet() // ✅ Ensures uniqueness
            .toList();

        setState(() {
          // ✅ Update suggestions only if different from the current state
          if (_filteredSuggestions != matches) {
            _filteredSuggestions = matches;
            _showTagPopup = _filteredSuggestions.isNotEmpty;
          }
        });
      } else {
        setState(() {
          _filteredSuggestions.clear();
          _showTagPopup = false;
        });
      }
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

      // ✅ If "cd" command, auto-fetch directory contents
      if (message.startsWith("cd ")) {
        await chatProvider.updateFileSuggestions(widget.chatId);
        setState(() {
          _fileSuggestions =
              chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
        });
      }

      _stopTypingIndicator();
      chatProvider.addMessage(widget.chatId, response, isUser: false);
      _scrollToBottom();
    } catch (e) {
      _stopTypingIndicator();
      chatProvider.addMessage(widget.chatId, "❌ SSH Error: $e", isUser: false);
    }
  }

  /// **Displays a Popup with Directory Contents**
  void _showDirectoryDropdown(BuildContext context, GlobalKey key) async {
    await Provider.of<ChatProvider>(context, listen: false)
        .updateFileSuggestions(widget.chatId); // ✅ Fetch directory

    setState(() {
      _fileSuggestions = Provider.of<ChatProvider>(context, listen: false)
              .chats[widget.chatId]?['fileSuggestions'] ??
          [];
    });

    final RenderBox renderBox =
        key.currentContext!.findRenderObject() as RenderBox;
    final Offset position = renderBox.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, // ✅ Align under the directory button
        position.dy + renderBox.size.height + 5, // ✅ Place it right below
        position.dx + 150, // ✅ Fixed width for dropdown
        position.dy + renderBox.size.height + 200, // ✅ Adjust dropdown height
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // ✅ Keep rounded design
      ),
      items: [
        if (Provider.of<ChatProvider>(context, listen: false)
            .canGoBack(widget.chatId))
          PopupMenuItem(
            onTap: () => Provider.of<ChatProvider>(context, listen: false)
                .goBackDirectory(widget.chatId),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, size: 16, color: Colors.black54),
                const SizedBox(width: 5),
                const Text(
                  "Go Back",
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: "monospace",
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ..._fileSuggestions.map((dir) {
          return PopupMenuItem(
            onTap: () {
              setState(() {
                _messageController.text = "cd $dir";
              });
            },
            child: Text(
              dir,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: "monospace",
                color: Colors.black87,
              ),
            ),
          );
        }).toList(),
      ],
    );
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
            icon: Icon(isConnected ? Icons.check_circle : Icons.cancel,
                color: isConnected ? Colors.green : Colors.grey),
            onPressed: () {},
          ),
          IconButton(
            key: _directoryButtonKey, // ✅ Assign the key
            icon: const Icon(Icons.folder_open),
            onPressed: () =>
                _showDirectoryDropdown(context, _directoryButtonKey),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const HomeScreen())),
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

          // ✅ Auto-suggestion Popup (ONLY SHOW WHEN THERE ARE SUGGESTIONS)
          if (_filteredSuggestions.isNotEmpty) _tagPopup(),

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

  Widget _chatInputBox() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  onChanged: (text) =>
                      {}, // ✅ No inline auto-fill, just trigger pop-up
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
        ),
      ],
    );
  }

  Widget _tagPopup() {
    if (_filteredSuggestions.isEmpty)
      return const SizedBox.shrink(); // Hide if empty

    return Positioned(
      left: 15, // Align to left
      bottom: 75, // Position above the input
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: 3), // ✅ More compact padding
          decoration: BoxDecoration(
            color: Colors.grey[50], // ✅ Softer background
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filteredSuggestions.map((dir) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _messageController.text = "cd $dir"; // Auto-fill
                      _filteredSuggestions.clear();
                      _showTagPopup = false;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5), // ✅ Compact spacing
                    decoration: BoxDecoration(
                      color: Colors.grey[100], // ✅ Light background
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      dir,
                      style: const TextStyle(
                        fontSize: 12, // ✅ Smaller font
                        fontFamily: 'monospace', // ✅ Monospace font
                        fontWeight: FontWeight.w300, // ✅ Lighter font weight
                        color: Colors.black87, // ✅ Darker text for contrast
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUserMessage) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: text)); // ✅ Copy to clipboard

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUserMessage ? Colors.grey[300] : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: isUserMessage
            ? SelectableText(
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
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    text,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: "monospace",
                      color: Color.fromARGB(255, 66, 66, 66),
                    ),
                  ),
                ],
              ),
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
