# ClipLAN Project Architecture

This document outlines the core tree structure of the ClipLAN project, specifically focusing on the `lib` folder where all the application logic, UI, and state management reside.

## Tree Structure & Core Functions

```text
lib/
├── main.dart
├── app.dart
├── models/
│   ├── clipboard_item.dart
│   ├── device_info.dart
│   └── transfer_item.dart
├── providers/
│   └── app_state.dart
├── screens/
│   ├── clipboard_screen.dart
│   ├── devices_screen.dart
│   ├── file_browser_screen.dart
│   ├── history_screen.dart
│   ├── home_screen.dart
│   ├── qr_scanner_screen.dart
│   └── settings_screen.dart
├── services/
│   ├── background_service.dart
│   ├── discovery_service.dart
│   ├── rate_limiter.dart
│   ├── storage_service.dart
│   └── transfer_service.dart
├── theme/
│   └── app_theme.dart
└── widgets/
    ├── approval_sheet.dart
    ├── connected_devices_panel.dart
    ├── device_tile.dart
    ├── glassmorphic_card.dart
    ├── hashing_dialog.dart
    ├── qr_display_sheet.dart
    ├── radar_animation.dart
    ├── shared_clipboard_sheet.dart
    ├── transfer_card.dart
    └── username_dialog.dart
```

### Core Files

*   **`main.dart`**: The entry point of the Flutter application. It initializes global configurations (like Hive database, Background Service) and starts the app.
*   **`app.dart`**: Contains the root `ClipLANApp` widget. It sets up the `MaterialApp`, routing, and injects the global `AppTheme`.

### `models/` (Data Structures)
*This folder contains data classes that define the shapes of the objects used throughout the app.*
*   **`clipboard_item.dart`**: Defines the structure for copied text (content, sender, timestamp) used in the shared clipboard feature.
*   **`device_info.dart`**: Represents a peer device on the network (Name, IP, OS, Hardware, and Last Seen time).
*   **`transfer_item.dart`**: The most complex model. Represents a file transfer session, tracking progress, speed, file list, and transfer status (pending, transferring, completed, failed).

### `providers/` (State Management)
*This folder manages the global state of the application using the Provider pattern.*
*   **`app_state.dart`**: The central brain of the UI. It holds the lists of discovered devices, transfer history, and handles linking the UI to the underlying services (like initiating a transfer when a user taps a device).

### `screens/` (User Interface Pages)
*This folder contains the full-screen views of the application.*
*   **`home_screen.dart`**: The main navigation hub (usually containing a bottom navigation bar or tabs).
*   **`devices_screen.dart`**: The radar/discovery page where nearby peers are displayed.
*   **`file_browser_screen.dart`**: The interface for the user to select files/folders from their local storage to send.
*   **`clipboard_screen.dart`**: The page displaying the shared text clipboard history.
*   **`history_screen.dart`**: Displays past file transfers (sent and received).
*   **`qr_scanner_screen.dart`**: A camera interface to scan QR codes for manual device linking.
*   **`settings_screen.dart`**: Allows the user to configure app preferences (username, save paths, auto-accept).

### `services/` (Business Logic & Networking)
*This folder is the engine of the app. It handles heavy lifting, networking, and background tasks independently of the UI.*
*   **`background_service.dart`**: (Added recently) Keeps the app's networking isolate alive in the background on mobile devices, allowing files to be received while the app is minimized.
*   **`discovery_service.dart`**: Handles UDP Multicast/Broadcast networking. It continuously shouts the device's presence to the local network and listens for other devices shouting back.
*   **`transfer_service.dart`**: Handles TCP networking for actual file transfers. It uses Dart Isolates (background threads) to read/write large files over network sockets without freezing the UI.
*   **`storage_service.dart`**: Interfaces with the local file system and Hive (local database) to save settings, history, and the files themselves.
*   **`rate_limiter.dart`**: A utility to prevent spamming the network or UI with too many updates in a short time.

### `theme/` (Styling)
*   **`app_theme.dart`**: Contains the color palettes, text styles, and global component themes (like button shapes and card shadows) to ensure consistent design.

### `widgets/` (Reusable UI Components)
*This folder contains smaller, reusable pieces of the UI used inside the screens.*
*   **`radar_animation.dart`**: The custom animated pulsing radar background seen on the devices screen.
*   **`glassmorphic_card.dart`**: A styled container providing a frosted-glass blur effect used throughout the app.
*   **`transfer_card.dart`**: The UI card that displays the progress bar, speed, and file names during an active transfer.
*   **`device_tile.dart`**: The list item representing a discovered device on the network.
*   **`approval_sheet.dart` / `username_dialog.dart` / `hashing_dialog.dart` / `qr_display_sheet.dart`**: Various popups and bottom sheets for user interaction.
