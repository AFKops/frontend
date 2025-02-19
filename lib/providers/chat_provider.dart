import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../services/ssh_service.dart';

class ChatProvider extends ChangeNotifier {
  Map<String, Map<String, dynamic>> _chats = {};
  String _currentChatId = "";
  bool _isConnected = false;

  /// For streaming “tail -f”, “journalctl --follow” etc.
  /// (Kept for reference if you specifically want separate channels, but now
  /// we rely on the single SSHService within each chat record.)
  // Map<String, WebSocketChannel?> _streamingSockets = {};

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

  /// --------------------------------------------------------------------------
  /// canGoBack & goBackDirectory
  /// --------------------------------------------------------------------------
  /// Replicates your old logic: user can only “go back” if not in root directory.
  /// Then we set the parent directory. (UI calls "cd .." automatically afterward.)
  bool canGoBack(String chatId) {
    final chatData = _chats[chatId];
    if (chatData == null) return false;

    final currentPath = chatData['currentDirectory'] ?? "/";
    // Only go back if not "/"
    return currentPath != "/";
  }

  void goBackDirectory(String chatId) {
    if (!canGoBack(chatId)) return;
    final chatData = _chats[chatId];
    if (chatData == null) return;

    final currentPath = chatData['currentDirectory'] ?? "/";
    final lastSlashIndex = currentPath.lastIndexOf('/');
    if (lastSlashIndex <= 0) {
      // If there's no deeper slash, set to root
      chatData['currentDirectory'] = "/";
    } else {
      // Take the substring up to the last slash
      chatData['currentDirectory'] = currentPath.substring(0, lastSlashIndex);
    }
    notifyListeners();
  }

  /// --------------------------------------------------------------------------
  /// START A NEW CHAT
  /// --------------------------------------------------------------------------
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
    };

    setCurrentChat(newChatId);
    notifyListeners();
    await saveChatHistory();

    // If it's a general (non-SSH) chat, nothing else to do
    if (isGeneralChat) {
      return newChatId;
    }

    // Retrieve the newly created chat data
    final chatData = _chats[newChatId];

    // Null check in case something unexpected happened
    if (chatData == null) {
      addMessage(
        newChatId,
        "❌ Chat data is missing or null",
        isUser: false,
      );
      return newChatId;
    }

    // Get the SSHService instance
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      addMessage(newChatId, "❌ No SSHService found", isUser: false);
      return newChatId;
    }

    try {
      // 1) Connect to the WebSocket
      ssh.connectToWebSocket(
        host: host,
        username: username,
        password: password,
        onMessageReceived: (output) {
          // Any output lines from the server
          addMessage(newChatId, output, isUser: false);
        },
        onError: (err) {
          addMessage(newChatId, "❌ $err", isUser: false);
          _isConnected = false;
          notifyListeners();
        },
      );

      // 2) Optionally run "uptime" or any quick test command
      Future.delayed(const Duration(milliseconds: 300), () {
        ssh.sendWebSocketCommand("uptime");
      });

      // 3) Mark as connected in our local state
      chatData['connected'] = true;
      _isConnected = true;
      addMessage(newChatId, "✅ Connected to $host", isUser: false);
      notifyListeners();
    } catch (e) {
      // If something went wrong during connect
      _isConnected = false;
      addMessage(newChatId, "❌ Failed to connect to $host\n$e", isUser: false);
    }

    return newChatId;
  }

  /// --------------------------------------------------------------------------
  /// SET CURRENT CHAT
  /// --------------------------------------------------------------------------
  void setCurrentChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _currentChatId = chatId;
      notifyListeners();
    }
  }

  String getCurrentChatId() => _currentChatId;

  /// --------------------------------------------------------------------------
  /// DISCONNECT
  /// --------------------------------------------------------------------------
  void disconnectChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _chats[chatId]?['connected'] = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  /// RECONNECT
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
        onMessageReceived: (line) {
          addMessage(chatId, line, isUser: false);
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

  /// --------------------------------------------------------------------------
  /// UPDATE FILE SUGGESTIONS
  /// --------------------------------------------------------------------------
  Future<void> updateFileSuggestions(String chatId, {String? query}) async {
    final chatData = _chats[chatId];
    if (chatData == null || chatData['connected'] != true) return;

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return;

    final currentDir = chatData['currentDirectory'] ?? "/root";
    String directoryToQuery = currentDir;

    if (query != null && query.isNotEmpty) {
      final parts = query.split("/");
      if (parts.length == 1) {
        directoryToQuery = currentDir;
      } else {
        final partialPath = parts.sublist(0, parts.length - 1).join("/");
        directoryToQuery = "$currentDir/$partialPath";
      }
    }

    // We'll call listFiles; the response arrives in onMessageReceived
    ssh.listFiles(directoryToQuery);
  }

  /// --------------------------------------------------------------------------
  /// STREAMING CHECKS
  /// --------------------------------------------------------------------------
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

    // Optionally stop an old stream first
    ssh.stopCurrentProcess();
    chatData['isStreaming'] = true;
    notifyListeners();

    // Start the new streaming command
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

  /// --------------------------------------------------------------------------
  /// SEND COMMAND
  /// --------------------------------------------------------------------------
  Future<String> sendCommand(String chatId, String command) async {
    final chatData = _chats[chatId];
    if (chatData == null) return "❌ Chat session not found!";

    addMessage(chatId, command, isUser: true);
    final currentDir = chatData['currentDirectory'] ?? "/root";

    // handle cd
    if (command.startsWith("cd ")) {
      final newDir = await _handleDirectoryChange(chatId, command, currentDir);
      if (newDir.isNotEmpty) {
        chatData['currentDirectory'] = newDir;
        addMessage(chatId, "📂 Now in: $newDir", isUser: false);
        await saveChatHistory();
        return "📂 Now in: $newDir";
      } else {
        addMessage(chatId, "❌ Invalid directory", isUser: false);
        return "❌ Invalid directory";
      }
    }

    // streaming
    if (isStreamingCommand(command)) {
      startStreaming(chatId, command);
      return "📡 Streaming started...";
    }

    // normal
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      final err = "❌ No SSHService found. Cannot run command.";
      addMessage(chatId, err, isUser: false);
      return err;
    }

    final fullCmd = "cd $currentDir && $command";
    ssh.sendWebSocketCommand(fullCmd);
    // The lines come in onMessageReceived
    return "✔ Command sent: $fullCmd";
  }

  Future<String> _handleDirectoryChange(
      String chatId, String command, String currentDir) async {
    final targetDir = command.replaceFirst("cd ", "").trim();
    if (targetDir == "..") {
      return _getParentDirectory(chatId);
    }
    if (targetDir.startsWith("/")) {
      return _validateDirectory(chatId, targetDir);
    }
    final newDir = "$currentDir/$targetDir";
    return _validateDirectory(chatId, newDir);
  }

  Future<String> _validateDirectory(String chatId, String dir) async {
    // send "cd $dir && pwd" via WebSocket
    final chatData = _chats[chatId];
    if (chatData == null) return "";

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return "";

    ssh.sendWebSocketCommand("cd $dir && pwd");
    // We'll do a naive 0.5s wait
    await Future.delayed(const Duration(milliseconds: 500));
    return dir;
  }

  Future<String> _getParentDirectory(String chatId) async {
    final chatData = _chats[chatId];
    if (chatData == null) return "/";

    final currentDir = chatData['currentDirectory'] ?? "/root";
    if (currentDir == "/") {
      return "/";
    }
    final slashIdx = currentDir.lastIndexOf('/');
    if (slashIdx <= 0) {
      return "/";
    }
    return currentDir.substring(0, slashIdx);
  }

  /// --------------------------------------------------------------------------
  /// ADD MESSAGE
  /// --------------------------------------------------------------------------
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
}
