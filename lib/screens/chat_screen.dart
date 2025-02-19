import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import '../providers/theme_provider.dart';
import '../services/ssh_service.dart';

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

  void _updateStreamingMessages() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.addListener(_updateStreamingMessages);

    _messageController.addListener(() async {
      String input = _messageController.text.trim();

      if (input.startsWith("cd ")) {
        String query = input.substring(3).trim();

        if (query.isNotEmpty) {
          await Provider.of<ChatProvider>(context, listen: false)
              .updateFileSuggestions(widget.chatId, query: query);

          setState(() {
            // Re-fetch the new suggestions from the updated chat data
            _fileSuggestions = Provider.of<ChatProvider>(context, listen: false)
                    .chats[widget.chatId]?['fileSuggestions'] ??
                [];
          });

          if (!query.contains("/")) {
            // Filter from the top-level suggestions
            List<String> matches = _fileSuggestions
                .where((file) => file.startsWith(query))
                .toList();

            setState(() {
              _filteredSuggestions = matches;
              _showTagPopup = _filteredSuggestions.isNotEmpty;
            });
          } else {
            // If user typed "/", filter from deeper directory
            String lastPart = query.split("/").last;
            List<String> matches = _fileSuggestions
                .where((file) => file.startsWith(lastPart))
                .toList();

            setState(() {
              _filteredSuggestions = matches;
              _showTagPopup = _filteredSuggestions.isNotEmpty;
            });
          }
        }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: immediate
              ? const Duration(
                  milliseconds: 100) // fast scroll for sent messages
              : const Duration(
                  milliseconds: 300), // smooth scroll for responses
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startTypingIndicator() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final lastMessage = chatProvider.getMessages(widget.chatId).lastOrNull;

    // Don't show "..." if it's a streaming command
    if (lastMessage != null &&
        chatProvider.isStreamingCommand(lastMessage['text'])) {
      return;
    }

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

    // Stop existing streaming if a new command is sent
    if (chatProvider.isStreaming(widget.chatId)) {
      chatProvider.stopStreaming(widget.chatId);
    }

    chatProvider.addMessage(widget.chatId, message, isUser: true);
    _startTypingIndicator();
    _scrollToBottom(immediate: true);

    try {
      // If the command is a "streaming" command
      if (chatProvider.isStreamingCommand(message)) {
        chatProvider.startStreaming(widget.chatId, message);
      } else {
        // normal ephemeral command
        String response =
            await chatProvider.sendCommand(widget.chatId, message);

        setState(() {
          // If "cd" command, update suggestions; otherwise, clear popup
          if (message.startsWith("cd ")) {
            chatProvider.updateFileSuggestions(widget.chatId);
            _fileSuggestions =
                chatProvider.chats[widget.chatId]?['fileSuggestions'] ?? [];
          } else {
            _filteredSuggestions.clear();
            _showTagPopup = false;
          }
        });

        _stopTypingIndicator();
        chatProvider.addMessage(widget.chatId, response, isUser: false);
      }

      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } catch (e) {
      _stopTypingIndicator();
      chatProvider.addMessage(widget.chatId, "❌ SSH Error: $e", isUser: false);
      _scrollToBottom();
    }
  }

  void _showDirectoryDropdown(BuildContext context, GlobalKey key) async {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

    await Provider.of<ChatProvider>(context, listen: false)
        .updateFileSuggestions(widget.chatId);

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
        position.dx,
        position.dy + renderBox.size.height + 5,
        position.dx + 150,
        position.dy + renderBox.size.height + 200,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      items: [
        if (Provider.of<ChatProvider>(context, listen: false)
            .canGoBack(widget.chatId))
          PopupMenuItem(
            onTap: () {
              Provider.of<ChatProvider>(context, listen: false)
                  .goBackDirectory(widget.chatId);
              setState(() {
                _messageController.text = "cd ..";
              });
              _sendMessage();
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
                    color: isDarkMode ? Colors.white : Colors.black54,
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
              style: TextStyle(
                fontSize: 14,
                fontFamily: "monospace",
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          );
        }).toList(),
      ],
    );
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

                    // If this is the last message and it's streaming, mark it
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
              _chatInputBox(),
            ],
          ),

          // Auto-suggestion Popup
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
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
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
                prefixIcon: Provider.of<ChatProvider>(context, listen: true)
                        .canGoBack(widget.chatId)
                    ? IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        onPressed: () {
                          Provider.of<ChatProvider>(context, listen: false)
                              .goBackDirectory(widget.chatId);
                          setState(() {
                            _messageController.text = "cd ..";
                          });
                          _sendMessage();
                        },
                      )
                    : null,
              ),
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

  Widget _tagPopup() {
    if (_filteredSuggestions.isEmpty) return const SizedBox.shrink();

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
                    setState(() {
                      String selectedDir = dir;
                      String currentText = _messageController.text.trim();

                      if (currentText.startsWith("cd ")) {
                        List<String> parts = currentText.split(" ");
                        if (parts.length > 1) {
                          List<String> pathParts = parts[1].split("/");
                          pathParts.removeLast();
                          pathParts.add(selectedDir);
                          _messageController.text = "cd " + pathParts.join("/");
                        } else {
                          _messageController.text = "cd $selectedDir";
                        }
                      } else {
                        _messageController.text = "cd $selectedDir";
                      }

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

  Widget _buildMessageBubble(String text, bool isUserMessage,
      {bool isStreaming = false, required String chatId, required int index}) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(chatId);

    // ADDED CODE: check ephemeral inProgress
    final chatData = chatProvider.chats[chatId];
    final bool inProgress = (chatData?['inProgress'] == true);

    final isLastMessage = (index == messages.length - 1);

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
            SelectableText(
              text,
              style: TextStyle(
                fontSize: 14,
                fontFamily: "monospace",
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),

            // ADDED CODE: unify ephemeral "inProgress" + streaming in the last message
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
                          // ephemeral => forcibly stop
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
                          if (mounted) {
                            setState(() {});
                          }
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
