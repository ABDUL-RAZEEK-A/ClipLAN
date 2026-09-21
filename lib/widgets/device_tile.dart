import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/device_info.dart';
import '../theme/app_theme.dart';

/// Tappable tile representing a discovered network device.
class DeviceTile extends StatelessWidget {
  final DeviceInfo device;
  final bool isSelected;
  final bool showIp;
  final VoidCallback onTap;

  const DeviceTile({
    super.key,
    required this.device,
    required this.isSelected,
    required this.onTap,
    this.showIp = false,
  });

  IconData _platformIcon() {
    switch (device.platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.computer_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    AppColors.primaryLight.withValues(alpha: 0.2),
                    AppColors.primary.withValues(alpha: 0.15),
                  ],
                )
              : LinearGradient(
                  colors: [
                    AppColors.surface.withValues(alpha: 0.8),
                    AppColors.surface.withValues(alpha: 0.6),
                  ],
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryLight.withValues(alpha: 0.5)
                : AppColors.primaryLight.withValues(alpha: 0.06),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryLight.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Avatar or Platform icon
            if (device.avatarBase64 != null && device.avatarBase64!.isNotEmpty)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryLight, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryLight.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  image: DecorationImage(
                    image: MemoryImage(base64Decode(device.avatarBase64!)),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPrimary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryLight.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _platformIcon(),
                  color: AppColors.textPrimary,
                  size: 24,
                ),
              ),
            const SizedBox(width: 16),

            // Name & IP
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (device.username != null && device.username!.isNotEmpty)
                        ? '${device.username} - ${device.os ?? ''} ${device.hardwareName ?? ''}'
                        : device.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (showIp) ...[
                        Text(
                          device.ip,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '·',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        device.platform,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primaryLight : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryLight
                      : AppColors.textTertiary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      color: AppColors.background,
                      size: 16,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
