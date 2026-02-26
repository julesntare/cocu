import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/item.dart';
import '../services/database_service.dart';
import '../widgets/monthly_summary_widget.dart';
import '../theme/app_theme.dart';
import 'add_item_screen.dart';
import 'item_detail_screen.dart';
import 'settings_screen.dart';

enum ItemFilter { all, active, dueSoon, overdue, finished }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  List<Item> _items = [];
  List<Item> _filteredItems = [];
  Map<int, bool> _hasActiveRecordMap =
      {}; // Map of item ID to whether it has active ongoing record
  Map<int, double?> _cycleProgressMap =
      {}; // Map of item ID to purchase cycle progress (0.0–1.0+)
  bool _isLoading = true;
  int _summaryRefreshKey = 0;
  ItemFilter _currentFilter = ItemFilter.all;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      var filtered = _items;

      // Apply search filter
      final query = _searchController.text;
      if (query.trim().isNotEmpty) {
        filtered = filtered.where((item) {
          final searchLower = query.toLowerCase();
          return item.name.toLowerCase().contains(searchLower) ||
              (item.description?.toLowerCase().contains(searchLower) ?? false);
        }).toList();
      }

      // Apply status filter
      switch (_currentFilter) {
        case ItemFilter.active:
          filtered = filtered
              .where((item) => _hasActiveRecordMap[item.id] == true)
              .toList();
          break;
        case ItemFilter.dueSoon:
          filtered = filtered.where((item) {
            final isActive = _hasActiveRecordMap[item.id] == true;
            final progress = _cycleProgressMap[item.id];
            return isActive && progress != null && progress >= 0.9 && progress < 1.0;
          }).toList();
          break;
        case ItemFilter.overdue:
          filtered = filtered.where((item) {
            final isActive = _hasActiveRecordMap[item.id] == true;
            final progress = _cycleProgressMap[item.id];
            return isActive && progress != null && progress >= 1.0;
          }).toList();
          break;
        case ItemFilter.finished:
          filtered = filtered
              .where((item) => _hasActiveRecordMap[item.id] != true)
              .toList();
          break;
        case ItemFilter.all:
          // No additional filtering
          break;
      }

      _filteredItems = filtered;
    });
  }

  void _performSearch(String query) {
    _applyFilters();
  }

  void _changeFilter(ItemFilter filter) {
    setState(() {
      _currentFilter = filter;
    });
    _applyFilters();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final items = await _databaseService.getAllItems();

      // Calculate ongoing days and cycle progress for each item
      final itemsWithOngoingDays = await Future.wait(items.map((item) async {
        final priceHistory = await _databaseService.getPriceHistory(item.id!);
        final manualEntries = priceHistory
            .where((entry) => entry.entryType == 'manual')
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

        int ongoingDays = 0;
        bool hasActiveRecord = false;
        if (manualEntries.isNotEmpty) {
          final latestEntry = manualEntries.last;
          // Calculate days based on calendar date changes, not 24-hour intervals
          final now = DateTime.now();
          final startDate = DateTime(latestEntry.recordedAt.year,
              latestEntry.recordedAt.month, latestEntry.recordedAt.day);
          final currentDate = DateTime(now.year, now.month, now.day);
          ongoingDays = currentDate.difference(startDate).inDays;
          // Check if the latest entry has no finishedAt (meaning it's still ongoing)
          hasActiveRecord = latestEntry.finishedAt == null;
        }

        final cycleProgress =
            await _databaseService.getPurchaseCycleProgress(item.id!);

        return {
          'item': item,
          'ongoingDays': ongoingDays,
          'hasActiveRecord': hasActiveRecord,
          'cycleProgress': cycleProgress,
        };
      }));

      // Sort by ongoing days (smallest first)
      itemsWithOngoingDays.sort((a, b) =>
          (a['ongoingDays'] as int).compareTo(b['ongoingDays'] as int));

      final sortedItems =
          itemsWithOngoingDays.map((e) => e['item'] as Item).toList();

      // Build the ongoing days map, active record map, and cycle progress map
      final ongoingDaysMap = <int, int>{};
      final hasActiveRecordMap = <int, bool>{};
      final cycleProgressMap = <int, double?>{};
      for (var itemData in itemsWithOngoingDays) {
        final item = itemData['item'] as Item;
        final ongoingDays = itemData['ongoingDays'] as int;
        final hasActiveRecord = itemData['hasActiveRecord'] as bool;
        ongoingDaysMap[item.id!] = ongoingDays;
        hasActiveRecordMap[item.id!] = hasActiveRecord;
        cycleProgressMap[item.id!] = itemData['cycleProgress'] as double?;
      }

      setState(() {
        _items = sortedItems;
        _filteredItems = sortedItems;
        _hasActiveRecordMap = hasActiveRecordMap;
        _cycleProgressMap = cycleProgressMap;
        _isLoading = false;
        _summaryRefreshKey++; // Refresh the summary widget
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'is_authenticated', value: 'false');
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  LinearGradient _getOngoingGradient() {
    // Green gradient for fresh items
    return const LinearGradient(
      colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  LinearGradient _getDueSoonGradient() {
    // Amber gradient — approaching the next purchase date (90–99%)
    return const LinearGradient(
      colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  LinearGradient _getOverdueGradient() {
    // Red gradient — past the expected purchase date (100%+)
    return const LinearGradient(
      colors: [Color(0xFFF44336), Color(0xFFEF5350)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Future<void> _deleteItem(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _databaseService.deleteItem(item.id!);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${item.name} deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting item: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
          child: AppBar(
            title: const Text('CoCu'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'logout') {
                    _showLogoutDialog();
                  } else if (value == 'settings') {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                    // Reload data if backup was restored
                    if (result == true) {
                      _loadData();
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings, size: 20),
                        SizedBox(width: 8),
                        Text('Settings & Backup'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 20),
                        SizedBox(width: 8),
                        Text('Logout'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Monthly Summary
          MonthlySummaryWidget(key: ValueKey('summary_$_summaryRefreshKey')),
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or description...',
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: _performSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _currentFilter == ItemFilter.all,
                  onSelected: (selected) {
                    if (selected) _changeFilter(ItemFilter.all);
                  },
                  selectedColor:
                      AppColors.primaryStart.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primaryStart,
                  labelStyle: TextStyle(
                    color: _currentFilter == ItemFilter.all
                        ? AppColors.primaryStart
                        : AppColors.textSecondary,
                    fontWeight: _currentFilter == ItemFilter.all
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Active'),
                  selected: _currentFilter == ItemFilter.active,
                  onSelected: (selected) {
                    if (selected) _changeFilter(ItemFilter.active);
                  },
                  selectedColor:
                      const Color(0xFF4CAF50).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFF4CAF50),
                  avatar: _currentFilter == ItemFilter.active
                      ? null
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                  labelStyle: TextStyle(
                    color: _currentFilter == ItemFilter.active
                        ? const Color(0xFF4CAF50)
                        : AppColors.textSecondary,
                    fontWeight: _currentFilter == ItemFilter.active
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Due Soon'),
                  selected: _currentFilter == ItemFilter.dueSoon,
                  onSelected: (selected) {
                    if (selected) _changeFilter(ItemFilter.dueSoon);
                  },
                  selectedColor:
                      const Color(0xFFFF9800).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFFFF9800),
                  avatar: _currentFilter == ItemFilter.dueSoon
                      ? null
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                  labelStyle: TextStyle(
                    color: _currentFilter == ItemFilter.dueSoon
                        ? const Color(0xFFFF9800)
                        : AppColors.textSecondary,
                    fontWeight: _currentFilter == ItemFilter.dueSoon
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Overdue'),
                  selected: _currentFilter == ItemFilter.overdue,
                  onSelected: (selected) {
                    if (selected) _changeFilter(ItemFilter.overdue);
                  },
                  selectedColor:
                      const Color(0xFFF44336).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFFF44336),
                  avatar: _currentFilter == ItemFilter.overdue
                      ? null
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFF44336), Color(0xFFEF5350)],
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                  labelStyle: TextStyle(
                    color: _currentFilter == ItemFilter.overdue
                        ? const Color(0xFFF44336)
                        : AppColors.textSecondary,
                    fontWeight: _currentFilter == ItemFilter.overdue
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Finished'),
                  selected: _currentFilter == ItemFilter.finished,
                  onSelected: (selected) {
                    if (selected) _changeFilter(ItemFilter.finished);
                  },
                  selectedColor:
                      AppColors.textSecondary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.textSecondary,
                  labelStyle: TextStyle(
                    color: _currentFilter == ItemFilter.finished
                        ? AppColors.textSecondary
                        : AppColors.textSecondary,
                    fontWeight: _currentFilter == ItemFilter.finished
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          // Items list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No items yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Add your first item to start tracking prices',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : _filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No items found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try searching with different keywords',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              final isActive =
                                  _hasActiveRecordMap[item.id] == true;
                              final progress = _cycleProgressMap[item.id];
                              final isOverdue = isActive &&
                                  progress != null &&
                                  progress >= 1.0;
                              final isDueSoon = isActive &&
                                  !isOverdue &&
                                  progress != null &&
                                  progress >= 0.9;

                              LinearGradient? barGradient;
                              if (isOverdue) {
                                barGradient = _getOverdueGradient();
                              } else if (isDueSoon) {
                                barGradient = _getDueSoonGradient();
                              } else if (isActive) {
                                barGradient = _getOngoingGradient();
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryStart
                                          .withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ItemDetailScreen(item: item),
                                        ),
                                      ).then((_) => _loadData());
                                    },
                                    onLongPress: () => _deleteItem(item),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Row(
                                      children: [
                                        // Left colored bar: green = active,
                                        // amber = due soon (≥90%), red = overdue (≥100%)
                                        if (barGradient != null)
                                          Container(
                                            width: 4,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              gradient: barGradient,
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                bottomLeft: Radius.circular(16),
                                              ),
                                            ),
                                          ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                          color: AppColors
                                                              .textPrimary,
                                                          letterSpacing: 0.1,
                                                        ),
                                                      ),
                                                      if (item.description !=
                                                          null) ...[
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          item.description!,
                                                          style:
                                                              const TextStyle(
                                                            color: AppColors
                                                                .textSecondary,
                                                            fontSize: 12,
                                                            height: 1.3,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                if (isOverdue)
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                        right: 4),
                                                    child: Icon(
                                                      Icons.error_outline_rounded,
                                                      size: 16,
                                                      color: Color(0xFFF44336),
                                                    ),
                                                  )
                                                else if (isDueSoon)
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                        right: 4),
                                                    child: Icon(
                                                      Icons.warning_amber_rounded,
                                                      size: 16,
                                                      color: Color(0xFFFF9800),
                                                    ),
                                                  ),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: AppColors.textLight,
                                                  size: 24,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentStart.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddItemScreen()),
            ).then((_) => _loadData());
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, size: 32, color: Colors.white),
        ),
      ),
    );
  }
}
