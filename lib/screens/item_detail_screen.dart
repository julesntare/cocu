import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/item.dart';
import '../models/sub_item.dart';
import '../models/price_history.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'add_item_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  final Item item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  List<PriceHistory> _priceHistory = [];
  List<SubItem> _subItems = [];
  Map<String, Map<String, dynamic>> _monthlySpending = {};
  List<String> _monthlySpendingKeys = [];
  int _currentMonthIndex = 0;
  bool _isLoading = true;
  Item? _currentItem;
  TabController? _tabController;
  int _selectedTabIndex = 0;
  VoidCallback? _tabListener;

  // Cache for sub-items data to avoid reloading on tab switch
  final Map<int, List<PriceHistory>> _subItemHistoryCache = {};
  final Map<int, Map<String, Map<String, dynamic>>> _subItemMonthlySpendingCache = {};

  // Preserve cycle index for the purchase period stats card
  int _purchaseCycleIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _loadPriceHistory();
  }

  @override
  void dispose() {
    if (_tabListener != null && _tabController != null) {
      _tabController!.removeListener(_tabListener!);
    }
    _tabController?.dispose();
    super.dispose();
  }

  void _initializeTabController() {
    // Only create tab controller if there are sub-items
    if (_subItems.isEmpty) {
      return;
    }

    _tabController = TabController(
      length: _subItems.length, // Only sub-item tabs
      vsync: this,
    );

    _tabListener = () {
      if (_tabController != null && !_tabController!.indexIsChanging) {
        setState(() {
          _selectedTabIndex = _tabController!.index;
          _loadDataForSelectedTab();
        });
      }
    };

    _tabController!.addListener(_tabListener!);
  }

  Future<void> _loadPriceHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final subItems = await _databaseService.getSubItemsByItemId(widget.item.id!);
      final updatedItem = await _databaseService.getItemById(widget.item.id!);

      List<PriceHistory> history;
      Map<String, Map<String, dynamic>> monthlySpending;

      // Clear cache
      _subItemHistoryCache.clear();
      _subItemMonthlySpendingCache.clear();

      // If there are sub-items, preload all sub-items data
      if (subItems.isNotEmpty) {
        // Preload all sub-items data in parallel
        final futures = <Future>[];
        for (int i = 0; i < subItems.length; i++) {
          final subItem = subItems[i];
          futures.add(
            Future.wait([
              _databaseService.getPriceHistoryForSubItem(widget.item.id!, subItem.id!),
              _databaseService.getMonthlySpendingForSubItem(widget.item.id!, subItem.id!),
            ]).then((results) {
              _subItemHistoryCache[i] = results[0] as List<PriceHistory>;
              _subItemMonthlySpendingCache[i] = results[1] as Map<String, Map<String, dynamic>>;
            })
          );
        }

        await Future.wait(futures);

        // Use first sub-item's data
        history = _subItemHistoryCache[0]!;
        monthlySpending = _subItemMonthlySpendingCache[0]!;
      } else {
        // No sub-items, load parent item data
        history = await _databaseService.getPriceHistory(widget.item.id!, includeSubItems: false);
        monthlySpending = await _databaseService.getMonthlySpendingForItem(widget.item.id!);
      }

      // Dispose old tab controller BEFORE setState to avoid ticker issues
      if (_tabListener != null && _tabController != null) {
        _tabController!.removeListener(_tabListener!);
        _tabController!.dispose();
        _tabController = null;
        _tabListener = null;
      }

      setState(() {
        _priceHistory = history;
        _subItems = subItems;
        _currentItem = updatedItem ?? widget.item;
        _monthlySpending = monthlySpending;
        _monthlySpendingKeys = monthlySpending.keys.toList();
        _currentMonthIndex = 0;
        _isLoading = false;
      });

      // Initialize tab controller AFTER setState to avoid ticker issues
      _initializeTabController();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading price history: $e')),
        );
      }
    }
  }

  Future<void> _loadDataForSelectedTab({bool forceReload = false}) async {
    // Use cached data if available and not forcing reload
    if (!forceReload &&
        _subItemHistoryCache.containsKey(_selectedTabIndex) &&
        _subItemMonthlySpendingCache.containsKey(_selectedTabIndex)) {
      setState(() {
        _priceHistory = _subItemHistoryCache[_selectedTabIndex]!;
        _monthlySpending = _subItemMonthlySpendingCache[_selectedTabIndex]!;
        _monthlySpendingKeys = _monthlySpending.keys.toList();
        _currentMonthIndex = 0;
      });
      return;
    }

    // Load data from database
    setState(() {
      _isLoading = true;
    });

    try {
      final subItem = _subItems[_selectedTabIndex];
      final history = await _databaseService.getPriceHistoryForSubItem(
          widget.item.id!, subItem.id!);
      final monthlySpending =
          await _databaseService.getMonthlySpendingForSubItem(
              widget.item.id!, subItem.id!);

      setState(() {
        _priceHistory = history;
        _monthlySpending = monthlySpending;
        _monthlySpendingKeys = monthlySpending.keys.toList();
        _currentMonthIndex = 0;
        _isLoading = false;
      });

      // Update cache with fresh data
      _subItemHistoryCache[_selectedTabIndex] = history;
      _subItemMonthlySpendingCache[_selectedTabIndex] = monthlySpending;
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

  Future<void> _addPriceEntry() async {
    // Determine current price based on whether sub-items exist
    final currentPrice = _subItems.isEmpty
        ? _currentItem!.currentPrice
        : _subItems[_selectedTabIndex].currentPrice;

    // Check if usage tracking is enabled for this item
    final bool trackUsage = _currentItem!.trackUsage;
    final String? usageUnit = _currentItem!.usageUnit;

    // Initialize with current price as default value
    final priceController = TextEditingController(
      text: NumberFormat('#,###').format(currentPrice.round()),
    );
    final descriptionController = TextEditingController();
    final quantityPurchasedController = TextEditingController();
    final quantityValueController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool recordRemaining = true; // true = remaining, false = consumed

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8C00), Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  trackUsage ? Icons.trending_up : Icons.add_shopping_cart,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  trackUsage ? 'Add Usage Entry' : 'Add Price Entry',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: priceController,
                  decoration: InputDecoration(
                    labelText: 'Price',
                    suffixText: 'Rwf',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFFF8C00), width: 2),
                    ),
                    prefixIcon:
                        const Icon(Icons.payments, color: Color(0xFFFFC107)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        priceController.clear();
                      },
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final int value = int.parse(newValue.text);
                      final formatted = NumberFormat('#,###').format(value);
                      return TextEditingValue(
                        text: formatted,
                        selection:
                            TextSelection.collapsed(offset: formatted.length),
                      );
                    }),
                  ],
                ),
                // Usage tracking fields (only shown when trackUsage is enabled)
                if (trackUsage) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityPurchasedController,
                    decoration: InputDecoration(
                      labelText: 'Quantity Purchased (Optional)',
                      suffixText: usageUnit ?? 'units',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFFF8C00), width: 2),
                      ),
                      prefixIcon:
                          const Icon(Icons.add_box, color: Color(0xFF4CAF50)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: 'e.g., 100',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Toggle between remaining and consumed
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                recordRemaining = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: recordRemaining
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: recordRemaining
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Remaining',
                                  style: TextStyle(
                                    color: recordRemaining
                                        ? const Color(0xFFFF8C00)
                                        : Colors.grey.shade600,
                                    fontWeight: recordRemaining
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                recordRemaining = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !recordRemaining
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: !recordRemaining
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Consumed',
                                  style: TextStyle(
                                    color: !recordRemaining
                                        ? const Color(0xFFFF8C00)
                                        : Colors.grey.shade600,
                                    fontWeight: !recordRemaining
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityValueController,
                    decoration: InputDecoration(
                      labelText: recordRemaining
                          ? 'Remaining Quantity'
                          : 'Consumed Quantity',
                      suffixText: usageUnit ?? 'units',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFFF8C00), width: 2),
                      ),
                      prefixIcon: Icon(
                        recordRemaining ? Icons.inventory : Icons.remove_circle,
                        color: recordRemaining
                            ? const Color(0xFF2196F3)
                            : const Color(0xFFE91E63),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: recordRemaining
                          ? 'e.g., 45 (how much is left)'
                          : 'e.g., 5 (how much used)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFFF8C00), width: 2),
                    ),
                    prefixIcon:
                        const Icon(Icons.description, color: Color(0xFFFFB700)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() {
                        selectedDate = date;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            color: Color(0xFFFF9500), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy').format(selectedDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
              child: const Text('Cancel'),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB700), Color(0xFFFF8C00)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton(
                onPressed: () {
                  if (priceController.text.isNotEmpty) {
                    Navigator.pop(context, {
                      'price': priceController.text,
                      'date': selectedDate,
                      'description': descriptionController.text.trim(),
                      'quantityPurchased': quantityPurchasedController.text.trim(),
                      'quantityValue': quantityValueController.text.trim(),
                      'recordRemaining': recordRemaining,
                    });
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      try {
        final priceText = result['price']!;
        final price = double.parse(priceText.replaceAll(',', ''));
        final recordedAt = result['date'] as DateTime;
        final description = result['description'] as String?;

        // Parse usage tracking fields
        double? quantityPurchased;
        double? quantityRemaining;
        double? quantityConsumed;

        if (trackUsage) {
          final purchasedText = result['quantityPurchased'] as String?;
          final valueText = result['quantityValue'] as String?;
          final isRemaining = result['recordRemaining'] as bool;

          if (purchasedText != null && purchasedText.isNotEmpty) {
            quantityPurchased = double.tryParse(purchasedText);
          }
          if (valueText != null && valueText.isNotEmpty) {
            final value = double.tryParse(valueText);
            if (value != null) {
              if (isRemaining) {
                quantityRemaining = value;
              } else {
                quantityConsumed = value;
              }
            }
          }
        }

        if (_subItems.isEmpty) {
          // Main item (only when no sub-items)
          final priceHistory = PriceHistory(
            itemId: _currentItem!.id!,
            price: price,
            recordedAt: recordedAt,
            createdAt: DateTime.now(),
            entryType: 'manual',
            description: description?.isEmpty == true ? null : description,
            quantityPurchased: quantityPurchased,
            quantityRemaining: quantityRemaining,
            quantityConsumed: quantityConsumed,
          );

          await _databaseService.insertPriceHistory(priceHistory);

          // Update item's current price if it's different
          if (price != _currentItem!.currentPrice) {
            final updatedItem = _currentItem!.copyWith(
              currentPrice: price,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateItem(updatedItem);
            _currentItem = updatedItem;
          }
        } else {
          // Sub-item
          final subItem = _subItems[_selectedTabIndex];
          final priceHistory = PriceHistory(
            itemId: _currentItem!.id!,
            subItemId: subItem.id!,
            price: price,
            recordedAt: recordedAt,
            createdAt: DateTime.now(),
            entryType: 'manual',
            description: description?.isEmpty == true ? null : description,
            quantityPurchased: quantityPurchased,
            quantityRemaining: quantityRemaining,
            quantityConsumed: quantityConsumed,
          );

          await _databaseService.insertPriceHistory(priceHistory);

          // Update sub-item's current price if it's different
          if (price != subItem.currentPrice) {
            final updatedSubItem = subItem.copyWith(
              currentPrice: price,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateSubItem(updatedSubItem);
            _subItems[_selectedTabIndex] = updatedSubItem;
          }
        }

        // Reload data: use full reload for main item, or tab-specific reload for sub-items
        if (_subItems.isEmpty) {
          await _loadPriceHistory();
        } else {
          await _loadDataForSelectedTab(forceReload: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entry added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding entry: $e')),
          );
        }
      }
    }
  }

  List<FlSpot> _generateChartData() {
    if (_priceHistory.length < 2) return [];

    // Filter out automatic entries from chart (these are automatic entries when item price is updated)
    final chartHistory =
        _priceHistory.where((entry) => entry.entryType == 'manual').toList();

    if (chartHistory.length < 2) return [];

    // Sort price history by date to ensure proper chronological order
    final sortedHistory = List<PriceHistory>.from(chartHistory)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    // Use index-based positioning to show only dates with data
    return sortedHistory.asMap().entries.map((entry) {
      final index = entry.key;
      final priceEntry = entry.value;
      return FlSpot(index.toDouble(), priceEntry.price);
    }).toList();
  }

  double get _minPrice {
    if (_priceHistory.isEmpty) return 0;
    return _priceHistory.map((e) => e.price).reduce((a, b) => a < b ? a : b);
  }

  double get _maxPrice {
    if (_priceHistory.isEmpty) return 100;
    return _priceHistory.map((e) => e.price).reduce((a, b) => a > b ? a : b);
  }

  // Get the number of data points for the chart X-axis
  double get _maxDays {
    if (_priceHistory.length < 2) return 0;

    // Filter out automatic entries from chart calculation
    final chartHistory =
        _priceHistory.where((entry) => entry.entryType == 'manual').toList();

    if (chartHistory.length < 2) return 0;

    // Return the number of data points minus 1 (since we start from 0)
    return (chartHistory.length - 1).toDouble();
  }

  // Get date from index for chart labels
  DateTime _getDateFromDays(double index) {
    if (_priceHistory.isEmpty) return DateTime.now();

    // Filter out automatic entries from chart calculation
    final chartHistory =
        _priceHistory.where((entry) => entry.entryType == 'manual').toList();

    if (chartHistory.isEmpty) return DateTime.now();

    final sortedHistory = List<PriceHistory>.from(chartHistory)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    // Get the actual date for this index position
    final indexInt = index.round();
    if (indexInt >= 0 && indexInt < sortedHistory.length) {
      return sortedHistory[indexInt].recordedAt;
    }

    return DateTime.now();
  }

  String _getPriceChangeText() {
    // Filter out automatic entries and sort by date
    final filteredHistory = _priceHistory
        .where((entry) => entry.entryType == 'manual')
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    if (filteredHistory.length < 2) return '';

    final firstPrice = filteredHistory.first.price; // Oldest entry
    final lastPrice = filteredHistory.last.price; // Newest entry
    final change = lastPrice - firstPrice;
    final changePercent = (change / firstPrice) * 100;

    final prefix = change >= 0 ? '+' : '';
    final formattedChange = NumberFormat('#,###').format(change.abs().round());

    return '$prefix$formattedChange Rwf ($prefix${changePercent.toStringAsFixed(1)}%)';
  }

  String _getEndDateWithDaysDifference(DateTime startDate, DateTime endDate) {
    // Calculate days based on calendar date changes, not 24-hour intervals
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final daysDifference = end.difference(start).inDays;
    final endDateFormatted = DateFormat('MMM dd').format(endDate);

    if (daysDifference == 0) {
      return '(Ended: $endDateFormatted)';
    } else if (daysDifference == 1) {
      return '(Ended: $endDateFormatted, \nAfter 1 day)';
    } else {
      final formattedDifference =
          _formatDaysDifferenceForEnd(daysDifference.abs());
      return '(Ended: $endDateFormatted, \nAfter $formattedDifference)';
    }
  }

  String _formatDaysDifferenceForEnd(int days) {
    if (days < 30) {
      return '$days days';
    } else {
      final months = days ~/ 30;
      final remainingDays = days % 30;
      if (remainingDays == 0) {
        return months == 1 ? '1 month' : '$months months';
      } else {
        final monthText = months == 1 ? '1 month' : '$months months';
        final dayText = remainingDays == 1 ? '1 day' : '$remainingDays days';
        return '$monthText and $dayText';
      }
    }
  }

  String _calculateDaysOngoingFromLatestEntry(DateTime latestEntryDate) {
    // Calculate days based on calendar date changes, not 24-hour intervals
    final now = DateTime.now();
    final startDate = DateTime(
        latestEntryDate.year, latestEntryDate.month, latestEntryDate.day);
    final currentDate = DateTime(now.year, now.month, now.day);
    final daysDifference = currentDate.difference(startDate).inDays;

    if (daysDifference == 0) {
      return '0 days';
    } else if (daysDifference == 1) {
      return '1 day';
    } else {
      return _formatDaysDifferenceForEnd(daysDifference);
    }
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      double kValue = price / 1000;
      if (kValue == kValue.round()) {
        return '${kValue.round()}k Rwf';
      } else {
        return '${kValue.toStringAsFixed(1)}k Rwf';
      }
    } else {
      return '${NumberFormat('#,###').format(price.round())} Rwf';
    }
  }

  List<Widget> _buildPriceHistoryList(List<PriceHistory> allHistory) {
    final sortedHistory = allHistory
        .where((e) => e.entryType == 'manual')
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    List<Widget> widgets = [];

    for (int i = 0; i < sortedHistory.length; i++) {
      final history = sortedHistory[i];

      // Add the main price history record
      widgets.add(_buildPriceHistoryItem(history, sortedHistory));

      // Check if this record is ended and there's a next record
      if (history.finishedAt != null && i < sortedHistory.length - 1) {
        final nextRecord = sortedHistory[i + 1];
        // Calculate days based on calendar date changes, not 24-hour intervals
        final finishedDate = DateTime(history.finishedAt!.year,
            history.finishedAt!.month, history.finishedAt!.day);
        final nextDate = DateTime(nextRecord.recordedAt.year,
            nextRecord.recordedAt.month, nextRecord.recordedAt.day);
        final gapDays = nextDate.difference(finishedDate).inDays;

        // Only add a gap record if there's a gap (more than 0 days)
        if (gapDays > 0) {
          widgets.add(_buildGapRecord(
              history.finishedAt!, nextRecord.recordedAt, gapDays));
        }
      }
    }

    return widgets.reversed.toList();
  }

  Widget _buildPriceHistoryItem(
      PriceHistory history, List<PriceHistory> sortedHistory) {
    // Find the current entry's position in chronologically sorted list
    final chronologicalIndex = sortedHistory.indexWhere(
        (e) => e.recordedAt == history.recordedAt && e.price == history.price);

    // Get the chronologically next entry (the one that came after this one in time)
    final nextDate = chronologicalIndex < sortedHistory.length - 1
        ? sortedHistory[chronologicalIndex + 1].recordedAt
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF5E6),
            Color(0xFFFFE8CC),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF8C00).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                right: 40), // Add space for the menu button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB700), Color(0xFFFF8C00)],
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy')
                                .format(history.recordedAt),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            history.finishedAt != null
                                ? _getEndDateWithDaysDifference(
                                    history.recordedAt, history.finishedAt!)
                                : nextDate != null
                                    ? _getEndDateWithDaysDifference(
                                        history.recordedAt, nextDate)
                                    : (chronologicalIndex ==
                                            sortedHistory.length - 1
                                        ? '(Latest Entry, ongoing by ${_calculateDaysOngoingFromLatestEntry(history.recordedAt)})'
                                        : '(Initial Price)'),
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (history.description != null &&
                              history.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    title: Row(
                                      children: [
                                        const Icon(
                                          Icons.description,
                                          color: Color(0xFFFF8C00),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Description',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ],
                                    ),
                                    content: SingleChildScrollView(
                                      child: Text(
                                        history.description!,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: Text(
                                history.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB700), Color(0xFFFF8C00)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatPrice(history.price),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Price entry options',
            onSelected: (value) {
              if (value == 'edit') {
                _editPriceEntry(history);
              } else if (value == 'delete') {
                _deletePriceEntry(history);
              } else if (value == 'mark_ended') {
                _markPriceEntryAsEnded(history);
              } else if (value == 'mark_unended') {
                _markPriceEntryAsUnended(history);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                ),
              ),
              if (history.finishedAt == null)
                const PopupMenuItem(
                  value: 'mark_ended',
                  child: Row(
                    children: [
                      Icon(Icons.flag, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Mark as Ended'),
                    ],
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'mark_unended',
                  child: Row(
                    children: [
                      Icon(Icons.flag, size: 18, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Mark as Unended'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGapRecord(DateTime endDate, DateTime nextDate, int gapDays) {
    final formattedGap = _formatDaysDifferenceForEnd(gapDays);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8F4F8), // Light blue background for gap records
            Color(0xFFD1E7ED), // Slightly darker blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4A90E2) // Blue border for gap records
              .withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4A90E2), // Blue circle for gap records
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gap Period',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '(${DateFormat('MMM dd').format(endDate)} to ${DateFormat('MMM dd, yyyy').format(nextDate)}, $formattedGap)',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF4A90E2), // Blue text for gap records
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF4A90E2), // Blue gradient for gap records
                  Color(0xFF2A7FCA)
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Gap',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPriceEntry(PriceHistory history) async {
    // Check if usage tracking is enabled for this item
    final bool trackUsage = _currentItem!.trackUsage;
    final String? usageUnit = _currentItem!.usageUnit;

    final priceController = TextEditingController(
      text: NumberFormat('#,###').format(history.price.round()),
    );
    final descriptionController = TextEditingController(
      text: history.description ?? '',
    );
    final quantityPurchasedController = TextEditingController(
      text: history.quantityPurchased?.toString() ?? '',
    );
    final quantityValueController = TextEditingController(
      text: (history.quantityRemaining ?? history.quantityConsumed)?.toString() ?? '',
    );
    DateTime selectedDate = history.recordedAt;
    bool recordRemaining = history.quantityRemaining != null || history.quantityConsumed == null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8C00), Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  trackUsage ? Icons.trending_up : Icons.edit,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  trackUsage ? 'Edit Usage Entry' : 'Edit Price Entry',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: priceController,
                  decoration: InputDecoration(
                    labelText: 'Price',
                    suffixText: 'Rwf',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFFF8C00), width: 2),
                    ),
                    prefixIcon:
                        const Icon(Icons.payments, color: Color(0xFFFFC107)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        priceController.clear();
                      },
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final int value = int.parse(newValue.text);
                      final formatted = NumberFormat('#,###').format(value);
                      return TextEditingValue(
                        text: formatted,
                        selection:
                            TextSelection.collapsed(offset: formatted.length),
                      );
                    }),
                  ],
                ),
                // Usage tracking fields (only shown when trackUsage is enabled)
                if (trackUsage) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityPurchasedController,
                    decoration: InputDecoration(
                      labelText: 'Quantity Purchased (Optional)',
                      suffixText: usageUnit ?? 'units',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFFF8C00), width: 2),
                      ),
                      prefixIcon:
                          const Icon(Icons.add_box, color: Color(0xFF4CAF50)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: 'e.g., 100',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Toggle between remaining and consumed
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                recordRemaining = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: recordRemaining
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: recordRemaining
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Remaining',
                                  style: TextStyle(
                                    color: recordRemaining
                                        ? const Color(0xFFFF8C00)
                                        : Colors.grey.shade600,
                                    fontWeight: recordRemaining
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                recordRemaining = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !recordRemaining
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: !recordRemaining
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Consumed',
                                  style: TextStyle(
                                    color: !recordRemaining
                                        ? const Color(0xFFFF8C00)
                                        : Colors.grey.shade600,
                                    fontWeight: !recordRemaining
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityValueController,
                    decoration: InputDecoration(
                      labelText: recordRemaining
                          ? 'Remaining Quantity'
                          : 'Consumed Quantity',
                      suffixText: usageUnit ?? 'units',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFFF8C00), width: 2),
                      ),
                      prefixIcon: Icon(
                        recordRemaining ? Icons.inventory : Icons.remove_circle,
                        color: recordRemaining
                            ? const Color(0xFF2196F3)
                            : const Color(0xFFE91E63),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: recordRemaining
                          ? 'e.g., 45 (how much is left)'
                          : 'e.g., 5 (how much used)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFFF8C00), width: 2),
                    ),
                    prefixIcon:
                        const Icon(Icons.description, color: Color(0xFFFFB700)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() {
                        selectedDate = date;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            color: Color(0xFFFF9500), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy').format(selectedDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
              child: const Text('Cancel'),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB700), Color(0xFFFF8C00)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton(
                onPressed: () {
                  if (priceController.text.isNotEmpty) {
                    Navigator.pop(context, {
                      'price': priceController.text,
                      'date': selectedDate,
                      'description': descriptionController.text.trim(),
                      'quantityPurchased': quantityPurchasedController.text.trim(),
                      'quantityValue': quantityValueController.text.trim(),
                      'recordRemaining': recordRemaining,
                    });
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text(
                  'Update',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final priceText = result['price']!;
        final price = double.parse(priceText.replaceAll(',', ''));
        final recordedAt = result['date'] as DateTime;
        final description = result['description'] as String?;

        // Parse usage tracking fields
        double? quantityPurchased;
        double? quantityRemaining;
        double? quantityConsumed;
        bool clearRemaining = false;
        bool clearConsumed = false;

        if (_currentItem!.trackUsage) {
          final purchasedText = result['quantityPurchased'] as String?;
          final valueText = result['quantityValue'] as String?;
          final isRemaining = result['recordRemaining'] as bool;

          if (purchasedText != null && purchasedText.isNotEmpty) {
            quantityPurchased = double.tryParse(purchasedText);
          }
          if (valueText != null && valueText.isNotEmpty) {
            final value = double.tryParse(valueText);
            if (value != null) {
              if (isRemaining) {
                quantityRemaining = value;
                clearConsumed = true; // Clear consumed if switching to remaining
              } else {
                quantityConsumed = value;
                clearRemaining = true; // Clear remaining if switching to consumed
              }
            }
          } else {
            // Clear both if no value entered
            clearRemaining = true;
            clearConsumed = true;
          }
        }

        final updatedPriceHistory = history.copyWith(
          price: price,
          recordedAt: recordedAt,
          description: description?.isEmpty == true ? null : description,
          quantityPurchased: quantityPurchased ?? history.quantityPurchased,
          quantityRemaining: quantityRemaining,
          quantityConsumed: quantityConsumed,
          clearQuantityRemaining: clearRemaining,
          clearQuantityConsumed: clearConsumed,
        );

        await _databaseService.updatePriceHistory(updatedPriceHistory);

        // Update item's current price if this is the most recent entry
        if (_subItems.isEmpty) {
          final allHistory =
              await _databaseService.getPriceHistory(_currentItem!.id!, includeSubItems: false);
          final mostRecent = allHistory
              .reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
          if (mostRecent.id == updatedPriceHistory.id) {
            final updatedItem = _currentItem!.copyWith(
              currentPrice: price,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateItem(updatedItem);
          }
          await _loadPriceHistory();
        } else {
          final subItem = _subItems[_selectedTabIndex];
          final allHistory = await _databaseService.getPriceHistoryForSubItem(
              _currentItem!.id!, subItem.id!);
          final mostRecent = allHistory
              .reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
          if (mostRecent.id == updatedPriceHistory.id) {
            final updatedSubItem = subItem.copyWith(
              currentPrice: price,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateSubItem(updatedSubItem);
            _subItems[_selectedTabIndex] = updatedSubItem;
          }
          await _loadDataForSelectedTab(forceReload: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Price entry updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating price entry: $e')),
          );
        }
      }
    }
  }

  Future<void> _markPriceEntryAsEnded(PriceHistory history) async {
    DateTime selectedDate = DateTime.now();

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8C00), Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.flag,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Set End Date',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select the date when this price period ended',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now()
                        .add(const Duration(days: 365)), // Allow future dates
                  );
                  if (date != null) {
                    setState(() {
                      selectedDate = date;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: Color(0xFFFF9500), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              DateFormat('MMM dd, yyyy').format(selectedDate),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
              child: const Text('Cancel'),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB700), Color(0xFFFF8C00)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context, selectedDate);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text(
                  'Confirm',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        await _databaseService.updatePriceHistoryFinishedAt(
            history.id!, result);

        // Reload data: use full reload for main item, or tab-specific reload for sub-items
        if (_subItems.isEmpty) {
          await _loadPriceHistory();
        } else {
          await _loadDataForSelectedTab(forceReload: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Price entry marked as ended')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error marking price entry as ended: $e')),
          );
        }
      }
    }
  }

  Future<void> _markPriceEntryAsUnended(PriceHistory history) async {
    try {
      // Set the finishedAt date to null to unmark as ended
      await _databaseService.updatePriceHistoryFinishedAt(history.id!, null);

      // Reload data: use full reload for main item, or tab-specific reload for sub-items
      if (_subItems.isEmpty) {
        await _loadPriceHistory();
      } else {
        await _loadDataForSelectedTab(forceReload: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price entry unmarked as ended')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unmarking price entry as ended: $e')),
        );
      }
    }
  }

  Future<void> _deletePriceEntry(PriceHistory history) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete, color: Colors.red, size: 24),
            SizedBox(width: 12),
            Text(
              'Delete Price Entry',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content:
            const Text('Are you sure you want to delete this price entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
            ),
            child: const Text('Cancel'),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _databaseService.deletePriceHistory(history.id!);

        // Update current price based on whether this is main item or sub-item
        if (_subItems.isEmpty) {
          // Main item - update item's current price
          final allHistory =
              await _databaseService.getPriceHistory(_currentItem!.id!, includeSubItems: false);
          if (allHistory.isNotEmpty) {
            final mostRecent = allHistory
                .reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
            final updatedItem = _currentItem!.copyWith(
              currentPrice: mostRecent.price,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateItem(updatedItem);
          } else {
            // If no history remains, set current price to 0 or some default
            final updatedItem = _currentItem!.copyWith(
              currentPrice: 0.0,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateItem(updatedItem);
          }
        } else {
          // Sub-item - update sub-item's current price
          final subItem = _subItems[_selectedTabIndex];
          final allHistory = await _databaseService.getPriceHistoryForSubItem(
              _currentItem!.id!, subItem.id!);
          if (allHistory.isNotEmpty) {
            final mostRecent = allHistory
                .reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
            final updatedSubItem = subItem.copyWith(
              currentPrice: mostRecent.price,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateSubItem(updatedSubItem);
            _subItems[_selectedTabIndex] = updatedSubItem;
          }
        }

        // Reload data: use full reload for main item, or tab-specific reload for sub-items
        if (_subItems.isEmpty) {
          await _loadPriceHistory();
        } else {
          await _loadDataForSelectedTab(forceReload: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Price entry deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting price entry: $e')),
          );
        }
      }
    }
  }

  Future<void> _addSubItem() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Sub-Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Sub-Item Name (e.g., 5kg, 10kg, 1L)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'Initial Price (Rwf)',
                  prefixText: 'Rwf ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) {
                      return newValue;
                    }
                    final number = int.parse(newValue.text);
                    final formatted = NumberFormat('#,###').format(number);
                    return TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFFFF8C00),
                            onPrimary: Colors.white,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    setState(() {
                      selectedDate = date;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: Color(0xFFFF9500), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              DateFormat('MMM dd, yyyy').format(selectedDate),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final priceText = priceController.text.replaceAll(',', '').trim();
                if (name.isNotEmpty && priceText.isNotEmpty) {
                  Navigator.of(context).pop({
                    'name': name,
                    'price': double.parse(priceText),
                    'date': selectedDate,
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final selectedDate = result['date'] as DateTime;
        final subItem = SubItem(
          itemId: widget.item.id!,
          name: result['name'] as String,
          currentPrice: result['price'] as double,
          createdAt: selectedDate,
          updatedAt: selectedDate,
        );

        await _databaseService.insertSubItem(subItem);
        await _loadPriceHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sub-item added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding sub-item: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteSubItem(SubItem subItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sub-Item'),
        content: Text('Are you sure you want to delete "${subItem.name}"? This will also delete all its price records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _databaseService.deleteSubItem(subItem.id!);
        await _loadPriceHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sub-item deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting sub-item: $e')),
          );
        }
      }
    }
  }

  Map<String, dynamic> _getPurchaseConsistencyAnalysis() {
    // Filter out automatic entries and sort by date
    final filteredHistory = _priceHistory
        .where((entry) => entry.entryType == 'manual')
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    if (filteredHistory.length < 3) {
      return {
        'summary': 'Not enough data',
        'description': 'Need at least 3 entries to analyze patterns',
        'color': Colors.grey,
        'icon': Icons.help_outline,
      };
    }

    // Calculate intervals between purchases based on calendar date changes
    List<int> intervals = [];
    for (int i = 1; i < filteredHistory.length; i++) {
      final prevDate = DateTime(
          filteredHistory[i - 1].recordedAt.year,
          filteredHistory[i - 1].recordedAt.month,
          filteredHistory[i - 1].recordedAt.day);
      final currDate = DateTime(
          filteredHistory[i].recordedAt.year,
          filteredHistory[i].recordedAt.month,
          filteredHistory[i].recordedAt.day);
      final daysDiff = currDate.difference(prevDate).inDays;
      if (daysDiff > 0) intervals.add(daysDiff);
    }

    if (intervals.isEmpty) {
      return {
        'summary': 'No time gaps',
        'description': 'All entries on same days',
        'color': Colors.orange,
        'icon': Icons.schedule,
      };
    }

    // Calculate average and standard deviation
    final average = intervals.reduce((a, b) => a + b) / intervals.length;
    final variance = intervals
            .map((x) => (x - average) * (x - average))
            .reduce((a, b) => a + b) /
        intervals.length;
    final standardDeviation = math.sqrt(variance);
    final coefficientOfVariation = standardDeviation / average;

    // Determine consistency
    String summary;
    String description;
    Color color;
    IconData icon;

    if (coefficientOfVariation < 0.3) {
      summary = 'Very Consistent';
      description = 'Purchased every ${average.round()} days on average';
      color = Colors.green;
      icon = Icons.trending_up;
    } else if (coefficientOfVariation < 0.6) {
      summary = 'Moderately Consistent';
      description = 'Some variation in purchase timing';
      color = Colors.blue;
      icon = Icons.show_chart;
    } else if (coefficientOfVariation < 1.0) {
      summary = 'Inconsistent';
      description = 'Irregular purchase pattern';
      color = Colors.orange;
      icon = Icons.trending_flat;
    } else {
      summary = 'Very Inconsistent';
      description = 'Highly irregular purchases';
      color = Colors.red;
      icon = Icons.trending_down;
    }

    return {
      'summary': summary,
      'description': description,
      'color': color,
      'icon': icon,
      'average': average.round(),
      'intervals': intervals,
    };
  }

  String _formatMonth(String monthKey) {
    try {
      final date = DateTime.parse('$monthKey-01');
      return DateFormat('MMMM yyyy').format(date);
    } catch (e) {
      return monthKey;
    }
  }

  void _previousMonthlySpendingMonth() {
    if (_currentMonthIndex < _monthlySpendingKeys.length - 1) {
      setState(() {
        _currentMonthIndex++;
      });
    }
  }

  void _nextMonthlySpendingMonth() {
    if (_currentMonthIndex > 0) {
      setState(() {
        _currentMonthIndex--;
      });
    }
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentItem == null || (_subItems.isNotEmpty && _tabController == null)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(_subItems.isEmpty || _tabController == null ? 60 : 110),
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
          child: AppBar(
            title: Text(_currentItem!.name),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (_subItems.isNotEmpty) // Show delete button for sub-items when they exist
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete Sub-Item',
                  onPressed: () {
                    _deleteSubItem(_subItems[_selectedTabIndex]);
                  },
                ),
              if (_subItems.isEmpty) // Show edit button only when no sub-items (main item only)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Item',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddItemScreen(item: _currentItem),
                      ),
                    );
                    await _loadPriceHistory();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add Sub-Item',
                onPressed: _addSubItem,
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Price Entry',
                onPressed: _addPriceEntry,
              ),
            ],
            bottom: _subItems.isEmpty || _tabController == null
                ? null
                : TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: _subItems.map((subItem) => Tab(
                      child: Row(
                        children: [
                          const Icon(Icons.category, size: 16),
                          const SizedBox(width: 8),
                          Text(subItem.name),
                        ],
                      ),
                    )).toList(),
                  ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subItems.isEmpty || _tabController == null
              ? _buildItemContent()
              : TabBarView(
                  controller: _tabController,
                  children: _subItems.map((subItem) => _buildItemContent()).toList(),
                ),
    );
  }

  Widget _buildItemContent() {
    // Get current item name and price based on whether sub-items exist
    final String displayName = _subItems.isEmpty
        ? _currentItem!.name
        : _subItems[_selectedTabIndex].name;
    final double currentPrice = _subItems.isEmpty
        ? _currentItem!.currentPrice
        : _subItems[_selectedTabIndex].currentPrice;
    final String? description = _subItems.isEmpty
        ? _currentItem!.description
        : null;

    return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Item Info Card
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFF6B35)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  width: 3,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  displayName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (description != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Current Price',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${NumberFormat('#,###').format(currentPrice.round())} Rwf',
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (_priceHistory
                                      .where((entry) =>
                                          entry.entryType == 'manual')
                                      .length >=
                                  2)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Total Change',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _getPriceChangeText(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Purchase Period Stats Card (only shown when usage tracking is enabled)
                if (_currentItem!.trackUsage)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _databaseService.getPurchaseCycleStats(_currentItem!.id!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }

                      final cycles = snapshot.data!;
                      final usageUnit = _currentItem!.usageUnit ?? 'units';

                      // Don't show if no cycles
                      if (cycles.isEmpty) {
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.trending_up,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No usage data yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add a price entry with quantity purchased to start tracking usage',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return _PurchasePeriodStatsCard(
                        cycles: cycles,
                        usageUnit: usageUnit,
                        buildStatItem: _buildStatItem,
                        initialCycleIndex: _purchaseCycleIndex,
                        onCycleIndexChanged: (index) {
                          _purchaseCycleIndex = index;
                        },
                      );
                    },
                  ),
                if (_currentItem!.trackUsage) const SizedBox(height: 16),

                // Purchase Consistency Analysis
                if (_priceHistory
                        .where((entry) => entry.entryType == 'manual')
                        .length >=
                    2)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(
                        builder: (context) {
                          final analysis = _getPurchaseConsistencyAnalysis();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    analysis['icon'] as IconData,
                                    color: analysis['color'] as Color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Purchase Pattern',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: (analysis['color'] as Color)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: analysis['color'] as Color,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      analysis['summary'] as String,
                                      style: TextStyle(
                                        color: analysis['color'] as Color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                analysis['description'] as String,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Monthly Spending (Frequent Purchases)
                if (_monthlySpendingKeys.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_month,
                                color: AppColors.accentStart,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Monthly Spending',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Monthly purchase summary',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: _currentMonthIndex <
                                        _monthlySpendingKeys.length - 1
                                    ? _previousMonthlySpendingMonth
                                    : null,
                                icon: const Icon(Icons.arrow_left),
                                tooltip: 'Previous month',
                              ),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    if (_monthlySpendingKeys.isEmpty) {
                                      return const Center(
                                        child:
                                            Text('No monthly data available'),
                                      );
                                    }

                                    final currentMonth = _monthlySpendingKeys[
                                        _currentMonthIndex];
                                    final data =
                                        _monthlySpending[currentMonth]!;
                                    final frequency = data['frequency'] as int;
                                    final totalSpent =
                                        data['total_spent'] as double;

                                    return Column(
                                      children: [
                                        Text(
                                          _formatMonth(currentMonth),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: AppColors.accentGradient,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '$frequency purchases',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Column(
                                          children: [
                                            const Text(
                                              'Total Spent',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            Text(
                                              '${NumberFormat('#,###').format(totalSpent.round())} Rwf',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.accentStart,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: _currentMonthIndex > 0
                                    ? _nextMonthlySpendingMonth
                                    : null,
                                icon: const Icon(Icons.arrow_right),
                                tooltip: 'Next month',
                              ),
                            ],
                          ),
                          if (_monthlySpendingKeys.length > 1) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${_currentMonthIndex + 1} of ${_monthlySpendingKeys.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (_monthlySpendingKeys.isNotEmpty) const SizedBox(height: 16),

                // Price Chart
                if (_priceHistory
                        .where((entry) => entry.entryType == 'manual')
                        .length >=
                    2)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Price History Chart',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 200,
                            child: LineChart(
                              LineChartData(
                                gridData: const FlGridData(show: true),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      interval: 1,
                                      getTitlesWidget: (value, meta) {
                                        // Only show labels for actual data points to avoid overcrowding
                                        final chartHistory = _priceHistory
                                            .where((entry) =>
                                                entry.entryType == 'manual')
                                            .toList()
                                          ..sort((a, b) => a.recordedAt
                                              .compareTo(b.recordedAt));

                                        // Show every nth label based on number of data points
                                        final totalPoints = chartHistory.length;
                                        int skipInterval = 1;
                                        if (totalPoints > 8) {
                                          skipInterval =
                                              (totalPoints / 6).ceil();
                                        }

                                        final indexInt = value.round();
                                        if (indexInt % skipInterval != 0 &&
                                            indexInt != totalPoints - 1) {
                                          return const SizedBox.shrink();
                                        }

                                        final date = _getDateFromDays(value);
                                        return Transform.rotate(
                                          angle:
                                              -0.3, // Slight rotation to fit better
                                          child: Text(
                                            DateFormat('MM/dd').format(date),
                                            style: const TextStyle(fontSize: 9),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        String formatPrice(double price) {
                                          if (price >= 1000) {
                                            double kValue = price / 1000;
                                            if (kValue == kValue.round()) {
                                              return '${kValue.round()}k';
                                            } else {
                                              return '${kValue.toStringAsFixed(1)}k';
                                            }
                                          } else {
                                            return '${price.round()}';
                                          }
                                        }

                                        return Text(
                                          formatPrice(value),
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: true),
                                minX: 0,
                                maxX: _maxDays,
                                minY: _minPrice * 0.9,
                                maxY: _maxPrice * 1.1,
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _generateChartData(),
                                    isCurved: true,
                                    gradient: AppColors.primaryGradient,
                                    barWidth: 3,
                                    dotData: const FlDotData(show: true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Price History List
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Price History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_priceHistory.isEmpty)
                          const Text('No price history available')
                        else if (_priceHistory
                            .where((entry) => entry.entryType == 'manual')
                            .isEmpty)
                          const Text('No manual price entries yet')
                        else
                          ..._buildPriceHistoryList(_priceHistory),
                      ],
                    ),
                  ),
                ),
              ],
            );
  }
}

// Stateful widget for Purchase Period Stats with navigation
class _PurchasePeriodStatsCard extends StatefulWidget {
  final List<Map<String, dynamic>> cycles;
  final String usageUnit;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) buildStatItem;
  final int initialCycleIndex;
  final ValueChanged<int> onCycleIndexChanged;

  const _PurchasePeriodStatsCard({
    required this.cycles,
    required this.usageUnit,
    required this.buildStatItem,
    required this.initialCycleIndex,
    required this.onCycleIndexChanged,
  });

  @override
  State<_PurchasePeriodStatsCard> createState() => _PurchasePeriodStatsCardState();
}

class _PurchasePeriodStatsCardState extends State<_PurchasePeriodStatsCard> {
  late int _currentCycleIndex;

  @override
  void initState() {
    super.initState();
    // Ensure index is within bounds
    _currentCycleIndex = widget.initialCycleIndex.clamp(0, widget.cycles.length - 1);
  }

  void _goToPreviousCycle() {
    if (_currentCycleIndex < widget.cycles.length - 1) {
      setState(() {
        _currentCycleIndex++;
        widget.onCycleIndexChanged(_currentCycleIndex);
      });
    }
  }

  void _goToNextCycle() {
    if (_currentCycleIndex > 0) {
      setState(() {
        _currentCycleIndex--;
        widget.onCycleIndexChanged(_currentCycleIndex);
      });
    }
  }

  String _formatDateRange(DateTime purchaseDate, DateTime? endDate, bool isCurrentOngoing) {
    final startStr = DateFormat('MMM dd, yyyy').format(purchaseDate);
    if (endDate != null) {
      // Completed: show purchase date - end date
      return '$startStr - ${DateFormat('MMM dd, yyyy').format(endDate)}';
    } else if (isCurrentOngoing) {
      // Current ongoing purchase: show "Ongoing"
      return '$startStr - Ongoing';
    } else {
      // Past entry without end date (shouldn't happen now with inferred dates)
      return '$startStr - Present';
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchase = widget.cycles[_currentCycleIndex];
    final purchaseDate = purchase['purchaseDate'] as DateTime;
    final endDate = purchase['endDate'] as DateTime?;
    final quantityPurchased = purchase['quantityPurchased'] as double?;
    final quantityRemaining = purchase['quantityRemaining'] as double?;
    final consumed = purchase['consumed'] as double?;
    final daysTracked = purchase['daysTracked'] as int;
    final avgDailyUsage = purchase['avgDailyUsage'] as double?;
    final isComplete = purchase['isComplete'] as bool;
    final price = purchase['price'] as double?;
    final usedFallback = purchase['usedFallback'] as bool? ?? false;
    final usedHistoricalPattern = purchase['usedHistoricalPattern'] as bool? ?? false;

    // Calculate display values - avoid N/A when we can infer values
    final fallbackDailyUsage = (isComplete && quantityPurchased != null && daysTracked > 0)
        ? quantityPurchased / daysTracked
        : null;
    final displayDailyUsage = avgDailyUsage ?? fallbackDailyUsage;
    final displayConsumed = consumed ?? (isComplete && quantityPurchased != null ? quantityPurchased : null);
    final displayRemaining = quantityRemaining ?? (isComplete && quantityPurchased != null ? 0.0 : null);

    final bool canGoLeft = _currentCycleIndex < widget.cycles.length - 1;
    final bool canGoRight = _currentCycleIndex > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with navigation
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isComplete
                          ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                          : [const Color(0xFFFF9800), const Color(0xFFFFB74D)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isComplete ? Icons.check_circle : Icons.hourglass_top,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isComplete ? 'Completed Daily Usage' : 'Daily Usage',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.cycles.length - _currentCycleIndex} of ${widget.cycles.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Navigation arrows
                IconButton(
                  onPressed: canGoLeft ? _goToPreviousCycle : null,
                  icon: Icon(
                    Icons.chevron_left,
                    color: canGoLeft ? const Color(0xFFFF8C00) : Colors.grey.shade300,
                  ),
                  tooltip: 'Older purchase',
                ),
                IconButton(
                  onPressed: canGoRight ? _goToNextCycle : null,
                  icon: Icon(
                    Icons.chevron_right,
                    color: canGoRight ? const Color(0xFFFF8C00) : Colors.grey.shade300,
                  ),
                  tooltip: 'Newer purchase',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Date range
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatDateRange(purchaseDate, endDate, _currentCycleIndex == 0 && !isComplete),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isComplete ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$daysTracked days',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Price info
            if (price != null) ...[
              const SizedBox(height: 8),
              Text(
                'Price: ${NumberFormat('#,###').format(price.round())} Rwf',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Stats grid
            Row(
              children: [
                Expanded(
                  child: widget.buildStatItem(
                    icon: Icons.speed,
                    label: 'Daily Usage',
                    value: displayDailyUsage != null && displayDailyUsage > 0
                        ? '${displayDailyUsage.toStringAsFixed(1)} ${widget.usageUnit}'
                        : 'N/A',
                    color: const Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: widget.buildStatItem(
                    icon: Icons.shopping_cart,
                    label: 'Purchased',
                    value: quantityPurchased != null
                        ? '${quantityPurchased.toStringAsFixed(1)} ${widget.usageUnit}'
                        : 'N/A',
                    color: const Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: widget.buildStatItem(
                    icon: Icons.local_fire_department,
                    label: 'Consumed',
                    value: displayConsumed != null
                        ? '${displayConsumed.toStringAsFixed(1)} ${widget.usageUnit}'
                        : 'N/A',
                    color: const Color(0xFFE91E63),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: widget.buildStatItem(
                    icon: Icons.inventory_2,
                    label: 'Remaining',
                    value: displayRemaining != null
                        ? '${displayRemaining.toStringAsFixed(1)} ${widget.usageUnit}'
                        : 'N/A',
                    color: const Color(0xFF9C27B0),
                  ),
                ),
              ],
            ),

            // Show hint if using fallback or historical pattern
            if (usedFallback || usedHistoricalPattern) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC8E6C9)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        usedHistoricalPattern
                            ? 'Estimated from past purchase patterns'
                            : 'Using average from other purchases',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
