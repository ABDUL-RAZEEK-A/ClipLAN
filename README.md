# ClipLAN (ClipLAN)

ClipLAN is a blazing fast, open-source, serverless, peer-to-peer (P2P) local area network (LAN) file sharing and real-time shared clipboard application built using Flutter.

It is designed to easily share massive files (Gigabytes in size) at maximum local network speeds (often exceeding 30-50+ MB/s) with extreme stability, completely offline.

## Key Features

- **⚡ Blazing Fast & Unlimited:** Transfers happen over direct TCP local connections, limited only by your Wi-Fi router's maximum bandwidth. No artificial rate limits.
- **🔋 Rock-Solid Stability:** Engineered for massive files. Features active WakeLock management to prevent CPU sleep, and OOM (Out Of Memory) protection using `IOSink` backpressure to guarantee stability on low-RAM devices even when disk write speeds bottleneck network speeds.
- **🚫 100% Serverless & Offline:** Operates entirely without internet access, external cloud servers, or manual Bluetooth pairing. It discovers devices instantly using UDP multicasting.
- **🛡️ Secure & Verified:** Transfers are verified on the fly using end-to-end real-time SHA-256 cryptographic checksum computation.
- **📁 Advanced File Browser:** Built-in clean file browser with quick navigation, category filters (Images, Videos, Audios, Apps, Documents), and home shortcuts.
- **📋 Network Clipboard:** Seamlessly share text snippets and URLs across your local network in real-time.
- **🖥️ Cross-Platform:** Works natively on Android, iOS, and macOS (with Apple Sandbox removal for true filesystem access).

## How it Works (Under the Hood)

1. **Discovery**: Devices find each other instantly using zero-configuration UDP multicasting (port 53317).
2. **Transfer Engine**: Files are broken down and streamed in memory-efficient 2MB chunks over raw TCP sockets (port 53318).
3. **Memory Safety**: `await sink.flush()` ensures the Dart internal memory buffer never balloons out of control on slow disk storage (like cheap SD cards), preventing Android OOM crashes.
4. **Cancellation Integrity**: Securely handles remote and local cancellations, aborting network streams instantly and cleaning up incomplete files.

## Getting Started

Make sure you have Flutter installed.

```bash
# Clone the repository
# Navigate to the cliplan directory
cd cliplan

# Get dependencies
flutter pub get

# Run on macOS or Android
flutter run
```

To build a release APK for Android:
```bash
flutter build apk
```

## Architecture Details
For a deeper dive into the exact UDP discovery mechanisms, TCP protocols, and data models used, please read `details/hifg.txt` located in the root of the project structure.
