# ChatOps - DevOps Assistant

## 📌 Overview
ChatOps is a **Flutter-based** DevOps assistant that allows users to **connect to remote servers via SSH** and execute commands seamlessly. The app provides an intuitive chat-style interface to interact with servers, run commands, and retrieve outputs in real time.

## 🎯 Features
- **SSH Connection**: Securely connect to remote servers using **root@IP** credentials.
- **Command Execution**: Send SSH commands and receive real-time responses.
- **Persistent Chat History**: Retains past command logs for each connected session.
- **Multiple Server Chats**: Each server connection is treated as a separate chat session.
- **Automatic Session Management**: Detects active sessions and allows quick reconnects.
- **Dark & Light Theme Support**: Adjusts based on system preferences.
- **Secure Authentication**: Optional encryption of stored credentials.
- **Chat Name Customization**: Rename chat sessions to match server names or projects.

## 🛠️ Tech Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Flask (Python) API with SSH handling
- **State Management**: Provider
- **Networking**: HTTP API calls
- **Storage**: SharedPreferences for persistent data

## 🚀 Installation & Setup

### 📌 Prerequisites
- **Flutter** (latest stable version)
- **Dart SDK**
- **Android Studio / VS Code**
- **A running SSH API server** (see backend setup)

### 🛠️ Steps to Run the App
1. **Clone the Repository**:
   ```sh
   git clone https://github.com/your-repo/chatops.git
   cd chatops
   ```
2. **Install Dependencies**:
   ```sh
   flutter pub get
   ```
3. **Run the App**:
   ```sh
   flutter run
   ```
4. **(Optional) Build for Production**:
   ```sh
   flutter build apk  # Android
   flutter build ios  # iOS
   ```

## 🔌 Connecting to SSH API Server
Ensure your **SSH API server** is running (either locally or on DigitalOcean). Update `ssh_service.dart` with your server URL:
```dart
final String apiUrl = "http://your-server-ip/ssh";  // Replace with your API
```

## 📝 Project Structure
```
chatops/
├── lib/
│   ├── main.dart                # Entry Point
│   ├── screens/
│   │   ├── home_screen.dart      # Main UI
│   │   ├── chat_screen.dart      # Chat UI for SSH sessions
│   │   ├── settings_screen.dart  # App Settings
│   │   ├── history_screen.dart   # Chat History
│   ├── providers/
│   │   ├── chat_provider.dart    # Manages chat & SSH connections
│   │   ├── theme_provider.dart   # Handles Dark/Light Mode
│   ├── services/
│   │   ├── ssh_service.dart      # API requests to SSH server
│   ├── models/
│   │   ├── chat_model.dart       # Chat Data Model
│
├── assets/                       # Icons, Images
├── pubspec.yaml                   # Dependencies
├── README.md                      # Documentation
```

## 🔧 Configuration & Customization
- **Changing Default SSH API Server**: Update `ssh_service.dart`:
  ```dart
  final String apiUrl = "https://your-api-url/ssh";
  ```
- **Modifying Chat UI**: Edit `chat_screen.dart` to adjust the chat bubble design.
- **Changing Themes**: Modify `theme_provider.dart` to adjust colors.

## 🚀 Future Enhancements
- ✅ AI-based suggestions for frequently used SSH commands.
- ✅ Multi-server session management.
- ✅ Biometric authentication for secure SSH login.
- ✅ WebSocket support for real-time command execution.

## 📜 License
This project is **MIT Licensed**. Feel free to use and modify it for your own needs!

## 🛠️ Contributing
We welcome contributions! Feel free to open issues and submit pull requests. 🚀🔥

