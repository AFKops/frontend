# AFKOps (Flutter Frontend)

A Flutter-based frontend for the AFKOps project. It connects to a secure backend WebSocket server to provide remote SSH access and real-time terminal interaction from your mobile device.

---

## Features

- Connect to any SSH server using encrypted credentials
- Real-time streaming terminal interface
- Supports Ctrl+C for process interruption
- Directory listing (cd, ls, etc.)
- Notepad-style command saving per session
- Persistent SSH chat history with reconnect options
- Built with Provider, WebSocket, AES encryption, and Material UI

---

## Installation & Setup

### 1. Clone the Repository

```bash
git clone https://github.com/chatdevops/frontend.git
cd frontend
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Update WebSocket URL

> By default, the app connects to the backend server hosted at:
>
> `ws://afkops.com/ssh-stream`
>
> If you're self-hosting the backend, change this line in `lib/services/ssh_service.dart`:

```dart
final String wsUrl = "ws://your_server_ip:5000/ssh-stream";
```

If you're using WSS (SSL), make sure you update this to:

```dart
final String wsUrl = "wss://yourdomain.com/ssh-stream";
```

### 4. Build & Run the App

```bash
flutter run
```

> 📦 For release APK:
>
> ```bash
> flutter build apk --release
> ```

---

## Requirements

- Flutter SDK (3.10+ recommended)
- Android device or emulator
- Backend server running [AFKOps WebSocket backend](https://github.com/chatdevops/backend)

---

## Known Issues

- Directory auto-suggestion (popup) is partially functional and does not always show suggestions

## Current Limitations

- Currently tested only on **Android**
- SSH Keys are not yet supported (only username/password)
- UI optimizations for iOS and tablets are in progress
- Directory auto-suggestion (popup) is partially functional and does not always show suggestions

---

## Notes

- All SSH credentials are encrypted using AES-CBC before being transmitted
- The encryption key is fetched securely from the backend on app launch
- Passwords can optionally be stored securely using encrypted SharedPreferences

---

## Future Work

In upcoming releases, the app will integrate an AI command assistant. Users will be able to type natural-language instructions like:

```
give me the logs
```

The app will interpret and convert this into appropriate terminal commands, such as:

```
journalctl --follow -u nginx
```

This will make the tool even more powerful for less technical users.

---

## License

MIT License. Feel free to fork, use, modify, and contribute. Shoutout appreciated if you find it useful.

