import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../services/ssh_service.dart';

class ChatProvider extends ChangeNotifier {
  Map<String, Map<String, dynamic>> _chats = {};
  String _currentChatId = "";
  bool _isConnected = false;

  Map<String, Map<String, dynamic>> get chats => _chats;

  List<Map<String, dynamic>> getMessages(String chatId) =>
      List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);

  String getChatName(String chatId) =>
      _chats[chatId]?['name'] ??
      formatTimestamp(
          _chats[chatId]?['timestamp'] ?? DateTime.now().toIso8601String());

  ChatProvider() {
    loadChatHistory();
  }

  String formatTimestamp(String timestamp) {
    DateTime dateTime = DateTime.parse(timestamp);
    return DateFormat('MMM d, yyyy | h:mm a').format(dateTime);
  }

  bool isConnected() => _isConnected;

  /// ✅ **Start a new chat & fetch SSH Welcome Message**
  Future<String> startNewChat({
    required String chatName,
    required String host,
    required String username,
    required String password,
  }) async {
    var uuid = const Uuid();
    String newChatId = uuid.v4();
    String timestamp = DateTime.now().toIso8601String();

    _chats[newChatId] = {
      'name': chatName,
      'messages': [],
      'timestamp': timestamp,
      'lastActive': timestamp,
      'host': host,
      'username': username,
      'password': password,
      'passwordSaved': password.isNotEmpty,
      'currentDirectory': "/root",
<<<<<<< HEAD
      'connected': true,
    };

    _currentChatId = newChatId; // ✅ Ensure this is correctly set
=======
      'connected': false, // Initially false until SSH connects
    };

    setCurrentChat(newChatId); // ✅ Set the current chat ID
>>>>>>> ac09413 (Normalize line endings)
    notifyListeners();
    saveChatHistory();

    try {
      String welcomeMessage = await SSHService().getSSHWelcomeMessage(
        host: host,
        username: username,
        password: password,
      );

<<<<<<< HEAD
      _isConnected = true;
      addMessage(newChatId, "✅ Connected to $host", isUser: false);
      return newChatId; // ✅ Return the correct chat ID
    } catch (e) {
      _isConnected = false;
      addMessage(newChatId, "❌ Failed to connect to $host", isUser: false);
      return "";
    }
  }

=======
      _chats[newChatId]?['connected'] = true;
      _isConnected = true;
      addMessage(newChatId, "✅ Connected to $host", isUser: false);
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      addMessage(newChatId, "❌ Failed to connect to $host", isUser: false);
    }

    return newChatId;
  }

  /// ✅ **Set the current active chat**
  void setCurrentChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _currentChatId = chatId;
      notifyListeners();
    }
  }

  /// ✅ **Get the current chat ID**
  String getCurrentChatId() => _currentChatId;

>>>>>>> ac09413 (Normalize line endings)
  /// ✅ **Disconnect SSH Session**
  void disconnectChat(String chatId) {
    if (_chats.containsKey(chatId)) {
      _chats[chatId]?['connected'] = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  /// ✅ **Reconnect to SSH without re-entering details**
  Future<void> reconnectChat(String chatId, String password) async {
    var chatData = _chats[chatId];
    if (chatData == null) return;

    try {
<<<<<<< HEAD
      // ✅ Reconnect using stored SSH details but request password
      await SSHService().getSSHWelcomeMessage(
        host: chatData['host'],
        username: chatData['username'],
        password: password, // ✅ Pass the password dynamically
=======
      await SSHService().getSSHWelcomeMessage(
        host: chatData['host'],
        username: chatData['username'],
        password: password,
>>>>>>> ac09413 (Normalize line endings)
      );

      _chats[chatId]?['connected'] = true;
      _isConnected = true;
      notifyListeners();
      addMessage(chatId, "✅ Reconnected to ${chatData['host']}", isUser: false);
    } catch (e) {
      _isConnected = false;
      addMessage(chatId, "❌ Failed to reconnect: $e", isUser: false);
    }
  }

<<<<<<< HEAD
=======
  /// ✅ **Checks if a chat is active**
  bool isChatActive(String chatId) {
    return _chats.containsKey(chatId) &&
        (_chats[chatId]?['connected'] ?? false);
  }

>>>>>>> ac09413 (Normalize line endings)
  /// ✅ **Handles running commands in the correct directory**
  Future<String> sendCommand(String chatId, String command) async {
    var chatData = _chats[chatId];
    if (chatData == null) return "❌ Chat session not found!";

    addMessage(chatId, command, isUser: true);
    String currentDir = chatData['currentDirectory'] ?? "/root";

    // ✅ **Handle `cd` commands and update directory**
    if (command.startsWith("cd ")) {
      String newDir =
          await _handleDirectoryChange(chatData, command, currentDir);
      if (newDir.isNotEmpty) {
        _chats[chatId]?['currentDirectory'] = newDir;
        saveChatHistory();
        return addMessage(chatId, "📂 Now in: $newDir", isUser: false);
      } else {
        return addMessage(chatId, "❌ Invalid directory", isUser: false);
      }
    }

    // ✅ **Run the command in the current directory**
    String fullCommand = "cd $currentDir && $command";
    try {
      String response = await SSHService().executeCommand(
        host: chatData['host'],
        username: chatData['username'],
        password: chatData['password'],
        command: fullCommand,
      );

      return addMessage(chatId, response.trim(), isUser: false);
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      return addMessage(chatId, "❌ SSH API Error: $e", isUser: false);
    }
  }

<<<<<<< HEAD
  /// ✅ **Handles incremental directory changes**
=======
  /// ✅ **Handles `cd` commands properly**
>>>>>>> ac09413 (Normalize line endings)
  Future<String> _handleDirectoryChange(
      Map<String, dynamic> chatData, String command, String currentDir) async {
    String targetDir = command.replaceFirst("cd ", "").trim();

    if (targetDir == "..") {
      return await _getParentDirectory(chatData);
    }

    if (targetDir.startsWith("/")) {
      return await _validateDirectory(chatData, targetDir);
    }

    String newDir = "$currentDir/$targetDir";
    return await _validateDirectory(chatData, newDir);
  }

  /// ✅ **Validates a directory before changing**
  Future<String> _validateDirectory(
      Map<String, dynamic> chatData, String dir) async {
    try {
      String result = await SSHService().executeCommand(
        host: chatData['host'],
        username: chatData['username'],
        password: chatData['password'],
        command: "cd $dir && pwd",
      );

      if (result.isNotEmpty && !result.contains("No such file or directory")) {
        return result.trim();
      }
    } catch (e) {
      return "";
    }

    return "";
  }

  /// ✅ **Handles `cd ..` correctly**
  Future<String> _getParentDirectory(Map<String, dynamic> chatData) async {
    String currentDir = chatData['currentDirectory'] ?? "/root";

    if (currentDir == "/") {
      return "/";
    }

    List<String> parts = currentDir.split("/");
    parts.removeLast();
    String parentDir = parts.join("/") == "" ? "/" : parts.join("/");

    return await _validateDirectory(chatData, parentDir);
  }

  /// ✅ **Prevents duplicate messages**
  String addMessage(String chatId, String message, {required bool isUser}) {
    if (!_chats.containsKey(chatId)) return message;

    List<Map<String, dynamic>> messages =
        List<Map<String, dynamic>>.from(_chats[chatId]?['messages'] ?? []);

    if (messages.isNotEmpty && messages.last['text'] == message) {
      return message;
    }

    _chats[chatId]?['messages'].add({'text': message, 'isUser': isUser});
    _chats[chatId]?['lastActive'] = DateTime.now().toIso8601String();
    saveChatHistory();
    notifyListeners();
    return message;
  }

  /// ✅ **Delete a chat**
  void deleteChat(String chatId) {
<<<<<<< HEAD
    _chats.remove(chatId);
    saveChatHistory();
    notifyListeners();
=======
    if (_chats.containsKey(chatId)) {
      _chats.remove(chatId);
      saveChatHistory();
      notifyListeners();
    }
>>>>>>> ac09413 (Normalize line endings)
  }

  /// ✅ **Delete all chats**
  void deleteAllChats() {
    _chats.clear();
    saveChatHistory();
    notifyListeners();
  }

  /// ✅ **Save chat history**
  Future<void> saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('chat_history', jsonEncode(_chats));
  }

  /// ✅ **Load chat history**
  Future<void> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedChats = prefs.getString('chat_history');

    if (storedChats != null) {
      _chats = Map<String, Map<String, dynamic>>.from(jsonDecode(storedChats));
    }
    notifyListeners();
  }
<<<<<<< HEAD

  /// ✅ **Rename a chat**
  void renameChat(String chatId, String newName) {
    if (_chats.containsKey(chatId)) {
      _chats[chatId]?['name'] = newName;
      saveChatHistory();
      notifyListeners();
    }
  }

  /// ✅ **Check if chat is active**
  bool isChatActive(String chatId) {
    return _chats.containsKey(chatId) &&
        (_chats[chatId]?['connected'] ?? false);
  }
=======
>>>>>>> ac09413 (Normalize line endings)
}
