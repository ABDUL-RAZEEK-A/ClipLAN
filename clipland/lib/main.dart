import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/app_state.dart';
import 'services/storage_service.dart';

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
          systemNavigationBarColor: Color(0xFFF0F6FF),
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      await Hive.initFlutter();

      final storageService = StorageService();
      await storageService.init();

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
    },
  );
}
