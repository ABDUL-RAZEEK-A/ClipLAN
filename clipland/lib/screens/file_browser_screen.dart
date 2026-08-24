import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../providers/app_state.dart';
import '../models/transfer_item.dart';
import '../theme/app_theme.dart';

enum FileCategory {
  recents,
  images,
  videos,
  audio,
  documents,
  apks,
  installedApps,
  all,
}

enum SortOption { nameAsc, nameDesc, sizeAsc, sizeDesc, dateDesc, dateAsc }

// A simple model to hold file data from the isolate without passing File objects
// which might have issues across isolate boundaries in older Dart versions (though usually fine now)
class ScannedFile {
  final String path;
  final String name;
  final int size;
  final int modifiedMs;
  final Uint8List? appIcon;

  ScannedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedMs,
    this.appIcon,
  });
}

class ScanResult {
  final List<ScannedFile> images;
  final List<ScannedFile> videos;
  final List<ScannedFile> audio;
  final List<ScannedFile> documents;
  final List<ScannedFile> apks;

  ScanResult({
    required this.images,
    required this.videos,
    required this.audio,
    required this.documents,
    required this.apks,
  });
}

// Background isolate scanner
ScanResult _scanDirectoriesBackground(List<String> roots) {
  final images = <ScannedFile>[];
  final videos = <ScannedFile>[];
  final audio = <ScannedFile>[];
  final documents = <ScannedFile>[];
  final apks = <ScannedFile>[];

  final imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};
  final videoExts = {'.mp4', '.mkv', '.avi', '.mov', '.webm'};
  final audioExts = {'.mp3', '.m4a', '.wav', '.aac', '.ogg'};
  final docExts = {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.txt',
  };
  final apkExts = {'.apk'};

  for (final rootPath in roots) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) continue;

    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path;
          // Skip hidden files/folders
          if (path.contains('/.')) continue;

          final lowerPath = path.toLowerCase();
          final ext = lowerPath.substring(
            lowerPath.lastIndexOf('.').clamp(0, lowerPath.length),
          );

          if (imageExts.contains(ext) ||
              videoExts.contains(ext) ||
              audioExts.contains(ext) ||
              docExts.contains(ext) ||
              apkExts.contains(ext)) {
            try {
              final stat = entity.statSync();
              final sf = ScannedFile(
                path: path,
                name: path.split(Platform.pathSeparator).last,
                size: stat.size,
                modifiedMs: stat.modified.millisecondsSinceEpoch,
              );

              if (imageExts.contains(ext))
                images.add(sf);
              else if (videoExts.contains(ext))
                videos.add(sf);
              else if (audioExts.contains(ext))
                audio.add(sf);
              else if (docExts.contains(ext))
                documents.add(sf);
              else if (apkExts.contains(ext))
                apks.add(sf);
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Ignore directories we can't access
    }
  }

  return ScanResult(
    images: images,
    videos: videos,
    audio: audio,
    documents: documents,
    apks: apks,
  );
}

class InAppFileBrowser extends StatefulWidget {
  final ValueChanged<List<PlatformFile>> onFilesSelected;

  const InAppFileBrowser({super.key, required this.onFilesSelected});

  @override
  State<InAppFileBrowser> createState() => _InAppFileBrowserState();
}

class _InAppFileBrowserState extends State<InAppFileBrowser> {
  // Navigation & State
  Directory? _currentDir;
  Directory? _trueRootDir;
  List<FileSystemEntity> _currentDirEntities = [];
  final List<File> _selectedFiles = [];
  bool _isLoading = true;
  bool _isScanning = false;
  bool _hasPermission = false;

  // Categories & Search
  FileCategory _currentCategory = FileCategory.all;
  SortOption _currentSort = SortOption.nameAsc;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isGridView = false;

  // Cached Scanned Data
  ScanResult? _scanResult;
  List<ScannedFile> _activeCategoryFiles = [];

  @override
  void initState() {
    super.initState();
    _initBrowser();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initBrowser() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    }

    _hasPermission = true;

    Directory? rootDir;
    List<String> scanRoots = [];

    if (Platform.isAndroid) {
      rootDir = Directory('/storage/emulated/0');
      if (!rootDir.existsSync()) {
        rootDir = await getExternalStorageDirectory();
      }
      scanRoots = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media', // WhatsApp media
      ];
    } else {
      final homePath =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (homePath != null) {
        rootDir = Directory(homePath);
      } else {
        rootDir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }
      scanRoots = [rootDir!.path];
    }

    if (rootDir != null) {
      _trueRootDir = rootDir;
      _navigateTo(rootDir);
    } else {
      setState(() => _isLoading = false);
    }

    // Start background scan for categories
    _startBackgroundScan(scanRoots);
  }

  Future<void> _startBackgroundScan(List<String> roots) async {
    setState(() => _isScanning = true);
    try {
      final result = await compute(_scanDirectoriesBackground, roots);
      if (mounted) {
        setState(() {
          _scanResult = result;
          _isScanning = false;
          _updateActiveCategoryList();
        });
      }
    } catch (e) {
      debugPrint('[InAppBrowser] Scan error: $e');
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _navigateTo(Directory dir) {
    setState(() {
      _isLoading = true;
      _currentDir = dir;
      _currentCategory = FileCategory.all;
      _searchQuery = '';
      _searchController.clear();
    });

    try {
      final entities = dir.listSync().where((e) {
        final name = e.path.split(Platform.pathSeparator).last;
        return !name.startsWith('.');
      }).toList();

      setState(() {
        _currentDirEntities = entities;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[InAppBrowser] Error reading directory: $e');
      setState(() => _isLoading = false);
    }
  }

  void _goUp() {
    if (_currentDir != null && _currentCategory == FileCategory.all) {
      final parent = _currentDir!.parent;
      if (parent.path != _currentDir!.path) {
        _navigateTo(parent);
      }
    }
  }

  void _goHome() {
    if (_trueRootDir != null) {
      _navigateTo(_trueRootDir!);
    }
  }

  Future<void> _refreshDirectory() async {
    if (_currentCategory == FileCategory.all && _currentDir != null) {
      _navigateTo(_currentDir!); // This synchronously updates the list
    }

    // Trigger a new background scan to refresh media categories
    List<String> roots = [];
    if (Platform.isAndroid) {
      roots = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Documents',
      ];
    } else if (_trueRootDir != null) {
      roots = [_trueRootDir!.path];
    }

    if (roots.isNotEmpty) {
      await _startBackgroundScan(roots);
    }
  }

  void _setCategory(FileCategory category) {
    setState(() {
      _currentCategory = category;
      _searchQuery = '';
      _searchController.clear();
      _updateActiveCategoryList();
    });
  }

  void _loadRecents() {
    final appState = Provider.of<AppState>(context, listen: false);
    final Set<String> uniquePaths = {};
    final recents = <ScannedFile>[];

    for (var transfer in appState.history) {
      if (transfer.direction == TransferDirection.sending) {
        for (var file in transfer.files) {
          if (file.path != null && !uniquePaths.contains(file.path)) {
            uniquePaths.add(file.path!);
            try {
              final stat = File(file.path!).statSync();
              if (stat.type != FileSystemEntityType.notFound) {
                recents.add(
                  ScannedFile(
                    path: file.path!,
                    name: file.name,
                    size: file.size,
                    modifiedMs: transfer.startTime.millisecondsSinceEpoch,
                  ),
                );
              }
            } catch (_) {}
          }
        }
      }
    }

    recents.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
    _activeCategoryFiles = recents;
  }

  void _updateActiveCategoryList() {
    if (_scanResult == null &&
        _currentCategory != FileCategory.recents &&
        _currentCategory != FileCategory.installedApps)
      return;
    switch (_currentCategory) {
      case FileCategory.recents:
        _loadRecents();
        break;
      case FileCategory.images:
        _activeCategoryFiles = _scanResult!.images;
        break;
      case FileCategory.videos:
        _activeCategoryFiles = _scanResult!.videos;
        break;
      case FileCategory.audio:
        _activeCategoryFiles = _scanResult!.audio;
        break;
      case FileCategory.documents:
        _activeCategoryFiles = _scanResult!.documents;
        break;
      case FileCategory.apks:
        _activeCategoryFiles = _scanResult!.apks;
        break;
      case FileCategory.installedApps:
        _activeCategoryFiles = [];
        _loadInstalledApps();
        break;
      case FileCategory.all:
        _activeCategoryFiles = [];
        break;
    }
  }

  static const _apkChannel = MethodChannel('com.cliplan/apkPaths');

  Future<void> _loadInstalledApps() async {
    setState(() => _isLoading = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);

      Map<dynamic, dynamic> pathsMap = {};
      if (Platform.isAndroid) {
        pathsMap = await _apkChannel.invokeMethod('getApkPaths');
      }

      final List<ScannedFile> appFiles = [];
      for (final app in apps) {
        final apkPath = pathsMap[app.packageName];
        if (apkPath != null) {
          int size = 0;
          try {
            size = File(apkPath).lengthSync();
          } catch (_) {}
          appFiles.add(
            ScannedFile(
              path: apkPath,
              name: '${app.name ?? "UnknownApp"}.apk',
              size: size,
              modifiedMs: DateTime.now().millisecondsSinceEpoch,
              appIcon: app.icon,
            ),
          );
        }
      }
      appFiles.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted && _currentCategory == FileCategory.installedApps) {
        setState(() {
          _activeCategoryFiles = appFiles;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedFiles.any((f) => f.path == path)) {
        _selectedFiles.removeWhere((f) => f.path == path);
      } else {
        _selectedFiles.add(File(path));
      }
    });
  }

  void _confirmSelection() {
    if (_selectedFiles.isNotEmpty) {
      final platformFiles = _selectedFiles.map((f) {
        return PlatformFile(
          name: f.path.split(Platform.pathSeparator).last,
          size: f.lengthSync(),
          path: f.path,
        );
      }).toList();
      widget.onFilesSelected(platformFiles);
      Navigator.pop(context);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int get _totalSize {
    int sum = 0;
    for (var f in _selectedFiles) {
      try {
        sum += f.lengthSync();
      } catch (_) {}
    }
    return sum;
  }

  // --- Filter and Sort Logic ---

  List<dynamic> _getFilteredAndSortedItems() {
    List<dynamic> items = [];

    if (_currentCategory == FileCategory.all) {
      items = List<FileSystemEntity>.from(_currentDirEntities);

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        items = items.where((e) {
          final name = e.path.split(Platform.pathSeparator).last.toLowerCase();
          return name.contains(query);
        }).toList();
      }

      // Sort
      items.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1; // folders always first
        if (!aIsDir && bIsDir) return 1;

        final nameA = a.path.split(Platform.pathSeparator).last;
        final nameB = b.path.split(Platform.pathSeparator).last;

        if (_currentSort == SortOption.nameAsc) return nameA.compareTo(nameB);
        if (_currentSort == SortOption.nameDesc) return nameB.compareTo(nameA);

        try {
          final statA = a.statSync();
          final statB = b.statSync();
          if (_currentSort == SortOption.sizeDesc)
            return statB.size.compareTo(statA.size);
          if (_currentSort == SortOption.sizeAsc)
            return statA.size.compareTo(statB.size);
          if (_currentSort == SortOption.dateDesc)
            return statB.modified.compareTo(statA.modified);
          if (_currentSort == SortOption.dateAsc)
            return statA.modified.compareTo(statB.modified);
        } catch (_) {}
        return 0;
      });
    } else {
      items = List<ScannedFile>.from(_activeCategoryFiles);

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        items = items
            .where((e) => e.name.toLowerCase().contains(query))
            .toList();
      }

      // Sort
      items.sort((a, b) {
        a as ScannedFile;
        b as ScannedFile;
        switch (_currentSort) {
          case SortOption.nameAsc:
            return a.name.compareTo(b.name);
          case SortOption.nameDesc:
            return b.name.compareTo(a.name);
          case SortOption.sizeDesc:
            return b.size.compareTo(a.size);
          case SortOption.sizeAsc:
            return a.size.compareTo(b.size);
          case SortOption.dateDesc:
            return b.modifiedMs.compareTo(a.modifiedMs);
          case SortOption.dateAsc:
            return a.modifiedMs.compareTo(b.modifiedMs);
        }
      });
    }

    return items;
  }

  // --- UI Builders ---

  Widget _buildCategoryTabs() {
    final categories = [
      {
        'val': FileCategory.recents,
        'label': 'Recents',
        'icon': Icons.history_rounded,
      },
      {
        'val': FileCategory.all,
        'label': 'All Files',
        'icon': Icons.folder_rounded,
      },
      {
        'val': FileCategory.images,
        'label': 'Images',
        'icon': Icons.image_rounded,
      },
      {
        'val': FileCategory.videos,
        'label': 'Videos',
        'icon': Icons.videocam_rounded,
      },
      {
        'val': FileCategory.audio,
        'label': 'Audio',
        'icon': Icons.audiotrack_rounded,
      },
      {
        'val': FileCategory.documents,
        'label': 'Docs',
        'icon': Icons.description_rounded,
      },
      {
        'val': FileCategory.apks,
        'label': 'APKs',
        'icon': Icons.android_rounded,
      },
      {
        'val': FileCategory.installedApps,
        'label': 'Apps',
        'icon': Icons.apps_rounded,
      },
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _currentCategory == cat['val'];

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                children: [
                  Icon(
                    cat['icon'] as IconData,
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.primaryLight,
                  ),
                  const SizedBox(width: 6),
                  Text(cat['label'] as String),
                ],
              ),
              selected: isSelected,
              onSelected: (val) {
                if (val) _setCategory(cat['val'] as FileCategory);
              },
              selectedColor: AppColors.primaryLight,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(
                color: isSelected ? Colors.transparent : AppColors.divider,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<SortOption>(
      icon: const Icon(Icons.sort_rounded, color: AppColors.textPrimary),
      onSelected: (val) => setState(() => _currentSort = val),
      itemBuilder: (context) => const [
        PopupMenuItem(value: SortOption.nameAsc, child: Text('Name (A-Z)')),
        PopupMenuItem(value: SortOption.nameDesc, child: Text('Name (Z-A)')),
        PopupMenuItem(
          value: SortOption.sizeDesc,
          child: Text('Size (Largest)'),
        ),
        PopupMenuItem(
          value: SortOption.sizeAsc,
          child: Text('Size (Smallest)'),
        ),
        PopupMenuItem(value: SortOption.dateDesc, child: Text('Date (Newest)')),
        PopupMenuItem(value: SortOption.dateAsc, child: Text('Date (Oldest)')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _getFilteredAndSortedItems();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                if (_currentCategory == FileCategory.all) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: _goUp,
                    tooltip: 'Back',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.home_rounded,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: _goHome,
                    tooltip: 'Home',
                  ),
                ],
                Expanded(
                  child: Text(
                    _currentCategory == FileCategory.all
                        ? (_currentDir?.path
                                  .split(Platform.pathSeparator)
                                  .last ??
                              'Files')
                        : 'Categorized Files',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isGridView
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
                _buildSortMenu(),
                if (_selectedFiles.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedFiles.clear()),
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
              ],
            ),
          ),

          // Categories
          _buildCategoryTabs(),
          const SizedBox(height: 8),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textTertiary,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textTertiary,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Breadcrumb (Only in All Files)
          if (_currentCategory == FileCategory.all && _currentDir != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _currentDir!.path,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          const SizedBox(height: 8),
          const Divider(color: AppColors.divider, height: 1),

          // Scanning Indicator
          if (_isScanning &&
              _currentCategory != FileCategory.all &&
              _scanResult == null)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryLight),
                    SizedBox(height: 16),
                    Text(
                      'Scanning device for media...',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

          // File List
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryLight,
              onRefresh: _refreshDirectory,
              child: _isLoading && _currentCategory == FileCategory.all
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryLight,
                      ),
                    )
                  : !_hasPermission
                  ? const Center(
                      child: Text(
                        'Storage permission required',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: AppColors.textTertiary.withOpacity(
                                    0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No files found for "$_searchQuery"'
                                      : 'No files available',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _isGridView
                  ? GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        _selectedFiles.isNotEmpty ? 100 : 16,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildGridItem(items[index]),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        0,
                        8,
                        0,
                        _selectedFiles.isNotEmpty ? 100 : 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildListItem(items[index]),
                    ),
            ),
          ),

          // Bottom Actions
          if (_selectedFiles.isNotEmpty)
            Container(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedFiles.length} files selected\nTotal: ${_formatSize(_totalSize)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _confirmSelection,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Select'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().slideY(
              begin: 1.0,
              duration: 200.ms,
              curve: Curves.easeOut,
            ),
        ],
      ),
    );
  }

  // --- Extracted Builders ---

  Map<String, dynamic> _extractItemData(dynamic item) {
    bool isDir = false;
    String path = '';
    String name = '';
    int size = 0;
    int dateMs = 0;
    Uint8List? appIcon;

    if (item is FileSystemEntity) {
      isDir = item is Directory;
      path = item.path;
      name = item.path.split(Platform.pathSeparator).last;
      if (!isDir) {
        try {
          final stat = item.statSync();
          size = stat.size;
          dateMs = stat.modified.millisecondsSinceEpoch;
        } catch (_) {}
      }
    } else if (item is ScannedFile) {
      isDir = false;
      path = item.path;
      name = item.name;
      size = item.size;
      dateMs = item.modifiedMs;
      appIcon = item.appIcon;
    }

    final isSelected = !isDir && _selectedFiles.any((f) => f.path == path);

    IconData fileIcon = Icons.insert_drive_file_rounded;
    Color iconColor = AppColors.primaryLight;
    bool isImage = false;

    if (isDir) {
      fileIcon = Icons.folder_rounded;
      iconColor = Colors.amber;
    } else {
      final ext = name.toLowerCase();
      if (ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.png') ||
          ext.endsWith('.webp') ||
          ext.endsWith('.gif')) {
        fileIcon = Icons.image_rounded;
        isImage = true;
      } else if (ext.endsWith('.mp4') ||
          ext.endsWith('.mkv') ||
          ext.endsWith('.mov')) {
        fileIcon = Icons.videocam_rounded;
      } else if (ext.endsWith('.mp3') ||
          ext.endsWith('.wav') ||
          ext.endsWith('.m4a')) {
        fileIcon = Icons.audiotrack_rounded;
      } else if (ext.endsWith('.pdf')) {
        fileIcon = Icons.picture_as_pdf_rounded;
      } else if (ext.endsWith('.apk')) {
        fileIcon = Icons.android_rounded;
      }
    }

    return {
      'isDir': isDir,
      'path': path,
      'name': name,
      'size': size,
      'dateMs': dateMs,
      'isSelected': isSelected,
      'fileIcon': fileIcon,
      'iconColor': iconColor,
      'isImage': isImage,
      'appIcon': appIcon,
      'originalItem': item,
    };
  }

  Widget _buildThumbnail(Map<String, dynamic> data, {double size = 48}) {
    if (data['appIcon'] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          data['appIcon'],
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (data['isImage']) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(data['path']),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            data['fileIcon'],
            color: data['iconColor'],
            size: size * 0.7,
          ),
        ),
      );
    }
    return Icon(data['fileIcon'], color: data['iconColor'], size: size * 0.7);
  }

  Widget _buildListItem(dynamic item) {
    final data = _extractItemData(item);

    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: _buildThumbnail(data, size: 40)),
      ),
      title: Text(
        data['name'],
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: data['isDir'] ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: !data['isDir']
          ? Text(
              '${_formatSize(data['size'])} • ${DateTime.fromMillisecondsSinceEpoch(data['dateMs']).toString().split('.').first}',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            )
          : null,
      trailing: !data['isDir']
          ? Icon(
              data['isSelected']
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: data['isSelected']
                  ? AppColors.primaryLight
                  : AppColors.divider,
            )
          : const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
      onTap: () {
        if (data['isDir']) {
          _navigateTo(data['originalItem'] as Directory);
        } else {
          _toggleSelection(data['path']);
        }
      },
    );
  }

  Widget _buildGridItem(dynamic item) {
    final data = _extractItemData(item);

    return GestureDetector(
      onTap: () {
        if (data['isDir']) {
          _navigateTo(data['originalItem'] as Directory);
        } else {
          _toggleSelection(data['path']);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: data['isSelected']
                ? AppColors.primaryLight
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(child: _buildThumbnail(data, size: 80)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          data['name'],
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: data['isDir']
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!data['isDir']) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatSize(data['size']),
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (!data['isDir'])
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  data['isSelected']
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: data['isSelected']
                      ? AppColors.primaryLight
                      : AppColors.divider.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
