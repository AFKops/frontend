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

// Fetch the WebSocket URL from SharedPreferences or a global provider
  Future<String> _getWebSocketUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("wsUrl") ??
        "ws://afkops.com/ssh-stream"; // Default URL if none is saved
  }

  Map<String, dynamic>? getChatById(String chatId) {
    return _chats[chatId];
  }

  List<String> getChatIds() {
    return _chats.keys.toList();
  }

  String getCurrentPath(String chatId) {
    return _chats[chatId]?['currentDirectory'] ?? "/root";
  }

  // Existing function (unused for key-based approach)
  String encodePassword(String password) {
    return base64.encode(utf8.encode(password));
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

  void goBackDirectory(String chatId) {
    final chatData = _chats[chatId];
    if (chatData == null) return;
    final ssh = chatData['service'] as SSHService?;
    ssh?.sendWebSocketCommand("cd .. && pwd");
  }

  /// Creates or reuses a chat (SSH or general)
  /// mode can be "PASSWORD" or "KEY"
  Future<String> startNewChat({
    required String chatName,
    String host = "",
    String username = "",
    String password = "",
    bool isGeneralChat = false,
    bool savePassword = false,
    String mode = "PASSWORD", // NEW for key-based mode (default=PASSWORD)
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

    // Initialize the service (SSHService) with the WebSocket URL fetched dynamically
    String wsUrl = await _getWebSocketUrl(); // Fetch the WebSocket URL
    SSHService? service = isGeneralChat
        ? null
        : SSHService(wsUrl: wsUrl); // Create SSHService with wsUrl

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
      'service': service, // Set the service here
      'inProgress': false,
      'fileSuggestions': <String>[],
      'customCommands': <String>[],
      'mode': mode, // Store the auth mode in the chat data
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
      Completer<String> authCompleter = Completer<String>();

      // If mode == "KEY", we pass password as "privateKey"
      // If mode == "PASSWORD", we pass password normally.
      if (mode == "KEY") {
        ssh.connectToWebSocket(
          host: host,
          username: username,
          password: "", // we skip password param if we're using KEY
          privateKey: password, // store the actual password field as key now
          mode: "KEY",
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
      } else {
        ssh.connectToWebSocket(
          host: host,
          username: username,
          password: password,
          privateKey: "", // empty, not used in password mode
          mode: "PASSWORD",
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
      }

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

  void setCurrentChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _currentChatId = chatId;
      notifyListeners();
    }
  }

  String getCurrentChatId() => _currentChatId;

  void disconnectChat(String chatId) {
    final chat = chats[chatId];
    if (chat != null && chat['service'] is SSHService) {
      final ssh = chat['service'] as SSHService;
      ssh.closeWebSocket(); // Properly close WS connection
      chat['service'] = null;
      chat['connected'] = false;
    }
    notifyListeners();
  }

  /// Reconnect with given password or key, depending on mode stored in chat data
  Future<void> reconnectChat(String chatId, String password) async {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    if (chatData['service'] == null) {
      // Get the WebSocket URL
      String wsUrl = await _getWebSocketUrl();
      chatData['service'] = SSHService(wsUrl: wsUrl);
    }
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return;

    final mode = (chatData['mode'] ?? "PASSWORD") as String;
    final host = chatData['host'] ?? "";
    final user = chatData['username'] ?? "";

    try {
      Completer<String> authCompleter = Completer<String>();

      if (mode == "KEY") {
        ssh.connectToWebSocket(
          host: host,
          username: user,
          password: "", // not used in KEY mode
          privateKey: password,
          mode: "KEY",
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
      } else {
        ssh.connectToWebSocket(
          host: host,
          username: user,
          password: password,
          privateKey: "",
          mode: "PASSWORD",
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
      }

      String authResult = await authCompleter.future
          .timeout(const Duration(seconds: 5), onTimeout: () => "TIMEOUT");

      if (authResult == "SUCCESS") {
        chatData['connected'] = true;
        _isConnected = true;
        addMessage(chatId, "✅ Reconnected to $host", isUser: false);
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

  Future<bool> reconnectAndCheck(String chatId, String password) async {
    final chatData = _chats[chatId];
    if (chatData == null) return false;

    if (chatData['service'] == null) {
      // Get the WebSocket URL
      String wsUrl = await _getWebSocketUrl();
      chatData['service'] = SSHService(wsUrl: wsUrl);
    }
    final ssh = chatData['service'] as SSHService?;
    if (ssh == null) return false;

    final mode = (chatData['mode'] ?? "PASSWORD") as String;
    final host = chatData['host'] ?? "";
    final user = chatData['username'] ?? "";

    try {
      Completer<String> authCompleter = Completer<String>();

      if (mode == "KEY") {
        ssh.connectToWebSocket(
          host: host,
          username: user,
          password: "", // not used in KEY mode
          privateKey: password,
          mode: "KEY",
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
      } else {
        ssh.connectToWebSocket(
          host: host,
          username: user,
          password: password,
          privateKey: "",
          mode: "PASSWORD",
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
      }

      String authResult = await authCompleter.future
          .timeout(const Duration(seconds: 5), onTimeout: () => "TIMEOUT");

      if (authResult == "SUCCESS") {
        chatData['connected'] = true;
        _isConnected = true;
        addMessage(chatId, "✅ Reconnected to $host", isUser: false);
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

  bool isChatActive(String chatId) {
    return _chats.containsKey(chatId) && (_chats[chatId]?['connected'] == true);
  }

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

  void addMessage(
    String chatId,
    String message, {
    required bool isUser,
    bool isStreaming = false,
    bool isSystem = false,
  }) {
    if (!_chats.containsKey(chatId)) return;
    final messages =
        List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);

    if (!isStreaming &&
        messages.isNotEmpty &&
        messages.last['text'] == message) {
      return;
    }

    _chats[chatId]?['messages'].add({
      'text': message,
      'isUser': isUser,
      'isStreaming': isStreaming,
      'isSystem': isSystem,
    });

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
      copy.remove('service');
      temp[key] = copy;
    });
    await prefs.setString('chat_history', jsonEncode(temp));
  }

  List<String> getSavedCommands(String chatId) {
    return List<String>.from(_chats[chatId]?['customCommands'] ?? []);
  }

  Future<void> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final storedChats = prefs.getString('chat_history');
    if (storedChats != null) {
      final decoded = jsonDecode(storedChats) as Map<String, dynamic>;
      decoded.forEach((key, val) {
        final map = Map<String, dynamic>.from(val);
        map['connected'] = false;
        map['service'] = null;
        if (map.containsKey('customCommands')) {
          map['customCommands'] =
              List<String>.from(map['customCommands'] ?? []);
        } else {
          map['customCommands'] = <String>[];
        }
        map['notepadText'] = map['notepadText'] ?? "";
        _chats[key] = map;
      });
    }
    notifyListeners();
  }

  void _handleServerOutput(String chatId, String rawOutput) {
    final chatData = _chats[chatId];
    if (chatData == null) return;

    try {
      final parsed = jsonDecode(rawOutput);
      if (parsed is Map<String, dynamic> && parsed.containsKey("directories")) {
        final dirs = parsed["directories"];
        if (dirs is List) {
          chatData['fileSuggestions'] = dirs.map((item) {
            if (item is String) {
              return item;
            } else if (item is Map<String, dynamic> &&
                item.containsKey('name')) {
              return item['name'].toString();
            } else {
              return item.toString();
            }
          }).toList();
          notifyListeners();
        }
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
