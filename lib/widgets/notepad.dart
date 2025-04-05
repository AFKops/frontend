import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';

class FullNotepadScreen extends StatelessWidget {
  final String chatId;
  const FullNotepadScreen({super.key, required this.chatId});

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    final controller = TextEditingController(
      text: chatProvider.getChatById(chatId)?['notepadText'] ?? "",
    );

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF171717) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF171717) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDarkMode ? Colors.white : Colors.black,
        ),
        title: Text(
          "Notepad",
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.save,
                color: isDarkMode ? Colors.white : Colors.black),
            onPressed: () {
              chatProvider.getChatById(chatId)?['notepadText'] =
                  controller.text;
              chatProvider.saveChatHistory();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          color: Colors.transparent,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontSize: 16,
              height: 1.6,
            ),
            decoration: const InputDecoration(
              hintText: "Note",
              hintStyle: TextStyle(
                color: Colors.white54,
                fontSize: 16,
              ),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isCollapsed: true,
            ),
          ),
        ),
      ),
    );
  }
}
