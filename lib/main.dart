import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/app_state.dart';
import 'services/storage_service.dart';
import 'services/background_service.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        debugPrint('[ClipLAN] Flutter error: ${details.exception}');
        debugPrint('[ClipLAN] Stack: ${details.stack}');
      };

      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      final appDir = await getApplicationSupportDirectory();
      Hive.init(appDir.path);

      final storageService = StorageService();
      await storageService.init();

      // Do not await initializeBackgroundService() to prevent blocking the main thread
      // which can cause Application Not Responding (ANR) errors on Android startup.
      initializeBackgroundService().catchError((e) {
        debugPrint('[ClipLAN] Failed to initialize background service: $e');
      });

      runApp(
        ChangeNotifierProvider(
          create: (_) => AppState(storageService),
          child: const ClipLANApp(),
        ),
      );
    },
    (error, stackTrace) {
      debugPrint('[ClipLAN] Uncaught error: $error');
      debugPrint('[ClipLAN] Stack: $stackTrace');
      
      // Do not call runApp again if the app is already running, to avoid unmounting AppState.
      // We will rely on debugPrint. If you need to see the error, you should check the Xcode console.
    },
  );
}
