import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_state.dart';
import '../models/device_info.dart';
import '../theme/app_theme.dart';
import '../widgets/device_tile.dart';
import '../widgets/transfer_card.dart';
import '../widgets/radar_animation.dart';
import '../widgets/glassmorphic_card.dart';
import '../widgets/qr_display_sheet.dart';
import 'file_browser_screen.dart';
import 'qr_scanner_screen.dart';
import '../widgets/shared_clipboard_sheet.dart';
import '../widgets/hashing_dialog.dart';
import '../models/transfer_item.dart';

/// Discover nearby devices, pick files, and initiate transfers.
/// Enhanced with file browser integration and explicit Send/Receive modes
/// modeled after the reference repo's WiFi Direct flow.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  DeviceInfo? _selectedDevice;
  List<PlatformFile>? _selectedFiles;
  bool _enableHashing = true;
  bool _isClearing = false;

  void _clearTransfers() async {
    if (_isClearing) return;
    setState(() => _isClearing = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      context.read<AppState>().clearTerminalTransfers();
      setState(() => _isClearing = false);
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Show Manual Connect Dialog ────────────────────────────────────────────

  void _showConnectByIpDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: AppColors.primaryLight.withValues(alpha: 0.2),
            ),
          ),
          title: const Text(
            'Connect Manually',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the IP address of the receiving device (e.g. 172.16.x.x). Use this if UDP discovery is blocked by college routers.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'IP Address',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(
                    Icons.cell_wifi_rounded,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final ip = controller.text.trim();
                if (ip.isNotEmpty) {
                  final state = context.read<AppState>();
                  final manualDevice = DeviceInfo(
                    id: 'manual_$ip',
                    name: 'Device at $ip',
                    ip: ip,
                    port: 53317, // default transfer port
                    platform: 'Unknown',
                  );
                  state.addManualDevice(manualDevice);
                  setState(() {
                    _selectedDevice = manualDevice;
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  // ── File Browser ──────────────────────────────────────────────────────────

  /// Opens the category-based file browser bottom sheet
  /// (modeled after reference repo's Gallery/Music/Video/Files tabs).
  void _openFileBrowser() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InAppFileBrowser(
        onFilesSelected: (files) {
          setState(() => _selectedFiles = files);
        },
      ),
    );
  }

  /// Quick pick via system file picker (legacy support).
  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles = result.files;
        });
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  // ── Send/Receive Actions ──────────────────────────────────────────────────

  Future<void> _sendFiles() async {
    if (_selectedDevice == null ||
        _selectedFiles == null ||
        _selectedFiles!.isEmpty) {
      return;
    }

    final state = context.read<AppState>();
    await state.sendFiles(
      _selectedDevice!,
      _selectedFiles!,
      enableHashing: _enableHashing,
    );
    setState(() {
      _selectedFiles = null;
    });
  }

  Future<void> _sendText() async {
    if (_selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Select a device first'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Send Text',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Type your message...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (text != null && text.trim().isNotEmpty && mounted) {
      final state = context.read<AppState>();
      await state.sendText(_selectedDevice!, text);
    }
  }

  void _shareClipboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SharedClipboardSheet(),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.videocam_rounded;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'flac':
        return Icons.audiotrack_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'apk':
        return Icons.android_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _fileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return const Color(0xFF10B981);
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return const Color(0xFFF59E0B);
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'flac':
        return const Color(0xFF8B5CF6);
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B82F6);
      default:
        return AppColors.textTertiary;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.pendingSharedFiles.isNotEmpty) {
      final newFiles = List<String>.from(state.pendingSharedFiles);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        bool changed = false;
        _selectedFiles ??= [];
        for (final path in newFiles) {
          final file = File(path);
          if (file.existsSync() && !_selectedFiles!.any((f) => f.path == path)) {
            _selectedFiles!.add(PlatformFile(
              path: path,
              name: file.uri.pathSegments.last,
              size: file.lengthSync(),
            ));
            changed = true;
          }
        }
        if (changed) setState(() {});
        context.read<AppState>().consumeSharedFiles();
      });
    }

    return Scaffold(
          body: RefreshIndicator(
            onRefresh: () async {
              await state.refreshDevices();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── App Bar ──────────────────────────────────────────────────
                SliverAppBar(
                  expandedHeight: 120,
                  floating: false,
                  pinned: true,
                  centerTitle: false,
                  backgroundColor: AppColors.background,
                  surfaceTintColor: Colors.transparent,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) =>
                              AppColors.gradientPrimary.createShader(b),
                          child: const Icon(
                            Icons.share_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'ClipLAN',
                          style: Theme.of(
                            context,
                          ).textTheme.headlineMedium?.copyWith(fontSize: 22),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    // Online status badge
                    Container(
                      margin: const EdgeInsets.only(right: 16, top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (state.isDiscovering
                                    ? AppColors.success
                                    : AppColors.error)
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              (state.isDiscovering
                                      ? AppColors.success
                                      : AppColors.error)
                                  .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: state.isDiscovering
                                  ? AppColors.success
                                  : AppColors.error,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (state.isDiscovering
                                              ? AppColors.success
                                              : AppColors.error)
                                          .withValues(alpha: 0.4),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            state.isDiscovering ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: state.isDiscovering
                                  ? AppColors.success
                                  : AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Quick Actions Bar ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildQuickAction(
                          icon: Icons.qr_code_2_rounded,
                          label: 'My QR',
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const QrDisplaySheet(),
                            );
                          },
                        ),
                        _buildQuickAction(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Scan QR',
                          onTap: () async {
                            final device = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QrScannerScreen(),
                              ),
                            );
                            if (device != null && device is DeviceInfo) {
                              setState(() => _selectedDevice = device);
                            }
                          },
                        ),
                        _buildQuickAction(
                          icon: Icons.add_link_rounded,
                          label: 'Connect IP',
                          onTap: _showConnectByIpDialog,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Send / Receive Mode ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _actionCard(
                            icon: Icons.upload_rounded,
                            label: 'Send',
                            subtitle: 'Pick & share files',
                            gradient: AppColors.gradientPrimary,
                            onTap: _openFileBrowser,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _actionCard(
                            icon: Icons.download_rounded,
                            label: 'Receive',
                            subtitle: state.isServerRunning
                                ? 'Ready to receive'
                                : 'Server offline',
                            gradient: AppColors.gradientAccent,
                            onTap: () {
                              if (state.isServerRunning) {
                                // Broadcast a UDP presence burst so nearby devices discover us
                                state.refreshDevices();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Row(
                                      children: [
                                        Icon(
                                          Icons.download_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 10),
                                        Text('App is ready to receive!'),
                                      ],
                                    ),
                                    backgroundColor: AppColors.success,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Transfer server is offline',
                                    ),
                                    backgroundColor: AppColors.error,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
                  ),
                ),

                // ── Active Transfers ─────────────────────────────────────────
                if (state.activeTransfers.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active Transfers',
                                style: Theme.of(context).textTheme.titleLarge,
                              ).animate().fadeIn().slideX(begin: -0.1),
                              TextButton(
                                onPressed: _clearTransfers,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                child: const Text('Clear All'),
                              ).animate().fadeIn().slideX(begin: 0.1),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...state.activeTransfers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final t = entry.value;
                            final isTerminal =
                                t.status == TransferStatus.completed ||
                                t.status == TransferStatus.failed ||
                                t.status == TransferStatus.cancelled;
                            return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Dismissible(
                                    key: Key('transfer_${t.id}'),
                                    direction: isTerminal
                                        ? DismissDirection.horizontal
                                        : DismissDirection.none,
                                    onDismissed: (_) =>
                                        state.dismissTransfer(t.id),
                                    background: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    secondaryBackground: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    child: TransferCard(
                                      transfer: t,
                                      onCancel: () => state.cancelTransfer(t),
                                      onDismiss: () =>
                                          state.dismissTransfer(t.id),
                                    ),
                                  ),
                                )
                                .animate(
                                  target: _isClearing && isTerminal ? 1 : 0,
                                )
                                .slideX(
                                  end: index.isEven ? -1.5 : 1.5,
                                  duration: 400.ms,
                                  curve: Curves.easeInOut,
                                )
                                .fadeOut(duration: 400.ms);
                          }),
                        ],
                      ),
                    ),
                  ),

                // ── Nearby Devices Header ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Nearby Devices',
                          style: Theme.of(context).textTheme.titleLarge,
                        ).animate().fadeIn().slideX(begin: -0.1),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primaryLight.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Text(
                            '${state.devices.length} found',
                            style: const TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Device List / Empty State ────────────────────────────────
                if (state.devices.isEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 280,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 200,
                              height: 200,
                              child: RadarAnimation(),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Scanning for devices...',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: AppColors.textTertiary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Make sure devices are on the same network',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppColors.textTertiary.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontSize: 12,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((_, i) {
                        final dev = state.devices[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child:
                              DeviceTile(
                                    device: dev,
                                    isSelected: _selectedDevice?.id == dev.id,
                                    showIp: state.showDeviceIp,
                                    onTap: () => setState(
                                      () => _selectedDevice =
                                          _selectedDevice?.id == dev.id
                                          ? null
                                          : dev,
                                    ),
                                  )
                                  .animate(
                                    delay: Duration(milliseconds: 80 * i),
                                  )
                                  .fadeIn()
                                  .slideY(begin: 0.15),
                        );
                      }, childCount: state.devices.length),
                    ),
                  ),

                // ── Selected Files Preview ───────────────────────────────────
                if (_selectedFiles != null && _selectedFiles!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: GlassmorphicCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.attach_file_rounded,
                                        color: AppColors.primaryLight,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Selected Files (${_selectedFiles!.length})',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _selectedFiles = null),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  color: AppColors.textTertiary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._selectedFiles!
                                .take(5)
                                .map(
                                  (f) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: _fileColor(
                                              f.name,
                                            ).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            _fileIcon(f.name),
                                            color: _fileColor(f.name),
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            f.name,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          _formatSize(f.size),
                                          style: const TextStyle(
                                            color: AppColors.textTertiary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            if (_selectedFiles!.length > 5)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '+ ${_selectedFiles!.length - 5} more files',
                                  style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            // Total size summary
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total size',
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _formatSize(
                                      _selectedFiles!.fold(
                                        0,
                                        (sum, f) => sum + f.size,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: AppColors.primaryLight,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Checkbox(
                                  value: _enableHashing,
                                  onChanged: (val) {
                                    setState(() {
                                      _enableHashing = val ?? true;
                                    });
                                  },
                                  activeColor: AppColors.primaryLight,
                                  side: const BorderSide(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const Expanded(
                                  child: Text(
                                    'Enable File Hashing (slower, ensures integrity)',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
                    ),
                  ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    child: InkWell(
                      onTap: () async {
                        final String? result =
                            await FilePicker.getDirectoryPath();
                        if (result != null && mounted) {
                          context.read<AppState>().updateSavePath(result);
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.surfaceLight),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.folder_open_rounded,
                                color: AppColors.primaryLight,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Storage Location',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    state.savePath,
                                    style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.edit_rounded,
                              color: AppColors.textTertiary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),

          // ── FABs ───────────────────────────────────────────────────────
          floatingActionButton: _buildFabs(),
        );
  }

  // ── Action Cards (Send / Receive) ─────────────────────────────────────

  Widget _actionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required LinearGradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              gradient.colors.first.withValues(alpha: 0.15),
              gradient.colors.last.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: gradient.colors.first.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: gradient.colors.first.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FABs ──────────────────────────────────────────────────────────────

  Widget _buildFabs() {
    // Ready to send
    if (_selectedDevice != null &&
        _selectedFiles != null &&
        _selectedFiles!.isNotEmpty) {
      return FloatingActionButton.extended(
        heroTag: 'send',
        onPressed: _sendFiles,
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.send_rounded),
        label: const Text(
          'Send',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ).animate().scale(begin: const Offset(0, 0), curve: Curves.elasticOut);
    }

    // Pick files directly
    return FloatingActionButton(
      heroTag: 'files',
      onPressed: _openFileBrowser,
      backgroundColor: AppColors.primaryLight,
      foregroundColor: AppColors.background,
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primaryLight, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
