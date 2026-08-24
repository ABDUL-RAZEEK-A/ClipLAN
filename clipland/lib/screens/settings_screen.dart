import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glassmorphic_card.dart';

/// Settings page for device name, save path, and transfer preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameCtrl;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(
      text: context.read<AppState>().username,
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  void _saveName(AppState state) {
    final name = _usernameCtrl.text.trim();
    if (name.isNotEmpty) {
      state.updateUsername(name);
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 100,
                pinned: true,
                backgroundColor: AppColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  title: Text(
                    'Settings',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 22),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),

                    // ── User Identity ──────────────────────────────────────
                    _section('User Identity'),
                    const SizedBox(height: 12),
                    GlassmorphicCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Username',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _usernameCtrl,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter username',
                              prefixIcon: ShaderMask(
                                shaderCallback: (b) =>
                                    AppColors.gradientPrimary.createShader(b),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              suffixIcon: IconButton(
                                onPressed: () => _saveName(state),
                                icon: const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _saveName(state),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

                    const SizedBox(height: 24),

                    // ── Storage ──────────────────────────────────────────────
                    _section('Storage'),
                    const SizedBox(height: 12),
                    GlassmorphicCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Save Location',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final result =
                                  await FilePicker.getDirectoryPath();
                              if (result != null && context.mounted) {
                                context.read<AppState>().updateSavePath(result);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primaryLight.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.folder_open_rounded,
                                    color: AppColors.primaryLight,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      state.savePath.isEmpty
                                          ? 'Tap to set save location'
                                          : state.savePath,
                                      style: TextStyle(
                                        color: state.savePath.isEmpty
                                            ? AppColors.textTertiary
                                            : AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.edit_rounded,
                                    color: AppColors.textTertiary,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

                    const SizedBox(height: 24),

                    // ── Transfer ─────────────────────────────────────────────
                    _section('Transfer'),
                    const SizedBox(height: 12),
                    GlassmorphicCard(
                      child: Column(
                        children: [
                          _switchRow(
                            icon: Icons.wifi_find_rounded,
                            color: AppColors.accent,
                            title: 'Show Device IP',
                            subtitle: 'Display IP address on device cards',
                            value: state.showDeviceIp,
                            onChanged: state.updateShowDeviceIp,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

                    const SizedBox(height: 24),

                    // ── About ────────────────────────────────────────────────
                    _section('About'),
                    const SizedBox(height: 12),
                    GlassmorphicCard(
                      child: Column(
                        children: [
                          _infoRow(
                            Icons.info_outline_rounded,
                            'Version',
                            '1.0.0',
                          ),
                          const Divider(color: AppColors.divider, height: 24),
                          _infoRow(
                            Icons.wifi_rounded,
                            'Protocol',
                            'TCP / UDP LAN',
                          ),
                          const Divider(color: AppColors.divider, height: 24),
                          _infoRow(
                            Icons.security_rounded,
                            'Verification',
                            'SHA-256',
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

                    const SizedBox(height: 100),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _section(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppColors.primaryLight,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primaryLight
                : null,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primaryLight.withValues(alpha: 0.4)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 20),
        const SizedBox(width: 14),
        Text(title, style: const TextStyle(color: AppColors.textSecondary)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        ),
      ],
    );
  }
}
