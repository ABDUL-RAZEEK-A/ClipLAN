import os

content = """# ClipLAN Application Documentation
## Comprehensive Technical Overview

================================================================================
1. INTRODUCTION AND MAIN FUNCTIONALITY
================================================================================

ClipLAN is a blazing-fast, decentralized, offline, peer-to-peer (P2P) file and clipboard sharing application built primarily to solve the bottleneck of transferring large files or text snippets between devices over local networks. The app is completely serverless, meaning it relies solely on the Local Area Network (LAN) or a mobile hotspot to communicate. By eliminating the cloud from the equation, ClipLAN achieves data transfer speeds limited only by the hardware limitations of the network interface cards (NIC) and Wi-Fi routers involved. 

### Focus on Android and iOS Capabilities
On mobile platforms (Android and iOS), the app focuses heavily on the seamless user experience. 
- **Android Capabilities**: Android users can take advantage of deep system integration using the `receive_sharing_intent` plugin, allowing users to select files directly from their gallery or file manager and share them instantly to ClipLAN. They can also use Wi-Fi Direct and Hotspot APIs for environments where no router is present. Furthermore, Android allows Background Services to keep transfers alive when the app is minimized (handled by wakelocks).
- **iOS Capabilities**: Due to iOS sandboxing, the app heavily relies on the `file_picker` to grant the application temporary read access to the Apple Files app and Photos Library. On iOS, the app leverages the Local Network Privacy permissions to perform UDP broadcasts. Clipboard sharing on iOS is highly restricted to foreground processes, so the app synchronizes clipboard states precisely when the user brings the app back to the foreground.

### Key Features
1. **P2P File Transfer:** No file size limits. Data flows directly from one IP address to another via a TCP socket.
2. **Cross-Platform Clipboard Synchronization:** Instantaneous text sharing between devices. A copied text snippet on an Android phone can immediately populate the clipboard of an iOS or macOS device on the network.
3. **QR Code Connection:** If UDP broadcasting fails due to complex network topologies (like enterprise networks blocking subnet broadcasts), devices can manually pair using QR codes containing the IP and port metadata.
4. **Offline First:** Zero internet reliance ensures absolute data privacy. 

================================================================================
2. TECHNOLOGY STACK
================================================================================

The technological foundation of ClipLAN is optimized for cross-platform compatibility, real-time socket communication, and performant UI rendering.

*   **Frontend / Core Framework**: Flutter (Dart)
    *   *Why?* Allows a single codebase to compile natively to Android (Kotlin/C++), iOS (Swift/Objective-C), macOS, Windows, and Linux.
*   **Networking Layer**: Raw Dart `dart:io` Sockets
    *   *Why?* Maximum throughput. We use `RawDatagramSocket` for UDP broadcasts and `ServerSocket`/`Socket` for TCP data streaming.
*   **State Management**: Provider (ChangeNotifier)
    *   *Why?* Offers an excellent balance of simplicity and performance. It allows deep widget trees to reactively rebuild only when specific application states (like transfer progress) change.
*   **Local Storage**: Hive (NoSQL Key-Value Store)
    *   *Why?* Hive is written in pure Dart and is incredibly fast. It operates synchronously, which makes reading application settings, transfer histories, and saved clipboards practically instantaneous.
*   **Design Language**: Custom Glassmorphism UI
    *   *Why?* Rather than adhering strictly to Material (Google) or Cupertino (Apple) guidelines, ClipLAN employs a futuristic, blurred, translucent UI architecture that looks premium on both mobile and desktop platforms.

================================================================================
3. SYSTEM DESIGN AND ARCHITECTURE
================================================================================

ClipLAN's architecture follows a classic Model-View-ViewModel (MVVM) inspired structure, loosely coupled via dependency injection (Provider). 

### The Network Topology
The system operates on a decentralized mesh topology. Every instance of ClipLAN acts as both a **Client** and a **Server**. 
1.  **Server Daemon**: Upon startup, the app spins up a TCP Server on a randomized port (or fixed if specified) to listen for incoming file and clipboard streams.
2.  **UDP Announcer**: Concurrently, it spins up a UDP broadcast socket. It shouts an "I am here" JSON payload to the `255.255.255.255` broadcast address at regular intervals.
3.  **The Handshake**: When Device B hears Device A's UDP broadcast, it reads Device A's IP and TCP port. If Device B wants to send a file to Device A, it opens a direct TCP connection to Device A's IP:Port. 
4.  **Payload Exchange**: The TCP stream is opened. The sender writes a JSON header (containing filename, size, type, and SHA-256 hash). A delimiter is sent, followed by the raw binary bytes of the file in chunks. The receiver parses the header, allocates file space, and writes the incoming bytes to the disk directly using `IOSink` to prevent RAM overflow.

================================================================================
4. THE 5 CORE MODULES
================================================================================

The application is strictly divided into 5 independent, highly cohesive modules.

### Module 1: The Discovery Module (`discovery_service.dart`)
**Purpose**: Responsible for finding other devices on the local network.
**How it Works**: 
This module leverages `RawDatagramSocket`. It binds to a specific UDP port (e.g., 53317). It runs a periodic timer (every 2-3 seconds) that serializes the device's metadata (Username, OS, Device ID, TCP Port) into a UTF-8 JSON string and broadcasts it over the subnet. Simultaneously, it listens for incoming datagrams. When a datagram is received from an external IP, it deserializes the payload, constructs a `DeviceInfo` object, and yields it to a Stream. It manages a cache of active devices, aging out devices that haven't broadcasted in the last 15 seconds.

### Module 2: The Transfer Module (`transfer_service.dart`)
**Purpose**: Handles the heavy lifting of raw data transmission.
**How it Works**:
This module utilizes `ServerSocket` and `Socket`. When initialized, it binds a TCP server to `InternetAddress.anyIPv4`. 
*   **Sending**: When a user selects a file, this module establishes a TCP client connection to the target device. It computes the SHA-256 hash of the file asynchronously. It creates a structured payload: a header containing `{ "type": "file", "name": "...", "size": X, "hash": "..." }`, followed by a `\n\n\n` delimiter, and then pipes the file stream directly into the socket using `File.openRead().pipe(socket)`.
*   **Receiving**: The `ServerSocket` listens for `Socket` connections. When a connection is accepted, it buffers the incoming bytes until it finds the `\n\n\n` delimiter. It parses the JSON header to understand what is coming. If it's a file, it opens an `IOSink` to the device's Downloads directory and writes the remaining byte stream to the disk in real-time. It reports progress by comparing `bytesReceived` against the `size` specified in the header.

### Module 3: The State Management Module (`app_state.dart`)
**Purpose**: The central brain connecting the UI to the background services.
**How it Works**:
Extending `ChangeNotifier`, this module holds the current state of the application. It instantiates the `DiscoveryService` and `TransferService`. It listens to their streams. When the `DiscoveryService` finds a new device, it updates the `availableDevices` list and calls `notifyListeners()`, which instantly updates the radar animation on the UI. It manages the queue of active transfers, tracking their progress (0.0 to 1.0), speed (MB/s), and status (pending, transferring, completed, failed). It is also responsible for bridging the `Clipboard` API with the `TransferService` to send text snippets as special TCP payloads.

### Module 4: The Storage & Persistence Module (`storage_service.dart` + Hive)
**Purpose**: Ensuring data survives app restarts.
**How it Works**:
Before the Flutter engine renders the first frame, Hive is initialized. It opens several binary boxes (e.g., `settingsBox`, `historyBox`, `clipboardBox`). The `StorageService` acts as a repository pattern wrapper around Hive. When a transfer completes successfully, the State Management module sends a `TransferItem` object to the `StorageService`. The service saves this to the `historyBox`. When the app cold-starts, it reads this box to populate the History Screen. It also stores user preferences like their custom username, dark mode settings, and default save directories.

### Module 5: The User Interface (UI) Module (`screens/` and `widgets/`)
**Purpose**: The visual layer users interact with.
**How it Works**:
Built entirely in Flutter, this module observes the State Management module. 
*   `devices_screen.dart` renders a beautiful radar pulsing animation (using `CustomPainter` and `AnimationController`) to visually represent the network search.
*   `transfer_card.dart` uses `LinearProgressIndicator` bound to the active transfer's progress value to show real-time completion status.
*   The UI makes heavy use of `BackdropFilter` to achieve the glassmorphic blur effects over animated backgrounds, ensuring the app feels native, fluid, and premium on iOS and Android.

================================================================================
5. DEPENDENCY INJECTION & EXTERNAL LIBRARIES
================================================================================

ClipLAN avoids reinventing the wheel by leveraging robust community dependencies listed in `pubspec.yaml`:

1.  **`provider`**: The core state management library. It injects the `AppState` at the root of the widget tree so any nested widget can read or manipulate the application state without passing callbacks down multiple layers.
2.  **`hive` & `hive_flutter`**: A lightweight, incredibly fast NoSQL database. Chosen over SQLite because P2P apps require extremely fast, synchronous read/writes for settings and history logs without the overhead of SQL queries.
3.  **`file_picker`**: Crucial for cross-platform file selection. It interfaces with the Android Storage Access Framework (SAF) and the iOS Document Picker/Photos library, returning abstract `PlatformFile` objects that the app can read from.
4.  **`path_provider`**: Resolves the complex directory structures of different operating systems. It tells the app where the "Downloads" or "Application Documents" directories are located securely on iOS and Android.
5.  **`crypto`**: Used to generate SHA-256 hashes of files before they are sent, and re-hashing them upon receipt to guarantee data integrity over the network.
6.  **`uuid`**: Generates unique identifiers for devices and individual transfer sessions, preventing collisions if two files with the same name are sent simultaneously.
7.  **`mobile_scanner` & `qr_flutter`**: Powers the manual QR code connection system. `qr_flutter` renders the IP/Port payload as a scannable graphic, while `mobile_scanner` accesses the device camera to decode it.
8.  **`receive_sharing_intent`**: Deep OS integration for Android/iOS. Allows users to "Share" a file from their phone's native gallery directly into ClipLAN, intercepting the intent bundle and triggering the transfer logic automatically.
9.  **`wakelock_plus`**: Essential for mobile devices. It prevents the CPU and screen from going to sleep during a long multi-gigabyte file transfer.
10. **`open_filex`**: Provides the ability to tap on a completed transfer in the History screen and have the native OS open it in the default application (e.g., opening a received `.mp4` in VLC or the native video player).

================================================================================
6. DETAILED FILE CONTRIBUTIONS (CODEBASE BREAKDOWN)
================================================================================

To understand how the app functions, one must examine the responsibility of each specific file in the `lib/` directory.

### `/models/` Directory
The blueprint of the application's data.
*   **`device_info.dart`**: Contains the `DeviceInfo` class. This defines what a "Peer" looks like: String id, String name, String os, String ip, and int port. It includes `fromJson` and `toJson` methods for UDP serialization.
*   **`transfer_item.dart`**: The model representing an active or completed transfer. It holds the file name, size, speed, progress, sender/receiver details, and status enums (`Pending`, `Transferring`, `Completed`, `Failed`).
*   **`clipboard_item.dart`**: A simple wrapper representing a synchronized string of text, complete with timestamps and origin device info.

### `/providers/` Directory
*   **`app_state.dart`**: The monolith orchestrator. It holds lists of `DeviceInfo` and `TransferItem`. It handles the logic of "User tapped send -> Start file picker -> Get path -> Call TransferService.sendFile()". It listens to the `ReceiveSharingIntent` streams and automatically starts transfers when external intents are caught.

### `/screens/` Directory
*   **`home_screen.dart`**: The main navigation hub, usually a `Scaffold` with a `BottomNavigationBar` connecting to the other screens.
*   **`devices_screen.dart`**: The flagship UI component. It displays the radar animation. It lists discovered devices via a `ListView.builder`. Tapping a device opens an action sheet (Send File / Send Clipboard).
*   **`file_browser_screen.dart`**: A custom interface to view the internal storage and app-specific directories, allowing users to manage received files natively within the app.
*   **`clipboard_screen.dart`**: Displays a history of received clipboards. It features a text input field to manually type and broadcast text to connected devices.
*   **`history_screen.dart`**: A list of all historical transfers loaded from Hive. Features progress bars for ongoing transfers and "Open File" buttons for completed ones.
*   **`settings_screen.dart`**: Allows the user to change their display name, toggle dark mode, specify fixed TCP ports, and wipe the database history.
*   **`qr_scanner_screen.dart`**: A full-screen camera view wrapping `mobile_scanner` to decode fallback QR connections.

### `/services/` Directory
The background workers doing the heavy OS-level interactions.
*   **`discovery_service.dart`**: Handles `RawDatagramSocket`. Core functions: `startBroadcasting()`, `startListening()`, `stop()`.
*   **`transfer_service.dart`**: Handles `ServerSocket` and `Socket`. Core functions: `startServer()`, `sendFile(File, TargetIP)`, `sendClipboard(Text, TargetIP)`. Manages the complex byte chunking and JSON header protocol.
*   **`storage_service.dart`**: The Hive wrapper. Core functions: `saveTransfer()`, `getTransfers()`, `updateSettings()`.
*   **`rate_limiter.dart`**: A small utility class to prevent the UI from choking. When downloading at 500 MB/s, calling `notifyListeners()` on every byte chunk would freeze the Flutter rendering thread. The rate limiter ensures UI progress updates only happen every 50-100 milliseconds.

### `/widgets/` Directory
Reusable, decoupled visual components.
*   **`radar_animation.dart`**: A highly optimized `CustomPainter` that draws concentric expanding circles, mathematically calculating opacities based on animation controllers to simulate a sonar ping.
*   **`transfer_card.dart`**: A sophisticated list tile that changes color based on the transfer status, containing a `LinearProgressIndicator` and speed/ETA text calculations.
*   **`glassmorphic_card.dart`**: A wrapper widget utilizing `BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10))` wrapped in a `ClipRRect` to give the app its signature translucent aesthetic.
*   **`hashing_dialog.dart`**: An indeterminate loading modal displayed when the app is computing the SHA-256 hash of a massive file before the network transfer begins, preventing the user from thinking the app has frozen.

================================================================================
7. CONCLUSION
================================================================================

ClipLAN is a masterpiece of local networking architecture wrapped in a beautiful, cross-platform Flutter shell. By separating concerns strictly—isolating raw TCP/UDP socket programming into background services, managing global application state via Provider, persisting data synchronously through Hive, and rendering high-framerate glassmorphic UIs—the application maintains high cohesion and low coupling. This makes the codebase highly scalable, exceptionally fast, and completely secure for the end user on both Android, iOS, and desktop platforms.
"""

with open("detail.txt", "w") as f:
    f.write(content)

print("Documentation generated successfully.")
