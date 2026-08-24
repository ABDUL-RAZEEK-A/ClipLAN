import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/transfer_item.dart';
import '../theme/app_theme.dart';

/// Card showing an active transfer with progress bar.
class TransferCard extends StatelessWidget {
  final TransferItem transfer;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;

  const TransferCard({
    super.key,
    required this.transfer,
    this.onCancel,
    this.onDismiss,
  });

  Color _statusColor() {
    switch (transfer.status) {
      case TransferStatus.completed:
        return AppColors.success;
      case TransferStatus.failed:
        return AppColors.error;
      case TransferStatus.cancelled:
        return AppColors.warning;
      case TransferStatus.transferring:
        return AppColors.primaryLight;
      case TransferStatus.verifying:
        return AppColors.secondary;
      case TransferStatus.waitingApproval:
        return AppColors.warning;
      case TransferStatus.pending:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSending = transfer.direction == TransferDirection.sending;
    final color = _statusColor();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surface.withValues(alpha: 0.9),
            AppColors.surface.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSending ? Icons.upload_rounded : Icons.download_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isSending ? "Sending to" : "Receiving from"} ${transfer.deviceName}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transfer.files.length} file${transfer.files.length > 1 ? "s" : ""} · ${transfer.formattedTotalSize}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  transfer.statusLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDismiss != null &&
                  (transfer.status == TransferStatus.completed ||
                      transfer.status == TransferStatus.failed ||
                      transfer.status == TransferStatus.cancelled)) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Progress section
          if (transfer.status == TransferStatus.transferring) ...[
            const SizedBox(height: 16),
            if (transfer.currentFileIndex < transfer.files.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  transfer.files[transfer.currentFileIndex].name,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            LayoutBuilder(
              builder: (context, box) {
                return Stack(
                  children: [
                    Container(
                      height: 8,
                      width: box.maxWidth,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 8,
                      width: box.maxWidth * transfer.progress,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientPrimary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryLight.withValues(
                              alpha: 0.4,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(transfer.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'File ${transfer.currentFileIndex + 1} of ${transfer.files.length}',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],

          // Cancel
          if (transfer.status == TransferStatus.transferring ||
              transfer.status == TransferStatus.waitingApproval) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  backgroundColor: AppColors.error.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],

          // Checksum
          if (transfer.status == TransferStatus.completed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  transfer.checksumValid == null
                      ? Icons.bolt_rounded
                      : (transfer.checksumValid!
                            ? Icons.verified_rounded
                            : Icons.warning_rounded),
                  color: transfer.checksumValid == null
                      ? AppColors.primaryLight
                      : (transfer.checksumValid!
                            ? AppColors.success
                            : AppColors.warning),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  transfer.checksumValid == null
                      ? 'Transferred (Fast mode)'
                      : (transfer.checksumValid!
                            ? 'Checksum verified ✓'
                            : 'Checksum mismatch'),
                  style: TextStyle(
                    color: transfer.checksumValid == null
                        ? AppColors.primaryLight
                        : (transfer.checksumValid!
                              ? AppColors.success
                              : AppColors.warning),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],

          // Received File Actions
          if (!isSending &&
              transfer.status == TransferStatus.completed &&
              transfer.files.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (transfer.files.length == 1) ...[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        final file = transfer.files.first;
                        if (file.path != null) {
                          OpenFilex.open(file.path!);
                        }
                      },
                      icon: const Icon(Icons.file_open_rounded, size: 16),
                      label: const Text('Open File'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        backgroundColor: AppColors.primaryLight.withValues(
                          alpha: 0.1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      final file = transfer.files.first;
                      if (file.path != null) {
                        final parentDir = File(file.path!).parent.path;
                        OpenFilex.open(parentDir);
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Show Folder'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      backgroundColor: AppColors.surfaceLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
