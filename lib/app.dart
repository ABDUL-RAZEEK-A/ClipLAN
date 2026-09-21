import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'providers/app_state.dart';
import 'widgets/username_dialog.dart';

class ClipLANApp extends StatelessWidget {
  const ClipLANApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClipLAN',
      scaffoldMessengerKey: context.read<AppState>().scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Consumer<AppState>(
        builder: (context, state, _) {
          // First-launch flow — modeled after reference repo's haveUser()
          if (!state.hasCompletedSetup) {
            return UsernameDialog(
              currentName: state.username,
              onNameSet: (name) => state.completeSetup(name),
            );
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
