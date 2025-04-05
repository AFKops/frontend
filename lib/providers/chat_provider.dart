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
  /// Creates or reuses a chat, handles SSH connection and authentication
  Future<String> startNewChat({
    required String chatName,
    String host = "",
    String username = "",
    String password = "",
    bool isGeneralChat = false,
    bool savePassword = false,
  }) async {
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
      'password': isGeneralChat ? "" : effectivePassword,
      'passwordSaved': isPwSaved,
      'currentDirectory': isGeneralChat ? "" : "/root",
      'connected': isGeneralChat,
      'service': isGeneralChat ? null : SSHService(),
      'inProgress': false,
      'fileSuggestions': <String>[],
      'customCommands': <String>[],
    };

    setCurrentChat(newChatId);
    notifyListeners();
    await saveChatHistory();

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
        addMessage(newChatId, "❌ Authentication failed", isUser: false);
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
      _isConnected = _chats.values.any((chat) => chat['connected'] == true);
      notifyListeners();
    }
  }

  // Reconnects with the given password
  Future<void> reconnectChat(String chatId, String password) async {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    if (chatData['service'] == null) {
      chatData['service'] = SSHService();
    }

    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return;

    try {
      Completer<String> authCompleter = Completer<String>();

      ssh.connectToWebSocket(
        host: chatData['host'],
        username: chatData['username'],
        password: password,
        onMessageReceived: (line) {
          if (line.contains("❌ Authentication failed")) {
            authCompleter.complete("FAIL");
          } else if (line.contains("Interactive Bash session started.")) {
            authCompleter.complete("SUCCESS");
          }
          _handleServerOutput(chatId, line);
        },
        onError: (err) {
          authCompleter.complete("FAIL");
          disconnectChat(chatId);
          addMessage(chatId, "❌ $err", isUser: false);
        },
        onDisconnected: () {
          disconnectChat(chatId);
          addMessage(chatId, "🔌 Disconnected from server", isUser: false);
        },
      );

      String authResult = await authCompleter.future
          .timeout(const Duration(seconds: 5), onTimeout: () => "TIMEOUT");

      if (authResult == "SUCCESS") {
        chatData['connected'] = true;
        _isConnected = true;
        addMessage(chatId, "✅ Reconnected to ${chatData['host']}",
            isUser: false);
      } else {
        disconnectChat(chatId);
        addMessage(chatId, "❌ Authentication failed", isUser: false);
      }

      notifyListeners();
    } catch (e) {
      disconnectChat(chatId);
      addMessage(chatId, "❌ Reconnect error: $e", isUser: false);
    }
  }

  /// Reconnects and returns true if auth succeeded, otherwise false
  Future<bool> reconnectAndCheck(String chatId, String password) async {
    final chatData = _chats[chatId];
    if (chatData == null) return false;

    if (chatData['service'] == null) {
      chatData['service'] = SSHService();
    }
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return false;

    try {
      Completer<String> authCompleter = Completer<String>();
      ssh.connectToWebSocket(
        host: chatData['host'],
        username: chatData['username'],
        password: password,
        onMessageReceived: (line) {
          if (line.contains("❌ Authentication failed")) {
            authCompleter.complete("FAIL");
          } else if (line.contains("Interactive Bash session started.")) {
            authCompleter.complete("SUCCESS");
          }
          _handleServerOutput(chatId, line);
        },
        onError: (err) {
          authCompleter.complete("FAIL");
          addMessage(chatId, "❌ $err", isUser: false);
          _isConnected = false;
          notifyListeners();
        },
      );

      String authResult = await authCompleter.future
          .timeout(const Duration(seconds: 5), onTimeout: () => "TIMEOUT");

      if (authResult == "SUCCESS") {
        chatData['connected'] = true;
        _isConnected = true;
        addMessage(chatId, "✅ Reconnected to ${chatData['host']}",
            isUser: false);
        notifyListeners();
        return true;
      } else {
        chatData['connected'] = false;
        _isConnected = false;
        addMessage(chatId, "❌ Authentication failed", isUser: false);
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isConnected = false;
      chatData['connected'] = false;
      addMessage(chatId, "❌ Failed to reconnect: $e", isUser: false);
      return false;
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
      // Call the new listFiles:
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
  void addMessage(
    String chatId,
    String message, {
    required bool isUser,
    bool isStreaming = false,
    bool isSystem = false, // <-- NEW
  }) {
    if (!_chats.containsKey(chatId)) return;
    final messages =
        List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);

    // Prevent duplicates
    if (!isStreaming &&
        messages.isNotEmpty &&
        messages.last['text'] == message) {
      return;
    }

    // Add the message
    _chats[chatId]?['messages'].add({
      'text': message,
      'isUser': isUser,
      'isStreaming': isStreaming,
      'isSystem': isSystem, // <-- store it
    });

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

  List<String> getSavedCommands(String chatId) {
    return List<String>.from(_chats[chatId]?['customCommands'] ?? []);
  }

  // Loads chat history
  Future<void> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final storedChats = prefs.getString('chat_history');
    if (storedChats != null) {
      final decoded = jsonDecode(storedChats) as Map<String, dynamic>;
      decoded.forEach((key, val) {
        final map = Map<String, dynamic>.from(val);

        // Always reset connection state on app start
        map['connected'] = false;
        map['service'] = null;

        // Ensure customCommands is present as a List<String>
        if (map.containsKey('customCommands')) {
          map['customCommands'] =
              List<String>.from(map['customCommands'] ?? []);
        } else {
          map['customCommands'] = <String>[];
        }

        // ✅ Ensure notepadText field exists
        map['notepadText'] = map['notepadText'] ?? "";

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

      // If the server sent something like {"directories": [...]}:
      if (parsed is Map<String, dynamic> && parsed.containsKey("directories")) {
        final dirs = parsed["directories"];
        if (dirs is List) {
          // Convert each item to a string
          chatData['fileSuggestions'] = dirs.map((item) {
            // 1) If it's already a string, just use it
            if (item is String) {
              return item;

              // 2) If it's a map with 'name', use that
            } else if (item is Map<String, dynamic> &&
                item.containsKey('name')) {
              return item['name'].toString();

              // 3) Otherwise, fallback
            } else {
              return item.toString();
            }
          }).toList();

          notifyListeners();
        }
        return; // Don’t fall through to the plain-text logic if we found directories
      }
    } catch (_) {
      // If it’s not valid JSON or parsing fails, handle as plain text below.
    }

    // -------------------------------------------------------
    // Continue handling normal (non-JSON) server output...
    // -------------------------------------------------------
    final lines = rawOutput.split('\n');
    for (final line in lines) {
      // If a line looks like an absolute path with no spaces, assume it's the new directory:
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

  void addSavedCommand(String chatId, String cmd) {
    if (!_chats.containsKey(chatId)) return;
    final list = List<String>.from(_chats[chatId]?['customCommands'] ?? []);
    if (!list.contains(cmd)) {
      list.add(cmd);
      _chats[chatId]!['customCommands'] = list;
      notifyListeners();
      saveChatHistory();
    }
  }

  void removeSavedCommand(String chatId, String cmd) {
    if (!_chats.containsKey(chatId)) return;
    final list = List<String>.from(_chats[chatId]?['customCommands'] ?? []);
    list.remove(cmd);
    _chats[chatId]!['customCommands'] = list;
    notifyListeners();
    saveChatHistory();
  }

  void updateNotepadText(String chatId, String text) {
    if (!_chats.containsKey(chatId)) return;
    _chats[chatId]!['notepadText'] = text;
    saveChatHistory();
    notifyListeners();
  }
}
