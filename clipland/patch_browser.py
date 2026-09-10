import re

with open('lib/screens/file_browser_screen.dart', 'r') as f:
    content = f.read()

# 1. Update ScannedFile
content = content.replace('''class ScannedFile {
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
}''', '''class ScannedFile {
  final String path;
  final String name;
  final int size;
  final int modifiedMs;
  final Uint8List? appIcon;
  final bool isDir;

  ScannedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedMs,
    this.appIcon,
    this.isDir = false,
  });
}''')

# 2. Variable declarations
content = content.replace(
'''  Directory? _trueRootDir;
  List<FileSystemEntity> _currentDirEntities = [];
  final List<File> _selectedFiles = [];''',
'''  Directory? _trueRootDir;
  List<ScannedFile> _currentDirEntities = [];
  final List<ScannedFile> _selectedFiles = [];'''
)

# 3. _navigateTo
content = content.replace(
'''  void _navigateTo(Directory dir) {
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
  }''',
'''  Future<void> _navigateTo(Directory dir) async {
    setState(() {
      _isLoading = true;
      _currentDir = dir;
      _currentCategory = FileCategory.all;
      _searchQuery = '';
      _searchController.clear();
    });

    try {
      final entities = await dir.list().where((e) {
        final name = e.path.split(Platform.pathSeparator).last;
        return !name.startsWith('.');
      }).toList();

      final scanned = <ScannedFile>[];
      for (final e in entities) {
        try {
          final stat = await e.stat();
          scanned.add(ScannedFile(
            path: e.path,
            name: e.path.split(Platform.pathSeparator).last,
            size: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            isDir: e is Directory,
          ));
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _currentDirEntities = scanned;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[InAppBrowser] Error reading directory: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }'''
)

# 4. _loadRecents
content = content.replace(
'''  void _loadRecents() {
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
  }''',
'''  Future<void> _loadRecents() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final Set<String> uniquePaths = {};
    final recents = <ScannedFile>[];

    for (var transfer in appState.history) {
      if (transfer.direction == TransferDirection.sending) {
        for (var file in transfer.files) {
          if (file.path != null && !uniquePaths.contains(file.path)) {
            uniquePaths.add(file.path!);
            try {
              final f = File(file.path!);
              if (await f.exists()) {
                final stat = await f.stat();
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
    if (mounted) {
      setState(() {
        _activeCategoryFiles = recents;
      });
    }
  }'''
)

# 5. _updateActiveCategoryList call
content = content.replace(
'''      case FileCategory.recents:
        _loadRecents();
        break;''',
'''      case FileCategory.recents:
        _loadRecents();
        break;'''
)

# 6. _toggleSelection
content = content.replace(
'''  void _toggleSelection(String path) {
    setState(() {
      if (_selectedFiles.any((f) => f.path == path)) {
        _selectedFiles.removeWhere((f) => f.path == path);
      } else {
        _selectedFiles.add(File(path));
      }
    });
  }''',
'''  void _toggleSelection(ScannedFile file) {
    setState(() {
      if (_selectedFiles.any((f) => f.path == file.path)) {
        _selectedFiles.removeWhere((f) => f.path == file.path);
      } else {
        _selectedFiles.add(file);
      }
    });
  }'''
)

# 7. _confirmSelection
content = content.replace(
'''  void _confirmSelection() {
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
  }''',
'''  void _confirmSelection() {
    if (_selectedFiles.isNotEmpty) {
      final platformFiles = _selectedFiles.map((f) {
        return PlatformFile(
          name: f.name,
          size: f.size,
          path: f.path,
        );
      }).toList();
      widget.onFilesSelected(platformFiles);
      Navigator.pop(context);
    }
  }'''
)

# 8. _totalSize
content = content.replace(
'''  int get _totalSize {
    int sum = 0;
    for (var f in _selectedFiles) {
      try {
        sum += f.lengthSync();
      } catch (_) {}
    }
    return sum;
  }''',
'''  int get _totalSize {
    int sum = 0;
    for (var f in _selectedFiles) {
      sum += f.size;
    }
    return sum;
  }'''
)

# 9. _getFilteredAndSortedItems
content = content.replace(
'''  List<dynamic> _getFilteredAndSortedItems() {
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
          if (_currentSort == SortOption.sizeDesc) {
            return statB.size.compareTo(statA.size);
          }
          if (_currentSort == SortOption.sizeAsc) {
            return statA.size.compareTo(statB.size);
          }
          if (_currentSort == SortOption.dateDesc) {
            return statB.modified.compareTo(statA.modified);
          }
          if (_currentSort == SortOption.dateAsc) {
            return statA.modified.compareTo(statB.modified);
          }
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
  }''',
'''  List<ScannedFile> _getFilteredAndSortedItems() {
    List<ScannedFile> items;

    if (_currentCategory == FileCategory.all) {
      items = List<ScannedFile>.from(_currentDirEntities);
    } else {
      items = List<ScannedFile>.from(_activeCategoryFiles);
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      items = items.where((e) {
        return e.name.toLowerCase().contains(query);
      }).toList();
    }

    // Sort
    items.sort((a, b) {
      if (a.isDir && !b.isDir) return -1; // folders always first
      if (!a.isDir && b.isDir) return 1;

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

    return items;
  }'''
)

# 10. _extractItemData
content = content.replace(
'''  Map<String, dynamic> _extractItemData(dynamic item) {
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
    }''',
'''  Map<String, dynamic> _extractItemData(dynamic item) {
    bool isDir = false;
    String path = '';
    String name = '';
    int size = 0;
    int dateMs = 0;
    Uint8List? appIcon;

    if (item is ScannedFile) {
      isDir = item.isDir;
      path = item.path;
      name = item.name;
      size = item.size;
      dateMs = item.modifiedMs;
      appIcon = item.appIcon;
    }'''
)

# 11. onTap replace `data['originalItem'] as Directory` to `Directory(data['path'])`
content = content.replace(
'''        if (data['isDir']) {
          _navigateTo(data['originalItem'] as Directory);
        } else {
          _toggleSelection(data['path']);
        }''',
'''        if (data['isDir']) {
          _navigateTo(Directory(data['path']));
        } else {
          _toggleSelection(data['originalItem'] as ScannedFile);
        }'''
)

with open('lib/screens/file_browser_screen.dart', 'w') as f:
    f.write(content)
