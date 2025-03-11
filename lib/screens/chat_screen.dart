import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/chat_provider.dart';
import 'home_screen.dart';
import '../providers/theme_provider.dart';
import '../services/ssh_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({Key? key, required this.chatId}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Directory suggestions
  List<String> _filteredSuggestions = [];
  bool _showTagPopup = false;
  List<String> _fileSuggestions = [];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isTyping = false;
  bool _isAtBottom = true;
  bool _userHasScrolledUp = false;

  // Called after init; sets listeners.
  @override
  void initState() {
    super.initState();
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.addListener(_handleProviderUpdates);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });
    _messageController.addListener(_handleTextChanges);
  }

  // Disposes controllers.
  @override
  void dispose() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.removeListener(_handleProviderUpdates);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Updates UI when provider changes.
  void _handleProviderUpdates() {
    if (!mounted) return;
    if (_userHasScrolledUp) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });
    setState(() {});
  }

  // Monitors scroll position.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final distanceFromBottom = maxScroll - offset;
    setState(() {
      _isAtBottom = distanceFromBottom <= 50;
      _userHasScrolledUp = distanceFromBottom > 50;
    });
  }

  // Scrolls to bottom.
  void _scrollToBottom({bool immediate = false, bool force = false}) {
    if (!_scrollController.hasClients) return;
    if (!force && _userHasScrolledUp) return;
    final position = _scrollController.position.maxScrollExtent;
    final duration = immediate
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 300);
    _scrollController.animateTo(position,
        duration: duration, curve: Curves.easeOut);
  }

  // Handles directory suggestion logic.
  void _handleTextChanges() async {
    final input = _messageController.text.trim();
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (!input.toLowerCase().startsWith("cd")) {
      setState(() {
        _filteredSuggestions.clear();
        _showTagPopup = false;
      });
      return;
    }
    final rawQuery = input.length > 2 ? input.substring(3).trim() : "";
    final isRequestingSubdir = rawQuery.endsWith("/");
    if (isRequestingSubdir || rawQuery.isEmpty) {
      await chatProvider.updateFileSuggestions(widget.chatId, query: rawQuery);
    }
    setState(() {
      _fileSuggestions =
          chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
      if (rawQuery.isEmpty) {
        _filteredSuggestions = List<String>.from(_fileSuggestions);
      } else {
        final parts = rawQuery.split("/");
        final lastPart = parts.last;
        _filteredSuggestions =
            _fileSuggestions.where((dir) => dir.startsWith(lastPart)).toList();
      }
      _showTagPopup = _filteredSuggestions.isNotEmpty;
    });
  }

  // Sends a message or command.
  Future<void> _sendMessage() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final text = _messageController.text.trim();
    _messageController.clear();
    if (text.isEmpty) return;
    if (chatProvider.isStreaming(widget.chatId)) {
      chatProvider.stopStreaming(widget.chatId);
    }
    chatProvider.addMessage(widget.chatId, text, isUser: true);
    _startTypingIndicator();
    _scrollToBottom(immediate: true, force: true);
    try {
      if (chatProvider.isStreamingCommand(text)) {
        chatProvider.startStreaming(widget.chatId, text);
      } else {
        final response = await chatProvider.sendCommand(widget.chatId, text);
        if (text.startsWith("cd ")) {
          await chatProvider.updateFileSuggestions(widget.chatId);
          _fileSuggestions =
              chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
        } else {
          _filteredSuggestions.clear();
          _showTagPopup = false;
        }
        _stopTypingIndicator();
        if (response != null && response.isNotEmpty) {
          chatProvider.addMessage(widget.chatId, response, isUser: false);
        }
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToBottom();
        });
      }
    } catch (e) {
      _stopTypingIndicator();
      chatProvider.addMessage(widget.chatId, "❌ SSH Error: $e", isUser: false);
      _scrollToBottom(force: true);
    }
  }

  // Starts typing indicator.
  void _startTypingIndicator() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final lastMsg = chatProvider.getMessages(widget.chatId).lastOrNull;
    if (lastMsg != null && chatProvider.isStreamingCommand(lastMsg['text'])) {
      return;
    }
    setState(() => _isTyping = true);
    _scrollToBottom(immediate: true, force: true);
  }

  // Stops typing indicator.
  void _stopTypingIndicator() {
    if (!mounted) return;
    setState(() => _isTyping = false);
  }

  // Prompts user for password.
  Future<String?> _askForPassword(BuildContext context) async {
    final TextEditingController pwdCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Enter SSH Password"),
          content: TextField(
            controller: pwdCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: "Password"),
          ),
          actions: [
            TextButton(
              child: const Text("CANCEL"),
              onPressed: () => Navigator.of(ctx).pop(null),
            ),
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                final entered = pwdCtrl.text.trim();
                Navigator.of(ctx).pop(entered.isEmpty ? null : entered);
              },
            ),
          ],
        );
      },
    );
  }

  // Attempts to reconnect if disconnected.
  Future<void> _handleReconnect() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final chatData = chatProvider.getChatById(widget.chatId);
    if (chatData == null) return;

    final saved = chatData['passwordSaved'] == true;
    final savedPwd = chatData['password'];

    if (saved && savedPwd != null && savedPwd.isNotEmpty) {
      await chatProvider.reconnectChat(widget.chatId, savedPwd);
    } else {
      final newPwd = await _askForPassword(context);
      if (newPwd == null) return;
      final encoded = chatProvider.encodePassword(newPwd);

      // If you want ephemeral usage only, do NOT store the password again:
      // chatData['password'] = encoded;
      // chatData['passwordSaved'] = true;

      await chatProvider.reconnectChat(widget.chatId, encoded);
    }
  }

  // Builds UI.
  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(widget.chatId);
    final chatName = chatProvider.getChatName(widget.chatId);
    final isConnected = chatProvider.isChatActive(widget.chatId);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDarkMode ? const Color(0xFF0D0D0D) : Colors.white,
      appBar: AppBar(
        title: Text(chatName, style: const TextStyle(fontSize: 18)),
        backgroundColor: isDarkMode ? const Color(0xFF0D0D0D) : Colors.white,
        iconTheme: IconThemeData(
          color: isDarkMode ? Colors.white : Colors.black,
        ),
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? Icons.check_circle : Icons.refresh,
              color: isConnected ? Colors.green : Colors.red,
            ),
            onPressed: () async {
              // Debug log
              print(
                  "[DEBUG] Tapped the connection icon. isConnected = $isConnected");
              // Show ChatProvider’s actual 'connected' status from the data model
              final actualConnState =
                  chatProvider.chats[widget.chatId]?['connected'];
              print("[DEBUG] chatData['connected']: $actualConnState");

              if (!isConnected) {
                print("[DEBUG] Attempting to reconnect...");
                await _handleReconnect();
              } else {
                print("[DEBUG] Already connected: no action taken.");
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Already connected")),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
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
                    final isUserMessage = message['isUser'] ?? false;
                    final isStreaming =
                        chatProvider.isStreaming(widget.chatId) &&
                            index == messages.length - 1;
                    return Align(
                      alignment: isUserMessage
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: _buildMessageBubble(
                        message['text'],
                        isUserMessage,
                        isStreaming: isStreaming,
                        chatId: widget.chatId,
                        index: index,
                      ),
                    );
                  },
                ),
              ),
              _chatInputBox(),
            ],
          ),
          if (_showTagPopup && _filteredSuggestions.isNotEmpty) _tagPopup(),
          if (!_isAtBottom)
            Positioned(
              right: 10,
              bottom: 75,
              child: FloatingActionButton.small(
                backgroundColor: Colors.black.withOpacity(0.7),
                onPressed: () => _scrollToBottom(force: true),
                child:
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // Builds the input row at the bottom.
  Widget _chatInputBox() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              autocorrect: false,
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "Type a command...",
                hintStyle: TextStyle(
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                ),
                prefixIcon: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  onPressed: () {
                    chatProvider.sendCommand(widget.chatId, "cd ..",
                        silent: true);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.white38 : Colors.black26,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.white24 : Colors.black12,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                filled: true,
                fillColor: Colors.transparent,
              ),
              onTap: () {
                _scrollToBottom(force: true);
              },
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.send,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  // Builds the tag popup for cd suggestions.
  Widget _tagPopup() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    return Positioned(
      left: 15,
      bottom: 75,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width - 30,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _filteredSuggestions.map((dir) {
                return GestureDetector(
                  onTap: () {
                    final currentText = _messageController.text.trim();
                    if (currentText.startsWith("cd ")) {
                      final parts = currentText.split(" ");
                      if (parts.length > 1) {
                        final pathParts = parts[1].split("/");
                        pathParts.removeLast();
                        pathParts.add(dir);
                        _messageController.text = "cd " + pathParts.join("/");
                      } else {
                        _messageController.text = "cd $dir";
                      }
                    } else {
                      _messageController.text = "cd $dir";
                    }
                    setState(() {
                      _filteredSuggestions.clear();
                      _showTagPopup = false;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF2A2A2A)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      dir,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w300,
                        color: isDarkMode ? Colors.white : Colors.black87,
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

  // Builds a single message bubble.
  Widget _buildMessageBubble(String text, bool isUserMessage,
      {bool isStreaming = false, required String chatId, required int index}) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(chatId);
    final chatData = chatProvider.chats[chatId];
    final inProgress = (chatData?['inProgress'] == true);
    final isLastMessage = (index == messages.length - 1);
    String smallCommand = "";
    String mainText = text;
    final smallMatch = RegExp(r"<small>(.*?)<\/small>").firstMatch(text);
    if (smallMatch != null) {
      smallCommand = smallMatch.group(1) ?? "";
      mainText = text.replaceAll(smallMatch.group(0)!, "").trim();
    }
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1)),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUserMessage
              ? (isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[300])
              : (isDarkMode
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (smallCommand.isNotEmpty)
              Text(
                smallCommand,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: "monospace",
                  color: isDarkMode ? Colors.white38 : Colors.black45,
                ),
              ),
            SelectableText(
              mainText,
              style: TextStyle(
                fontSize: 14,
                fontFamily: "monospace",
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
            if (isLastMessage && !isUserMessage && (isStreaming || inProgress))
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    Text(
                      isStreaming ? "Streaming..." : "In progress...",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        if (isStreaming) {
                          chatProvider.stopStreaming(chatId);
                        } else {
                          final ssh = chatData?['service'] as SSHService?;
                          ssh?.stopCurrentProcess();
                          chatData?['inProgress'] = false;
                          chatProvider.addMessage(
                              chatId, "❌ Command cancelled.",
                              isUser: false);
                          chatProvider.notifyListeners();
                        }
                        Future.delayed(const Duration(milliseconds: 200), () {
                          if (mounted) setState(() {});
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "🛑 Stop ${isStreaming ? "Streaming" : "Command"}",
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
                      ),
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  _TypingIndicatorState createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  // Initializes animations.
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

  // Builds typing indicator.
  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              final opacity =
                  (_animation.value - (index * 0.2)).clamp(0.3, 1.0);
              return Opacity(
                opacity: opacity,
                child: Text(
                  "•",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }

  // Cleans up controller.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
