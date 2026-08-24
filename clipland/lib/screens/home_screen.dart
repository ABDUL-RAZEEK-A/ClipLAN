import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/transfer_item.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/approval_sheet.dart';
import 'devices_screen.dart';
import 'clipboard_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Root shell screen with animated bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  late final PageController _pageCtrl;

  final _screens = const [
    DevicesScreen(),
    ClipboardScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();

    // Wire up the approval dialog callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.showApprovalDialog = _showApproval;
      state.onClipboardReceived = _showClipboardApproval;
    });
  }

  Future<bool> _showApproval(TransferItem transfer) async {
    if (!mounted) return false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ApprovalSheet(transfer: transfer),
    );
    return result ?? false;
  }

  Future<bool> _showClipboardApproval(Map<String, dynamic> data) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Incoming Clipboard',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: Text(
              '${data['senderName']} shared text:\n\n"${data['text']}"\n\nCopy to your system clipboard?',
              style: const TextStyle(color: AppColors.textTertiary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Decline',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.background,
                ),
                child: const Text('Copy'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _index = i),
                children: _screens,
              )
              .animate()
              .fadeIn(duration: 600.ms, curve: Curves.easeOutCubic)
              .scaleXY(begin: 0.95, end: 1.0),
      bottomNavigationBar: _nav()
          .animate()
          .fadeIn(delay: 200.ms)
          .slideY(begin: 0.5, curve: Curves.easeOutCubic),
    );
  }

  Widget _nav() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surface.withValues(alpha: 0.98),
            AppColors.background.withValues(alpha: 0.95),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.primaryLight.withValues(alpha: 0.08),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.radar_rounded, 'Discover'),
              _navItem(1, Icons.assignment_rounded, 'Clipboard'),
              _navItem(2, Icons.history_rounded, 'History'),
              _navItem(3, Icons.settings_rounded, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final sel = _index == i;
    return GestureDetector(
      onTap: () => _goTo(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: sel ? 20 : 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel
              ? AppColors.primaryLight.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: sel
              ? [
                  BoxShadow(
                    color: AppColors.primaryLight.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: sel ? AppColors.primaryLight : AppColors.textTertiary,
              size: 24,
            ),
            if (sel) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
