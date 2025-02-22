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
  final GlobalKey _directoryButtonKey = GlobalKey();

  // Directory suggestions
  List<String> _filteredSuggestions = [];
  bool _showTagPopup = false;
  List<String> _fileSuggestions = [];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isTyping = false;
  bool _isAtBottom = true;

  /// If `true`, user has scrolled away from the bottom, so we
  /// temporarily stop auto-scrolling on new messages.
  bool _userHasScrolledUp = false;

  @override
  void initState() {
    super.initState();

    // Listen to ChatProvider changes (new messages, etc.)
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.addListener(_handleProviderUpdates);

    _scrollController.addListener(_onScroll);

    // After first build, scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });

    // Also, watch text changes for "cd " directory suggestions
    _messageController.addListener(_handleTextChanges);
  }

  @override
  void dispose() {
    // Remove listeners
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.removeListener(_handleProviderUpdates);

    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Provider Listener: Called any time new messages or state changes
  // --------------------------------------------------------------------------
  void _handleProviderUpdates() {
    if (!mounted) return;
    // If the user is currently scrolled away from the bottom, do not auto-scroll
    // unless they've re-scrolled near the bottom.
    if (_userHasScrolledUp) {
      // Keep the user’s scroll position
      return;
    }
    // Otherwise, auto-scroll to show new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });
    setState(() {});
  }

  // --------------------------------------------------------------------------
  // SCROLL LOGIC
  // --------------------------------------------------------------------------
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // If we are close to the bottom (say within 50px),
    // consider that the user is effectively at the bottom.
    final distanceFromBottom = (maxScroll - offset);

    setState(() {
      _isAtBottom = distanceFromBottom <= 50;
    });

    // If user is no longer near bottom, set `_userHasScrolledUp = true`.
    // If user is back near bottom, set `_userHasScrolledUp = false`.
    if (distanceFromBottom > 50) {
      _userHasScrolledUp = true;
    } else {
      _userHasScrolledUp = false;
    }
  }

  /// Scroll to the latest message
  void _scrollToBottom({bool immediate = false, bool force = false}) {
    if (!_scrollController.hasClients) return;

    // Only auto-scroll if forced or user is at bottom
    // If `force` is true, we ignore `_userHasScrolledUp`
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

  // --------------------------------------------------------------------------
  // TEXT CHANGES FOR "cd" SUGGESTIONS
  // --------------------------------------------------------------------------
  void _handleTextChanges() async {
    final input = _messageController.text.trim();
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Check if user typed "cd "
    if (input.startsWith("cd ")) {
      final query = input.substring(3).trim();
      if (query.isNotEmpty) {
        // Update suggestions
        await chatProvider.updateFileSuggestions(widget.chatId, query: query);
        setState(() {
          _fileSuggestions =
              chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
        });

        // Filter deeper directory vs top-level
        if (!query.contains("/")) {
          final matches =
              _fileSuggestions.where((file) => file.startsWith(query)).toList();
          setState(() {
            _filteredSuggestions = matches;
            _showTagPopup = _filteredSuggestions.isNotEmpty;
          });
        } else {
          final lastPart = query.split("/").last;
          final matches = _fileSuggestions
              .where((file) => file.startsWith(lastPart))
              .toList();
          setState(() {
            _filteredSuggestions = matches;
            _showTagPopup = _filteredSuggestions.isNotEmpty;
          });
        }
      }
    } else {
      // If user typed something else, close suggestions
      setState(() {
        _filteredSuggestions.clear();
        _showTagPopup = false;
      });
    }
  }

  // --------------------------------------------------------------------------
  // SENDING A MESSAGE
  // --------------------------------------------------------------------------
  Future<void> _sendMessage() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final text = _messageController.text.trim();
    _messageController.clear();
    if (text.isEmpty) return;

    // If a streaming command was active, stop it
    if (chatProvider.isStreaming(widget.chatId)) {
      chatProvider.stopStreaming(widget.chatId);
    }

    // Show local user message
    chatProvider.addMessage(widget.chatId, text, isUser: true);
    _startTypingIndicator();
    // Auto-scroll to show user message
    _scrollToBottom(immediate: true, force: true);

    try {
      // Check if it's a streaming command
      if (chatProvider.isStreamingCommand(text)) {
        // Start streaming
        chatProvider.startStreaming(widget.chatId, text);
      } else {
        // Normal ephemeral command
        final response = await chatProvider.sendCommand(widget.chatId, text);

        // If it's a cd command, refresh suggestions
        if (text.startsWith("cd ")) {
          await chatProvider.updateFileSuggestions(widget.chatId);
          _fileSuggestions =
              chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
        } else {
          _filteredSuggestions.clear();
          _showTagPopup = false;
        }

        _stopTypingIndicator();

        // If the provider returned a non-empty response, show it
        if (response != null && response.isNotEmpty) {
          chatProvider.addMessage(widget.chatId, response, isUser: false);
        }

        // After a small delay, scroll to bottom
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

  // --------------------------------------------------------------------------
  // TYPING INDICATOR
  // --------------------------------------------------------------------------
  void _startTypingIndicator() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final lastMsg = chatProvider.getMessages(widget.chatId).lastOrNull;
    // If last message is a streaming command, skip the "..."
    if (lastMsg != null && chatProvider.isStreamingCommand(lastMsg['text'])) {
      return;
    }
    setState(() => _isTyping = true);
    _scrollToBottom(immediate: true, force: true);
  }

  void _stopTypingIndicator() {
    if (!mounted) return;
    setState(() => _isTyping = false);
  }

// Show directory suggestions popup
  void _showDirectoryDropdown(BuildContext context, GlobalKey key) async {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Update file suggestions
    await chatProvider.updateFileSuggestions(widget.chatId);

    setState(() {
      _fileSuggestions =
          chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
    });

    final RenderBox renderBox =
        key.currentContext!.findRenderObject() as RenderBox;
    final Offset position = renderBox.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + renderBox.size.height + 5,
        position.dx + 150,
        position.dy + renderBox.size.height + 200,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      items: [
        if (chatProvider.canGoBack(widget.chatId))
          PopupMenuItem(
            onTap: () {
              // ✅ Get the correct absolute parent directory
              final previousDir =
                  chatProvider.getParentDirectory(widget.chatId);

              // ✅ Update the stored path first
              chatProvider.goBackDirectory(widget.chatId);

              // ✅ Send the command correctly
              chatProvider.sendCommand(widget.chatId, "cd $previousDir",
                  silent: true);
            },
            child: Row(
              children: [
                Icon(Icons.arrow_back,
                    size: 16,
                    color: isDarkMode ? Colors.white54 : Colors.black54),
                const SizedBox(width: 5),
                Text(
                  "Go Back",
                  style: TextStyle(
                      fontSize: 14,
                      fontFamily: "monospace",
                      color: isDarkMode ? Colors.white : Colors.black54),
                ),
              ],
            ),
          ),
        ..._fileSuggestions.map((dir) {
          return PopupMenuItem(
            onTap: () {
              final chatData = chatProvider.chats[widget.chatId];
              final currentDir = chatData?['currentDirectory'] ?? "/";

              // ✅ Ensure we append directories properly
              String targetPath =
                  dir.startsWith("/") ? dir : "$currentDir/$dir";
              targetPath = targetPath.replaceAll("//", "/");

              setState(() {
                _messageController.text = "cd $targetPath";
              });
            },
            child: Text(
              dir,
              style: TextStyle(
                  fontSize: 14,
                  fontFamily: "monospace",
                  color: isDarkMode ? Colors.white : Colors.black87),
            ),
          );
        }).toList(),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // UI BUILD
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(widget.chatId);
    final chatName = chatProvider.getChatName(widget.chatId);
    final isConnected = chatProvider.isChatActive(widget.chatId);

    return Scaffold(
      // Let the scaffold adjust for the keyboard if you prefer
      resizeToAvoidBottomInset: true,
      backgroundColor: isDarkMode ? const Color(0xFF0D0D0D) : Colors.white,
      appBar: AppBar(
        title: Text(chatName, style: const TextStyle(fontSize: 18)),
        backgroundColor: isDarkMode ? const Color(0xFF0D0D0D) : Colors.white,
        iconTheme:
            IconThemeData(color: isDarkMode ? Colors.white : Colors.black),
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? Icons.check_circle : Icons.cancel,
              color: isConnected ? Colors.green : Colors.grey,
            ),
            onPressed: () {},
          ),
          IconButton(
            key: _directoryButtonKey,
            icon: const Icon(Icons.folder_open),
            onPressed: () =>
                _showDirectoryDropdown(context, _directoryButtonKey),
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
                    // The typing indicator as the last "pseudo-message"
                    if (_isTyping && index == messages.length) {
                      return const _TypingIndicator();
                    }
                    final message = messages[index];
                    final bool isUserMessage = message['isUser'] ?? false;

                    // If this is the last message & streaming, show the loader
                    bool isStreaming =
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
              // The input box at the bottom
              _chatInputBox(),
            ],
          ),

          // Tag popup for "cd" suggestions
          if (_showTagPopup && _filteredSuggestions.isNotEmpty) _tagPopup(),

          // If not at bottom, show a "scroll down" floating button
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

  // --------------------------------------------------------------------------
  // The text input row
  // --------------------------------------------------------------------------
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.white38 : Colors.black26,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                      color: isDarkMode ? Colors.white24 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                      color: isDarkMode ? Colors.white : Colors.black),
                ),
                filled: true,
                fillColor: Colors.transparent,
                prefixIcon: chatProvider.canGoBack(widget.chatId)
                    ? IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        onPressed: () {
                          chatProvider.goBackDirectory(widget.chatId);
                        },
                      )
                    : null,
              ),
              onTap: () {
                // If user taps the input box, we can forcibly scroll to bottom
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

  // --------------------------------------------------------------------------
  // The pop-up for directory suggestions
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // A single message bubble (with streaming or ephemeral state)
  // --------------------------------------------------------------------------
  Widget _buildMessageBubble(String text, bool isUserMessage,
      {bool isStreaming = false, required String chatId, required int index}) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(chatId);

    final chatData = chatProvider.chats[chatId];
    final bool inProgress = (chatData?['inProgress'] == true);
    final isLastMessage = (index == messages.length - 1);

    // ✅ Extract small command part if present
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
            // ✅ Show small command text in a smaller, lighter style
            if (smallCommand.isNotEmpty)
              Text(
                smallCommand,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: "monospace",
                  color: isDarkMode ? Colors.white38 : Colors.black45,
                ),
              ),

            // ✅ Show actual command output (Main Text)
            SelectableText(
              mainText,
              style: TextStyle(
                fontSize: 14,
                fontFamily: "monospace",
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),

            // ✅ Show streaming/in-progress indicator if needed
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

// --------------------------------------------------------------------------
// Messenger-style typing indicator
// --------------------------------------------------------------------------
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
              return Opacity(
                opacity: (_animation.value - (index * 0.2)).clamp(0.3, 1.0),
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
