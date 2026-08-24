import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/clipboard_item.dart';
import '../theme/app_theme.dart';
import '../widgets/glassmorphic_card.dart';

/// Dedicated Clipboard Page with "My Clipboard" and "Shared Clipboard" windows.
class ClipboardScreen extends StatefulWidget {
  const ClipboardScreen({super.key});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      setState(() {});
    });
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Add/Edit Dialog ───────────────────────────────────────────────────────

  void _showAddEditDialog(BuildContext context, {ClipboardItem? existing}) {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    final isEditing = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (b) => AppColors.gradientPrimary.createShader(b),
              child: Icon(
                isEditing ? Icons.edit_note_rounded : Icons.add_task_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              isEditing ? 'Edit Snippet' : 'Add to My Clipboard',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: textCtrl,
          maxLines: 6,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Type or paste your text here...',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final text = textCtrl.text.trim();
              if (text.isNotEmpty) {
                final state = context.read<AppState>();
                if (isEditing) {
                  state.updateMyClipboardItem(existing.id, text);
                } else {
                  state.addMyClipboardText(text);
                }
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isEditing ? 'Save Changes' : 'Add Snippet'),
          ),
        ],
      ),
    );
  }

  // ── Share Snippet Dialog ──────────────────────────────────────────────────

  void _showShareOptionsDialog(BuildContext context, String text) {
    final state = context.read<AppState>();
    final devices = state.devices;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share Clipboard Snippet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select how you want to share this text:',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: AppColors.primaryLight,
                ),
              ),
              title: const Text(
                'Broadcast to All Nearby Devices',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Sends to all devices listening on local network',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                state.broadcastClipboard(text);
              },
            ),
            if (devices.isNotEmpty) ...[
              const Divider(color: AppColors.divider, height: 24),
              const Text(
                'Send to Specific Device:',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...devices.map(
                (device) => ListTile(
                  leading: const Icon(
                    Icons.devices_rounded,
                    color: AppColors.primaryLight,
                  ),
                  title: Text(
                    device.name,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    device.ip,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    state.sendText(device, text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sent snippet to ${device.name}'),
                        backgroundColor: const Color(0xFF1F2937),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final myItems = state.myClipboard.where((item) {
          if (_searchQuery.isEmpty) return true;
          return item.text.toLowerCase().contains(_searchQuery);
        }).toList();

        final sharedItems = state.sharedClipboards;

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                expandedHeight: 110,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  title: Text(
                    'Clipboard',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 22),
                  ),
                ),
                actions: const [],
              ),

              // Tab Bar Header
              SliverPersistentHeader(
                pinned: true,
                delegate: _ClipboardTabBarDelegate(
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: AppColors.primaryLight,
                    unselectedLabelColor: AppColors.textTertiary,
                    indicatorColor: AppColors.primaryLight,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_special_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text('My Clipboard (${state.myClipboard.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.share_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text('Shared (${sharedItems.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabCtrl,
              children: [
                // ── Tab 1: My Clipboard ───────────────────────────────────────
                _buildMyClipboardTab(context, state, myItems),

                // ── Tab 2: Shared Clipboard ───────────────────────────────────
                _buildSharedTab(context, state, sharedItems),
              ],
            ),
          ),
          floatingActionButton: _tabCtrl.index == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddEditDialog(context),
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Add Snippet',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ── Tab 1: My Clipboard ───────────────────────────────────────────────────

  Widget _buildMyClipboardTab(
    BuildContext context,
    AppState state,
    List<ClipboardItem> items,
  ) {
    if (state.myClipboard.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  size: 48,
                  color: AppColors.primaryLight,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'My Clipboard is Empty',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Store your custom text snippets permanently in the app.\nYou can copy, edit, or share them anytime!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showAddEditDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add Your First Snippet'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Search bar
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search my snippets...',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.textTertiary,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => _searchCtrl.clear(),
                  )
                : null,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No matching snippets found',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassmorphicCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: Badge & Timestamp
                    Row(
                      children: [
                        if (item.isShared)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.call_received_rounded,
                                  size: 12,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.senderName != null
                                      ? 'From ${item.senderName}'
                                      : 'Received',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Personal Snippet',
                              style: TextStyle(
                                color: AppColors.primaryLight,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d, h:mm a').format(item.createdAt),
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Text Content
                    SelectableText(
                      item.text,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action Toolbar
                    Row(
                      children: [
                        Text(
                          '${item.text.length} chars',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),

                        // Copy Button
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          color: AppColors.primaryLight,
                          tooltip: 'Copy to Clipboard',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: item.text),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Copied to Clipboard!'),
                                backgroundColor: const Color(0xFF1F2937),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                        ),

                        // Share Button
                        IconButton(
                          icon: const Icon(Icons.share_rounded, size: 18),
                          color: AppColors.accent,
                          tooltip: 'Share Snippet',
                          onPressed: () =>
                              _showShareOptionsDialog(context, item.text),
                        ),

                        // Edit Button
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: AppColors.textSecondary,
                          tooltip: 'Edit Snippet',
                          onPressed: () =>
                              _showAddEditDialog(context, existing: item),
                        ),

                        // Delete Button (Owner control)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          color: AppColors.error,
                          tooltip: 'Delete Snippet',
                          onPressed: () {
                            state.deleteMyClipboardItem(item.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Deleted snippet'),
                                backgroundColor: const Color(0xFF1F2937),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ── Tab 2: Shared Clipboard ───────────────────────────────────────────────

  Widget _buildSharedTab(
    BuildContext context,
    AppState state,
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  size: 48,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Shared Clipboards',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Text snippets shared by nearby devices on your local network will appear here.\nYou can accept any shared snippet to save it to your clipboard!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final text = item['text'] as String? ?? '';
        final senderName =
            item['deviceName'] as String? ??
            item['senderName'] as String? ??
            'Nearby Device';
        final timestamp = item['timestamp'] != null
            ? DateTime.parse(item['timestamp'].toString())
            : DateTime.now();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassmorphicCard(
            borderColor: AppColors.accent.withValues(alpha: 0.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender Info Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.devices_rounded,
                        size: 16,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      senderName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('h:mm a').format(timestamp),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Content
                SelectableText(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Actions: Accept to My Clipboard, Copy, Dismiss
                Row(
                  children: [
                    // Accept Button
                    ElevatedButton.icon(
                      onPressed: () {
                        state.acceptSharedClipboard(item);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.playlist_add_rounded, size: 16),
                      label: const Text(
                        'Accept to My Clipboard',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Copy
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      color: AppColors.primaryLight,
                      tooltip: 'Copy to Clipboard',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Copied to Clipboard!'),
                            backgroundColor: const Color(0xFF1F2937),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),

                    // Dismiss
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textTertiary,
                      tooltip: 'Dismiss',
                      onPressed: () => state.dismissSharedClipboard(index),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClipboardTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _ClipboardTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height + 10;
  @override
  double get maxExtent => _tabBar.preferredSize.height + 10;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
          ),
        ),
        child: _tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_ClipboardTabBarDelegate oldDelegate) {
    return false;
  }
}
