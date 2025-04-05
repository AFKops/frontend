import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/chat_provider.dart';
import 'home_screen.dart';
import '../providers/theme_provider.dart';
import '../services/ssh_service.dart';
import '../widgets/notepad.dart';
import '../utils/secure_storage.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({Key? key, required this.chatId}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<String> _filteredSuggestions = [];
  List<String> _fileSuggestions = [];
  bool _showTagPopup = false;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isTyping = false;
  bool _isAtBottom = true;
  bool _userHasScrolledUp = false;

  @override
  void initState() {
    super.initState();
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.addListener(_handleProviderUpdates);
    _scrollController.addListener(_onScroll);

    // Scroll to bottom on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });

    _messageController.addListener(_handleTextChanges);
  }

  @override
  void dispose() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.removeListener(_handleProviderUpdates);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Called whenever the ChatProvider changes:
  void _handleProviderUpdates() {
    if (!mounted) return;
    if (_userHasScrolledUp) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });
    setState(() {});
  }

  // Monitor scroll to see if user scrolled up away from bottom
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

  // Scroll to bottom helper
  void _scrollToBottom({bool immediate = false, bool force = false}) {
    if (!_scrollController.hasClients) return;
    if (!force && _userHasScrolledUp) return;
    final position = _scrollController.position.maxScrollExtent;
    final duration = immediate
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 300);
    _scrollController.animateTo(
      position,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  // Handle "cd " directory suggestions
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

  // Send a message or command
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

  // Show user is typing
  void _startTypingIndicator() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final lastMsg = chatProvider.getMessages(widget.chatId).lastOrNull;
    if (lastMsg != null && chatProvider.isStreamingCommand(lastMsg['text'])) {
      return; // Already streaming
    }
    setState(() => _isTyping = true);
    _scrollToBottom(immediate: true, force: true);
  }

  // Stop typing indicator
  void _stopTypingIndicator() {
    if (!mounted) return;
    setState(() => _isTyping = false);
  }

  // Prompt for password if needed
  Future<String?> _askForPassword(BuildContext context) async {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isLoading = false;
        String errorMessage = "";
        bool savePassword = false;
        final pwdCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: isDarkMode ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(
                "Enter SSH Password",
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errorMessage.isNotEmpty)
                      Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: true,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: "Password",
                        hintStyle: TextStyle(
                          color: isDarkMode ? Colors.white54 : Colors.grey[700],
                        ),
                        filled: true,
                        fillColor:
                            isDarkMode ? Colors.grey[900] : Colors.grey[200],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDarkMode ? Colors.white38 : Colors.black26,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: savePassword,
                          onChanged: (val) {
                            setState(() => savePassword = val ?? false);
                          },
                        ),
                        const Text("Save Password"),
                      ],
                    ),
                    if (isLoading) const CircularProgressIndicator(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(
                    "Cancel",
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(null),
                ),
                TextButton(
                  child: Text(
                    "Connect",
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() {
                            errorMessage = "";
                            isLoading = true;
                          });
                          final typed = pwdCtrl.text.trim();
                          if (typed.isEmpty) {
                            setState(() {
                              isLoading = false;
                              errorMessage = "Password cannot be empty.";
                            });
                            return;
                          }
                          // Attempt reconnect
                          final success = await chatProvider.reconnectAndCheck(
                            widget.chatId,
                            typed,
                          );
                          setState(() => isLoading = false);

                          if (success) {
                            if (savePassword) {
                              final chatData =
                                  chatProvider.getChatById(widget.chatId);
                              if (chatData != null) {
                                chatData['password'] = typed;
                                chatData['passwordSaved'] = true;
                                chatProvider.notifyListeners();

                                // Also store in SecureStorage so it appears in Settings
                                await SecureStorage.savePassword(
                                  widget.chatId,
                                  typed, // actual password
                                  chatData['name'] ?? "",
                                  chatData['host'] ?? "",
                                  chatData['username'] ?? "",
                                );
                              }
                            }
                            Navigator.of(ctx).pop(typed);
                          } else {
                            setState(() {
                              errorMessage = "Wrong password, try again.";
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Attempt reconnect if disconnected
  Future<void> _handleReconnect() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final chatData = chatProvider.getChatById(widget.chatId);
    if (chatData == null) return;

    final saved = chatData['passwordSaved'] == true;
    final savedPwd = chatData['password'];

    if (saved && savedPwd != null && savedPwd.isNotEmpty) {
      await chatProvider.reconnectChat(widget.chatId, savedPwd);
    } else {
      final typedPwd = await _askForPassword(context);
      if (typedPwd == null) {
        return; // user canceled or never succeeded
      }
      // If ephemeral usage only, do nothing more here
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(widget.chatId);
    final chatName = chatProvider.getChatName(widget.chatId);
    final isConnected = chatProvider.isChatActive(widget.chatId);

    return Scaffold(
      // Let us handle insets with MediaQuery + SafeArea
      resizeToAvoidBottomInset: false,
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
              if (!isConnected) {
                await _handleReconnect();
              } else {
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
      body: SafeArea(
        // This padding ensures everything moves up with the keyboard
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              // The main messages area
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 10),
                      itemCount: messages.length + (_isTyping ? 1 : 0),
                      itemBuilder: (context, index) {
                        // If user is typing, add the typing indicator
                        if (_isTyping && index == messages.length) {
                          return const _TypingIndicator();
                        }
                        final message = messages[index];
                        final isUserMessage = message['isUser'] ?? false;
                        final isStreaming = chatProvider.isStreaming(
                              widget.chatId,
                            ) &&
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

                    // If user is scrolled up, show a "jump to bottom" button
                    if (!_isAtBottom)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: 10,
                            bottom: 10,
                          ),
                          child: FloatingActionButton.small(
                            backgroundColor: Colors.black.withOpacity(0.7),
                            onPressed: () => _scrollToBottom(force: true),
                            child: const Icon(Icons.keyboard_arrow_down,
                                color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Suggestions row (only visible if we have suggestions)
              if (_showTagPopup && _filteredSuggestions.isNotEmpty)
                _buildSuggestionRow(),

              // The user’s chat input
              _chatInputBox(),
            ],
          ),
        ),
      ),
    );
  }

  // Directory suggestion row, shown above the input bar
  Widget _buildSuggestionRow() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;

    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 2),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start, // <-- left align
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _filteredSuggestions.map((dir) {
            return Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4), // reduced height
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: GestureDetector(
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
                child: Text(
                  dir,
                  style: TextStyle(
                    fontSize: 11, // smaller text
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w400,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // The bottom textfield + control row
  Widget _chatInputBox() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final chatData = chatProvider.chats[widget.chatId];

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Command input
          TextField(
            controller: _messageController,
            autocorrect: false,
            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: "Type a command...",
              hintStyle: TextStyle(
                color: isDarkMode ? Colors.white54 : Colors.black54,
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
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            ),
            onTap: () {
              _scrollToBottom(force: true);
            },
          ),

          const SizedBox(height: 8),

          // Row of buttons: Back (cd..), Ctrl+C, Notepad, Send
          Row(
            children: [
              // Back (cd ..)
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: isDarkMode ? Colors.white : Colors.black),
                onPressed: () {
                  chatProvider.sendCommand(widget.chatId, "cd ..",
                      silent: true);
                },
              ),

              // Ctrl+C
              IconButton(
                icon: Icon(Icons.stop_circle_outlined,
                    color: isDarkMode ? Colors.red[300] : Colors.red),
                onPressed: () {
                  final ssh = chatData?['service'] as SSHService?;
                  ssh?.sendCtrlC();
                  chatProvider.addMessage(
                    widget.chatId,
                    "🚫 Force Ctrl+C sent.",
                    isUser: false,
                  );
                },
              ),

              // 📝 Notepad button for full editor
              IconButton(
                icon: Icon(Icons.edit_note,
                    color: isDarkMode ? Colors.white70 : Colors.black87),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullNotepadScreen(chatId: widget.chatId),
                    ),
                  );
                },
              ),

              const Spacer(),

              // Send
              IconButton(
                icon: Icon(Icons.send,
                    color: isDarkMode ? Colors.white : Colors.black),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // One bubble in the chat
  Widget _buildMessageBubble(
    String text,
    bool isUserMessage, {
    bool isStreaming = false,
    required String chatId,
    required int index,
  }) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(chatId);
    final chatData = chatProvider.chats[chatId];
    final inProgress = (chatData?['inProgress'] == true);
    final isLastMessage = (index == messages.length - 1);

    // Handle <small> tags
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
            duration: Duration(seconds: 1),
          ),
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
                            chatId,
                            "❌ Command cancelled.",
                            isUser: false,
                          );
                          chatProvider.notifyListeners();
                        }
                        Future.delayed(const Duration(milliseconds: 200), () {
                          if (mounted) setState(() {});
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "🛑 Stop ${isStreaming ? "Streaming" : "Command"}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
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

// The “...” typing dots shown while user is typing
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
