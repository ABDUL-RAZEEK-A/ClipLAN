import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeBackgroundService() async {
  if (!Platform.isAndroid) {
    debugPrint('Background service not supported or disabled on this platform.');
    return;
  }
  
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'cliplan_foreground', // id
    'ClipLAN Service', // name
    description: 'This channel is used for ClipLAN background file transfers.',
    importance: Importance.low, // low importance prevents sound/vibration
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'cliplan_foreground',
      initialNotificationTitle: 'ClipLAN',
      initialNotificationContent: 'Running in background',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  // Background service is intentionally NOT started here.
  // It is managed dynamically by AppState._manageBackgroundService() 
  // only when there is an active file transfer.
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  // Initialize the core app state to keep sockets listening
  try {
    debugPrint('[ClipLAN] Background Service AppState initializing...');
    
    // We run a dummy periodic timer just to ensure the isolate doesn't die.
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
            debugPrint('[ClipLAN] Background service is active');
        }
      }
    });
  } catch (e) {
    debugPrint('[ClipLAN] Background Service Error: $e');
  }
}
