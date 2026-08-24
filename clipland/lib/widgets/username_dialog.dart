import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// Full-screen dialog shown on first launch to set the device name.
/// Modeled after the reference repo's `haveUser()` first-launch flow.
class UsernameDialog extends StatefulWidget {
  final String currentName;
  final ValueChanged<String> onNameSet;

  const UsernameDialog({
    super.key,
    required this.currentName,
    required this.onNameSet,
  });

  @override
  State<UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<UsernameDialog> {
  late final TextEditingController _ctrl;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.currentName == 'My Device' ? '' : widget.currentName,
    );
    _isValid = _ctrl.text.trim().isNotEmpty;
    _ctrl.addListener(() {
      final valid = _ctrl.text.trim().isNotEmpty;
      if (valid != _isValid) setState(() => _isValid = valid);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isNotEmpty) {
      widget.onNameSet(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App icon with glow
                Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryLight.withValues(alpha: 0.2),
                            AppColors.accent.withValues(alpha: 0.1),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryLight.withValues(
                              alpha: 0.2,
                            ),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: ShaderMask(
                        shaderCallback: (b) =>
                            AppColors.gradientPrimary.createShader(b),
                        child: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    )
                    .animate()
                    .scale(
                      begin: const Offset(0, 0),
                      curve: Curves.elasticOut,
                      duration: 800.ms,
                    )
                    .fadeIn(),

                const SizedBox(height: 32),

                // Welcome text
                Text(
                  'Welcome to ClipLAN',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontSize: 26),
                ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 12),

                Text(
                  'Set your username so others can\nidentify you on the network',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 40),

                // Name input card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryLight.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'USERNAME',
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ctrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Abdul',
                          prefixIcon: ShaderMask(
                            shaderCallback: (b) =>
                                AppColors.gradientPrimary.createShader(b),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 32),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isValid ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primaryLight
                          .withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.white.withValues(
                        alpha: 0.5,
                      ),
                      elevation: _isValid ? 4 : 0,
                      shadowColor: AppColors.primaryLight.withValues(
                        alpha: 0.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 24),

                // Info note
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.textTertiary.withValues(alpha: 0.5),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'You can change this later in Settings',
                      style: TextStyle(
                        color: AppColors.textTertiary.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ).animate(delay: 600.ms).fadeIn(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
