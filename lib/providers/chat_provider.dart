import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/ssh_service.dart';

Timer? _debounce;

class ChatProvider extends ChangeNotifier {
  Map<String, Map<String, dynamic>> _chats = {};
  String _currentChatId = "";
  bool _isConnected = false;

  String getCurrentPath(String chatId) {
    return _chats[chatId]?['currentDirectory'] ?? "/root";
  }

  void updateCurrentPath(String chatId, String newPath) {
    if (_chats.containsKey(chatId) && _chats[chatId] != null) {
      _chats[chatId]!['currentDirectory'] = newPath;
      notifyListeners();
    }
  }

  Map<String, Map<String, dynamic>> get chats => _chats;

  ChatProvider() {
    loadChatHistory();
  }

  List<Map<String, dynamic>> getMessages(String chatId) {
    return List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);
  }

  String getChatName(String chatId) {
    return _chats[chatId]?['name'] ??
        formatTimestamp(
          _chats[chatId]?['timestamp'] ?? DateTime.now().toIso8601String(),
        );
  }

  String formatTimestamp(String timestamp) {
    DateTime dateTime = DateTime.parse(timestamp);
    return DateFormat('MMM d, yyyy | h:mm a').format(dateTime);
  }

  bool isConnected() => _isConnected;

  // --------------------------------------------------------------------------
  // canGoBack & goBackDirectory
  // --------------------------------------------------------------------------

  void goBackDirectory(String chatId) {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    final ssh = chatData['service'] as SSHService?;
    if (ssh != null) {
      ssh.sendWebSocketCommand("cd .. && pwd"); // ✅ Sends command to bash
    }
  }

  // --------------------------------------------------------------------------
  // START A NEW CHAT
  // --------------------------------------------------------------------------
  Future<String> startNewChat({
    required String chatName,
    String host = "",
    String username = "",
    String password = "",
    bool isGeneralChat = false,
  }) async {
    var uuid = const Uuid();
    String newChatId = isGeneralChat ? "general_${uuid.v4()}" : uuid.v4();
    String timestamp = DateTime.now().toIso8601String();

    _chats[newChatId] = {
      'name': chatName,
      'messages': <Map<String, dynamic>>[],
      'timestamp': timestamp,
      'lastActive': timestamp,
      'host': isGeneralChat ? "" : host,
      'username': isGeneralChat ? "" : username,
      'password': isGeneralChat ? "" : password,
      'passwordSaved': password.isNotEmpty && !isGeneralChat,
      'currentDirectory': isGeneralChat ? "" : "/root",
      'connected': isGeneralChat,
      // Keep one SSHService instance per chat
      'service': isGeneralChat ? null : SSHService(),

      // ADDED CODE: We'll track ephemeral commands
      'inProgress': false,
      // ADDED CODE: We'll store directory suggestions
      'fileSuggestions': <String>[],
    };

    setCurrentChat(newChatId);
    notifyListeners();
    await saveChatHistory();

    if (isGeneralChat) {
      return newChatId;
    }

    final chatData = _chats[newChatId];
    if (chatData == null) {
      addMessage(
        newChatId,
        "❌ Chat data is missing or null",
        isUser: false,
      );
      return newChatId;
    }

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      addMessage(newChatId, "❌ No SSHService found", isUser: false);
      return newChatId;
    }

    try {
      ssh.connectToWebSocket(
        host: host,
        username: username,
        password: password,

        // ADDED CODE: parse directory JSON in _handleServerOutput
        onMessageReceived: (output) {
          _handleServerOutput(newChatId, output);
        },
        onError: (err) {
          addMessage(newChatId, "❌ $err", isUser: false);
          _isConnected = false;
          notifyListeners();
        },
      );

      Future.delayed(const Duration(milliseconds: 300), () {
        ssh.sendWebSocketCommand("uptime");
      });

      chatData['connected'] = true;
      _isConnected = true;
      addMessage(newChatId, "✅ Connected to $host", isUser: false);
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      addMessage(newChatId, "❌ Failed to connect to $host\n$e", isUser: false);
    }

    return newChatId;
  }

  // --------------------------------------------------------------------------
  // SET CURRENT CHAT
  // --------------------------------------------------------------------------
  void setCurrentChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _currentChatId = chatId;
      notifyListeners();
    }
  }

  String getCurrentChatId() => _currentChatId;

  // --------------------------------------------------------------------------
  // DISCONNECT
  // --------------------------------------------------------------------------
  void disconnectChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _chats[chatId]?['connected'] = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  // RECONNECT
  Future<void> reconnectChat(String chatId, String password) async {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      addMessage(chatId, "❌ No SSHService found for reconnect", isUser: false);
      return;
    }

    try {
      ssh.connectToWebSocket(
        host: chatData['host'],
        username: chatData['username'],
        password: password,

        // ADDED CODE: parse directory JSON in _handleServerOutput
        onMessageReceived: (line) {
          _handleServerOutput(chatId, line);
        },
        onError: (err) {
          addMessage(chatId, "❌ $err", isUser: false);
          _isConnected = false;
          notifyListeners();
        },
      );
      chatData['connected'] = true;
      _isConnected = true;
      addMessage(chatId, "✅ Reconnected to ${chatData['host']}", isUser: false);
    } catch (e) {
      _isConnected = false;
      addMessage(chatId, "❌ Failed to reconnect: $e", isUser: false);
    }
  }

  bool isChatActive(String chatId) {
    return _chats.containsKey(chatId) && (_chats[chatId]?['connected'] == true);
  }

  // --------------------------------------------------------------------------
  // UPDATE FILE SUGGESTIONS
  // --------------------------------------------------------------------------
  Future<void> updateFileSuggestions(String chatId, {String? query}) async {
    final chatData = _chats[chatId];
    if (chatData == null || chatData['connected'] != true) return;

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return;

    // Cancel any previous debounce timer
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      String targetDir = chatData['currentDirectory'] ?? "/";

      if (query != null && query.isNotEmpty) {
        if (query.startsWith("/")) {
          // Absolute path case
          targetDir = query;
        } else {
          // Relative path case: Append query to current directory
          targetDir = "$targetDir/$query";
        }
      }

      // Ensure targetDir is valid and remove any double slashes
      targetDir = targetDir.replaceAll("//", "/");

      // Extract only the **last full directory** for listing
      List<String> parts = targetDir.split("/");
      parts.removeWhere((e) => e.isEmpty);

      if (parts.isNotEmpty) {
        targetDir = "/${parts.join("/")}";
        print("📤 Sending LIST_FILES: $targetDir");
        ssh.listFiles(targetDir);
      } else {
        print("⚠️ No valid directory found to list.");
      }
    });
  }

  // --------------------------------------------------------------------------
  // STREAMING CHECKS
  // --------------------------------------------------------------------------
  bool isStreamingCommand(String command) {
    final streamingCommands = ["journalctl --follow", "tail -f", "htop"];
    return streamingCommands.any((cmd) => command.startsWith(cmd));
  }

  bool isStreaming(String chatId) {
    return _chats[chatId]?['isStreaming'] == true;
  }

  void startStreaming(String chatId, String command) {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      addMessage(chatId, "❌ No SSHService for streaming", isUser: false);
      return;
    }

    ssh.stopCurrentProcess();
    chatData['isStreaming'] = true;
    notifyListeners();

    ssh.sendWebSocketCommand(command);
    addMessage(chatId, "📡 Streaming started: $command", isUser: false);
  }

  void stopStreaming(String chatId) {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return;

    ssh.stopCurrentProcess();
    chatData['isStreaming'] = false;
    addMessage(chatId, "❌ Streaming stopped.", isUser: false);
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // SEND COMMAND
  // --------------------------------------------------------------------------
  Future<String?> sendCommand(String chatId, String command,
      {bool silent = false}) async {
    final chatData = _chats[chatId];
    if (chatData == null) return "❌ Chat session not found!";

    // ✅ Only add the command message to the UI if it's not silent
    if (!silent) {
      addMessage(chatId, command, isUser: true);
    }

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      return "❌ No SSHService found!";
    }

    // ✅ Append `&& pwd` to `cd` commands so Bash always responds with the new directory
    if (command.startsWith("cd ")) {
      command = "$command && pwd";
    }

    // ✅ Directly send the command, let Bash handle everything
    ssh.sendWebSocketCommand(command);

    return null; // ✅ Prevent duplicate blank messages
  }

  // --------------------------------------------------------------------------
  // ADD MESSAGE
  // --------------------------------------------------------------------------
  void addMessage(
    String chatId,
    String message, {
    required bool isUser,
    bool isStreaming = false,
  }) {
    if (!_chats.containsKey(chatId)) return;

    final messages =
        List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);

    if (!isStreaming &&
        messages.isNotEmpty &&
        messages.last['text'] == message) {
      return;
    }

    if (isStreaming && !isUser) {
      _chats[chatId]?['messages'].add({
        'text': message,
        'isUser': false,
        'isStreaming': true,
      });
    } else {
      _chats[chatId]?['messages'].add({'text': message, 'isUser': isUser});
    }

    _chats[chatId]?['lastActive'] = DateTime.now().toIso8601String();
    saveChatHistory();
    notifyListeners();
  }

  void deleteChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      final ssh = _chats[chatId]?['service'] as SSHService?;
      ssh?.closeWebSocket();

      _chats.remove(chatId);
      saveChatHistory();
      notifyListeners();
    }
  }

  void deleteAllChats() {
    for (final cid in _chats.keys) {
      final ssh = _chats[cid]?['service'] as SSHService?;
      ssh?.closeWebSocket();
    }
    _chats.clear();
    saveChatHistory();
    notifyListeners();
  }

  Future<void> saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final temp = <String, Map<String, dynamic>>{};
    _chats.forEach((key, value) {
      final copy = Map<String, dynamic>.from(value);
      copy.remove('service'); // remove the SSHService instance
      temp[key] = copy;
    });
    await prefs.setString('chat_history', jsonEncode(temp));
  }

  Future<void> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final storedChats = prefs.getString('chat_history');
    if (storedChats != null) {
      final decoded = jsonDecode(storedChats) as Map<String, dynamic>;
      decoded.forEach((key, val) {
        _chats[key] = Map<String, dynamic>.from(val);
      });
    }
    notifyListeners();
  }

  // ADDED CODE: parse server output for "directories"
  void _handleServerOutput(String chatId, String rawOutput) {
    try {
      final parsed = jsonDecode(rawOutput);
      if (parsed is Map && parsed.containsKey("directories")) {
        _chats[chatId]?['fileSuggestions'] =
            List<String>.from(parsed["directories"]);
        notifyListeners();
        return;
      }
    } catch (_) {
      // Not JSON, process as normal output
    }

    final chatData = _chats[chatId];
    if (chatData == null) return;

    if (chatData.containsKey('lastCommandOutput')) {
      chatData['lastCommandOutput'] += "\n" + rawOutput;
    } else {
      chatData['lastCommandOutput'] = rawOutput;
    }

    // ✅ Delay ensures we group command outputs together before scrolling
    Future.delayed(const Duration(milliseconds: 100), () {
      if (chatData.containsKey('lastCommandOutput')) {
        addMessage(chatId, chatData['lastCommandOutput'], isUser: false);
        chatData.remove('lastCommandOutput'); // Clear after displaying
        notifyListeners(); // ✅ Trigger UI update
      }
    });
  }
}
