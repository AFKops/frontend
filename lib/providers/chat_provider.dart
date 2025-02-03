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

  /// ✅ Checks if the user can go back one directory
  /// ✅ Checks if the user can go back one directory
  bool canGoBack(String chatId) {
    if (!chats.containsKey(chatId)) return false; // ✅ Prevents errors

    String currentPath = chats[chatId]?['currentDirectory'] ?? "/";
    return currentPath != "/"; // ✅ Can go back if not root
  }

  /// ✅ Moves up one directory level
  void goBackDirectory(String chatId) {
    if (!canGoBack(chatId)) return; // ✅ Prevent errors if at root

    if (chats[chatId] == null) return; // ✅ Prevent null access

    String currentPath = chats[chatId]?['currentPath'] ?? "";
    String parentPath = currentPath.contains('/')
        ? currentPath.substring(0, currentPath.lastIndexOf('/'))
        : "/";

    chats[chatId]?['currentPath'] = parentPath; // ✅ Safely update the path
    notifyListeners(); // ✅ Updates UI
  }

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
    String host = "", // ✅ Optional for general chats
    String username = "", // ✅ Optional for general chats
    String password = "", // ✅ Optional for general chats
    bool isGeneralChat = false, // ✅ New flag for general chat
  }) async {
    var uuid = const Uuid();
    String newChatId = isGeneralChat ? "general_${uuid.v4()}" : uuid.v4();
    String timestamp = DateTime.now().toIso8601String();

    _chats[newChatId] = {
      'name': chatName,
      'messages': [],
      'timestamp': timestamp,
      'lastActive': timestamp,
      'host': isGeneralChat ? "" : host, // ✅ Only set if SSH chat
      'username': isGeneralChat ? "" : username, // ✅ Only set if SSH chat
      'password': isGeneralChat ? "" : password, // ✅ Only set if SSH chat
      'passwordSaved':
          password.isNotEmpty && !isGeneralChat, // ✅ Passwords only for SSH
      'currentDirectory':
          isGeneralChat ? "" : "/root", // ✅ No directory for general chat
      'connected': isGeneralChat, // ✅ General chats are always "connected"
    };

    setCurrentChat(newChatId); // ✅ Set current chat
    notifyListeners();
    saveChatHistory();

    // ✅ If it's a general chat, return immediately
    if (isGeneralChat) return newChatId;

    // ✅ Otherwise, attempt SSH connection
    try {
      String welcomeMessage = await SSHService().getSSHWelcomeMessage(
        host: host,
        username: username,
        password: password,
      );

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
      await SSHService().getSSHWelcomeMessage(
        host: chatData['host'],
        username: chatData['username'],
        password: password,
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

  /// ✅ **Checks if a chat is active**
  bool isChatActive(String chatId) {
    return _chats.containsKey(chatId) &&
        (_chats[chatId]?['connected'] ?? false);
  }

  /// ✅ **Fetch File Suggestions from Current Directory**
  Future<void> updateFileSuggestions(String chatId) async {
    var chatData = _chats[chatId];

    // ✅ Ensure chatData exists and chat is connected
    if (chatData == null || !(chatData['connected'] ?? false)) return;

    String currentDir = chatData['currentDirectory'] ?? ".";

    // ✅ Fetch file list using SSH
    List<String> files = await SSHService().listFiles(
      host: chatData['host'] ?? "",
      username: chatData['username'] ?? "",
      password: chatData['password'] ?? "",
      directory: currentDir,
    );

    // ✅ Ensure "fileSuggestions" is initialized
    _chats[chatId]?['fileSuggestions'] = files;
    notifyListeners();
  }

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

  /// ✅ **Handles `cd` commands properly**
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
    if (_chats.containsKey(chatId)) {
      _chats.remove(chatId);
      saveChatHistory();
      notifyListeners();
    }
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
}
