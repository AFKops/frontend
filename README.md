AFKOps (Flutter Frontend)
A modern Flutter-based frontend for the AFKOps project. It connects to a secure backend WebSocket server to provide remote SSH access and real-time terminal interaction from your mobile device.

Features
Connect to any SSH server using encrypted credentials

Real-time streaming terminal interface

Supports Ctrl+C for process interruption

Directory listing (cd, ls, etc.)

Notepad-style command saving per session

Persistent SSH chat history with reconnect options

Built with Provider, WebSocket, AES encryption, and Material UI

Installation & Setup
1. Clone the Repository
bash
Copy
git clone https://github.com/chatdevops/frontend.git
cd frontend
2. Install Dependencies
bash
Copy
flutter pub get
3. Update WebSocket URL
By default, the app connects to the backend server hosted at:

ws://137.184.69.130:5000/ssh-stream

If you're self-hosting the backend, change this line in lib/services/ssh_service.dart:

dart
Copy
final String wsUrl = "ws://your_server_ip:5000/ssh-stream";
If you're using WSS (SSL), make sure you update this to:

dart
Copy
final String wsUrl = "wss://yourdomain.com/ssh-stream";
4. Build & Run the App
bash
Copy
flutter run
📦 For release APK:

bash
Copy
flutter build apk --release
Requirements
Flutter SDK (3.10+ recommended)

Android device or emulator

Backend server running AFKOps WebSocket backend

Current Limitations
Currently tested only on Android

SSH Keys are not yet supported (only username/password)

UI optimizations for iOS and tablets are in progress

Known Issues
The suggestive directory pop-up is not working completely. 

Notes
All SSH credentials are encrypted using AES-CBC before being transmitted

The encryption key is fetched securely from the backend on app launch

Passwords can optionally be stored securely using encrypted SharedPreferences

Future Work
In upcoming releases, the app will integrate an AI command assistant. Users will be able to type natural-language instructions like:

vbnet
Copy
give me the logs
The app will interpret and convert this into appropriate terminal commands, such as:

css
Copy
journalctl --follow -u nginx
This will make the tool even more powerful for less technical users.

License
MIT License. Feel free to fork, use, modify, and contribute. Shoutout appreciated if you find it useful.

