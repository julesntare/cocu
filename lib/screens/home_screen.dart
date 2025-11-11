import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item.dart';
import '../services/database_service.dart';
import '../widgets/monthly_summary_widget.dart';
import '../theme/app_theme.dart';
import 'add_item_screen.dart';
import 'item_detail_screen.dart';

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
  Map<int, int> _ongoingDaysMap = {}; // Map of item ID to ongoing days
  Map<int, bool> _hasActiveRecordMap =
      {}; // Map of item ID to whether it has active ongoing record
  bool _isLoading = true;
  int _summaryRefreshKey = 0;

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

  void _performSearch(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredItems = _items;
      } else {
        // Filter items while maintaining the ongoing days sort order from _items
        _filteredItems = _items.where((item) {
          final searchLower = query.toLowerCase();
          return item.name.toLowerCase().contains(searchLower) ||
              (item.description?.toLowerCase().contains(searchLower) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final items = await _databaseService.getAllItems();

      // Calculate ongoing days for each item and sort by it
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
          ongoingDays =
              DateTime.now().difference(latestEntry.recordedAt).inDays;
          // Check if the latest entry has no finishedAt (meaning it's still ongoing)
          hasActiveRecord = latestEntry.finishedAt == null;
        }

        return {
          'item': item,
          'ongoingDays': ongoingDays,
          'hasActiveRecord': hasActiveRecord,
        };
      }));

      // Sort by ongoing days (smallest first)
      itemsWithOngoingDays.sort((a, b) =>
          (a['ongoingDays'] as int).compareTo(b['ongoingDays'] as int));

      final sortedItems =
          itemsWithOngoingDays.map((e) => e['item'] as Item).toList();

      // Build the ongoing days map and active record map
      final ongoingDaysMap = <int, int>{};
      final hasActiveRecordMap = <int, bool>{};
      for (var itemData in itemsWithOngoingDays) {
        final item = itemData['item'] as Item;
        final ongoingDays = itemData['ongoingDays'] as int;
        final hasActiveRecord = itemData['hasActiveRecord'] as bool;
        ongoingDaysMap[item.id!] = ongoingDays;
        hasActiveRecordMap[item.id!] = hasActiveRecord;
      }

      setState(() {
        _items = sortedItems;
        _filteredItems = sortedItems;
        _ongoingDaysMap = ongoingDaysMap;
        _hasActiveRecordMap = hasActiveRecordMap;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_authenticated', false);
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
                onSelected: (value) {
                  if (value == 'logout') {
                    _showLogoutDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text('Logout'),
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
                                        // Left colored bar for ongoing items
                                        if (_hasActiveRecordMap[item.id] ==
                                            true)
                                          Container(
                                            width: 4,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              gradient: _getOngoingGradient(),
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
