import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/ssh_service.dart';

class ChatProvider extends ChangeNotifier {
  Map<String, Map<String, dynamic>> _chats = {};
  String _currentChatId = "";
  bool _isConnected = false;

  // Returns the chat map for a given chatId
  Map<String, dynamic>? getChatById(String chatId) {
    return _chats[chatId];
  }

  // Returns all chatIds
  List<String> getChatIds() {
    return _chats.keys.toList();
  }

  // Returns the current directory for the chat
  String getCurrentPath(String chatId) {
    return _chats[chatId]?['currentDirectory'] ?? "/root";
  }

  // Base64-encodes password
  String encodePassword(String password) {
    return base64.encode(utf8.encode(password));
  }

  // Updates the current path for a chat
  void updateCurrentPath(String chatId, String newPath) {
    if (_chats.containsKey(chatId) && _chats[chatId] != null) {
      _chats[chatId]!['currentDirectory'] = newPath;
      notifyListeners();
    }
  }

  // Returns the entire chats map
  Map<String, Map<String, dynamic>> get chats => _chats;

  // Loads existing chat history on creation
  ChatProvider() {
    loadChatHistory();
  }

  // Returns the messages for a given chat
  List<Map<String, dynamic>> getMessages(String chatId) {
    return List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);
  }

  // Gets the chat name or timestamp if none
  String getChatName(String chatId) {
    return _chats[chatId]?['name'] ??
        formatTimestamp(
            _chats[chatId]?['timestamp'] ?? DateTime.now().toIso8601String());
  }

  // Formats ISO8601 timestamps
  String formatTimestamp(String timestamp) {
    DateTime dateTime = DateTime.parse(timestamp);
    return DateFormat('MMM d, yyyy | h:mm a').format(dateTime);
  }

  // Checks if any chat is connected
  bool isConnected() => _isConnected;

  // Goes up one directory for a given chat
  void goBackDirectory(String chatId) {
    final chatData = _chats[chatId];
    if (chatData == null) return;
    final ssh = chatData['service'] as SSHService?;
    ssh?.sendWebSocketCommand("cd .. && pwd");
  }

  // Starts a new chat or reuses an existing one
  Future<String> startNewChat({
    required String chatName,
    String host = "",
    String username = "",
    String password = "",
    bool isGeneralChat = false,
    bool savePassword = false, // <-- NEW
  }) async {
    // If user did NOT choose to save password, we store a blank password in the chat data.
    // If user DID choose to save, we store the real password.
    final effectivePassword = (!isGeneralChat && savePassword) ? password : "";
    final isPwSaved = (!isGeneralChat && savePassword && password.isNotEmpty);

    if (!isGeneralChat) {
      String? existingChatId = _findExistingSshChat(host, username, chatName);
      if (existingChatId != null) {
        setCurrentChat(existingChatId);
        notifyListeners();
        await saveChatHistory();
        return existingChatId;
      }
    }

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

      // We only store the password in chat data if the user opted to save it
      'password': isGeneralChat ? "" : effectivePassword,
      'passwordSaved': isPwSaved,

      'currentDirectory': isGeneralChat ? "" : "/root",
      'connected': isGeneralChat,
      'service': isGeneralChat ? null : SSHService(),
      'inProgress': false,
      'fileSuggestions': <String>[],
    };

    setCurrentChat(newChatId);
    notifyListeners();
    await saveChatHistory();

    // If general chat, just return
    if (isGeneralChat) {
      return newChatId;
    }

    final chatData = _chats[newChatId];
    if (chatData == null) {
      return "";
    }
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      return "";
    }

    try {
      // We can still use the real password for the SSH connection,
      // even if the user said “don’t save it.” This is ephemeral.
      String encodedPassword = encodePassword(password);
      Completer<String> authCompleter = Completer<String>();

      ssh.connectToWebSocket(
        host: host,
        username: username,
        password: encodedPassword,
        onMessageReceived: (output) {
          if (output.contains("❌ Authentication failed")) {
            authCompleter.complete("FAIL");
          } else if (output.contains("Interactive Bash session started.")) {
            authCompleter.complete("SUCCESS");
          }
          _handleServerOutput(newChatId, output);
        },
        onError: (err) {
          authCompleter.complete("FAIL");
          addMessage(newChatId, "❌ $err", isUser: false);
          _isConnected = false;
          notifyListeners();
        },
      );

      String authResult = await authCompleter.future
          .timeout(const Duration(seconds: 5), onTimeout: () => "TIMEOUT");

      if (authResult != "SUCCESS") {
        _chats.remove(newChatId);
        notifyListeners();
        return "";
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        ssh.sendWebSocketCommand("uptime");
      });
      chatData['connected'] = true;
      _isConnected = true;
      addMessage(newChatId, "✅ Connected to $host", isUser: false);
      notifyListeners();
      return newChatId;
    } catch (e) {
      _chats.remove(newChatId);
      notifyListeners();
      return "";
    }
  }

  // Finds an existing SSH chat by host/username/name
  String? _findExistingSshChat(String host, String username, String chatName) {
    for (final entry in _chats.entries) {
      final map = entry.value;
      if (map['host'] == host &&
          map['username'] == username &&
          map['name'] == chatName) {
        return entry.key;
      }
    }
    return null;
  }

  // Sets the current chatId
  void setCurrentChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _currentChatId = chatId;
      notifyListeners();
    }
  }

  // Gets the current chatId
  String getCurrentChatId() => _currentChatId;

  // Disconnects a given chat
  void disconnectChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _chats[chatId]?['connected'] = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  // Reconnects with the given password
  Future<void> reconnectChat(String chatId, String password) async {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    // If there's no service, create a new one now:
    if (chatData['service'] == null) {
      chatData['service'] = SSHService();
    }

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

  // Checks if a chat is active
  bool isChatActive(String chatId) {
    return _chats.containsKey(chatId) && (_chats[chatId]?['connected'] == true);
  }

  // Updates file suggestions for cd commands
  Future<void> updateFileSuggestions(String chatId, {String? query}) async {
    final chatData = _chats[chatId];
    if (chatData == null || chatData['connected'] != true) return;
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return;
    String targetDir = chatData['currentDirectory'] ?? "/";
    if (query != null && query.isNotEmpty) {
      if (query.startsWith("/")) {
        targetDir = query;
      } else {
        targetDir = "$targetDir/$query";
      }
    }
    targetDir = targetDir.replaceAll("//", "/");
    List<String> parts = targetDir.split("/");
    parts.removeWhere((e) => e.isEmpty);
    if (parts.isNotEmpty) {
      targetDir = "/${parts.join("/")}";
      ssh.listFiles(targetDir);
    }
  }

  // Checks if a command is a streaming command
  bool isStreamingCommand(String command) {
    final streamingCommands = ["journalctl --follow", "tail -f", "htop"];
    return streamingCommands.any((cmd) => command.startsWith(cmd));
  }

  // Checks if a chat is currently streaming
  bool isStreaming(String chatId) {
    return _chats[chatId]?['isStreaming'] == true;
  }

  // Starts streaming for a given chat
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

  // Stops streaming for a given chat
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

  // Sends a command to a given chat
  Future<String?> sendCommand(String chatId, String command,
      {bool silent = false}) async {
    final chatData = _chats[chatId];
    if (chatData == null) return "❌ Chat session not found!";
    if (!silent) {
      addMessage(chatId, command, isUser: true);
    }
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) {
      return "❌ No SSHService found!";
    }
    if (command.startsWith("cd ")) {
      command = "$command && pwd";
    }
    ssh.sendWebSocketCommand(command);
    return null;
  }

  // Adds a message to the given chat
  void addMessage(String chatId, String message,
      {required bool isUser, bool isStreaming = false}) {
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

  // Deletes a single chat
  void deleteChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      final ssh = _chats[chatId]?['service'] as SSHService?;
      ssh?.closeWebSocket();
      _chats.remove(chatId);
      saveChatHistory();
      notifyListeners();
    }
  }

  // Deletes all chats
  void deleteAllChats() {
    for (final cid in _chats.keys) {
      final ssh = _chats[cid]?['service'] as SSHService?;
      ssh?.closeWebSocket();
    }
    _chats.clear();
    saveChatHistory();
    notifyListeners();
  }

  // Saves chat history
  Future<void> saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final temp = <String, Map<String, dynamic>>{};
    _chats.forEach((key, value) {
      final copy = Map<String, dynamic>.from(value);
      copy.remove('service');
      temp[key] = copy;
    });
    await prefs.setString('chat_history', jsonEncode(temp));
  }

  // Loads chat history
  Future<void> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final storedChats = prefs.getString('chat_history');
    if (storedChats != null) {
      final decoded = jsonDecode(storedChats) as Map<String, dynamic>;
      decoded.forEach((key, val) {
        final map = Map<String, dynamic>.from(val);

        // Keep host, username, password, etc. but always mark the chat as disconnected.
        map['connected'] = false;
        map['service'] = null; // ensure no stale service object

        _chats[key] = map;
      });
    }
    notifyListeners();
  }

  // Handles SSH server output
  void _handleServerOutput(String chatId, String rawOutput) {
    final chatData = _chats[chatId];
    if (chatData == null) return;
    try {
      final parsed = jsonDecode(rawOutput);
      if (parsed is Map && parsed.containsKey("directories")) {
        chatData['fileSuggestions'] = List<String>.from(parsed["directories"]);
        notifyListeners();
        return;
      }
    } catch (_) {}
    final lines = rawOutput.split('\n');
    for (final line in lines) {
      if (line.startsWith('/') && !line.contains(' ')) {
        updateCurrentPath(chatId, line.trim());
        updateFileSuggestions(chatId);
      }
    }
    if (chatData.containsKey('lastCommandOutput')) {
      chatData['lastCommandOutput'] += "\n$rawOutput";
    } else {
      chatData['lastCommandOutput'] = rawOutput;
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (chatData.containsKey('lastCommandOutput')) {
        addMessage(chatId, chatData['lastCommandOutput'], isUser: false);
        chatData.remove('lastCommandOutput');
        notifyListeners();
      }
    });
  }
}
