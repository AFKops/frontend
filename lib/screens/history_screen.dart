import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // ✅ Import intl for timestamp formatting
import '../providers/chat_provider.dart';
import 'chat_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final sortedChats = chatProvider.chats.entries.toList()
      ..sort((a, b) {
        DateTime timeA;
        DateTime timeB;
        try {
          timeA = DateTime.parse(a.value['lastActive']);
          timeB = DateTime.parse(b.value['lastActive']);
        } catch (e) {
          timeA = DateTime.now();
          timeB = DateTime.now();
        }
        return timeB.compareTo(timeA); // Sort in descending order
      });

    final filteredChats = sortedChats.where((entry) {
      return entry.value['name']
          .toLowerCase()
          .contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat History"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
              decoration: const InputDecoration(
                hintText: "Search chats...",
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredChats.length,
              itemBuilder: (context, index) {
                final entry = filteredChats[index];
                return ListTile(
                  title: Text(entry.value['name']),
                  subtitle: Text(
                      "Last Active: ${chatProvider.formatTimestamp(entry.value['lastActive'])}"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(chatId: entry.key),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      chatProvider.deleteChat(entry.key);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
