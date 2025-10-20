import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/item.dart';
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

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PriceHistory> _priceHistory = [];
  Map<String, Map<String, dynamic>> _monthlySpending = {};
  List<String> _monthlySpendingKeys = [];
  int _currentMonthIndex = 0;
  bool _isLoading = true;
  Item? _currentItem;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _loadPriceHistory();
  }

  Future<void> _loadPriceHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final history = await _databaseService.getPriceHistory(widget.item.id!);
      final updatedItem = await _databaseService.getItemById(widget.item.id!);
      final monthlySpending =
          await _databaseService.getMonthlySpendingForItem(widget.item.id!);

      setState(() {
        _priceHistory = history;
        _currentItem = updatedItem ?? widget.item;
        _monthlySpending = monthlySpending;
        _monthlySpendingKeys = monthlySpending.keys.toList();
        _currentMonthIndex = 0;
        _isLoading = false;
      });
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

  Future<void> _addPriceEntry() async {
    // Initialize with current price as default value
    final priceController = TextEditingController(
      text: NumberFormat('#,###').format(_currentItem!.currentPrice.round()),
    );
    DateTime selectedDate = DateTime.now();

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
                child: const Icon(
                  Icons.add_shopping_cart,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Add Price Entry',
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

        final priceHistory = PriceHistory(
          itemId: _currentItem!.id!,
          price: price,
          recordedAt: recordedAt,
          createdAt: DateTime.now(),
          entryType: 'manual',
        );

        await _databaseService.insertPriceHistory(priceHistory);

        // Update item's current price if it's different
        if (price != _currentItem!.currentPrice) {
          final updatedItem = _currentItem!.copyWith(
            currentPrice: price,
            updatedAt: DateTime.now(),
          );
          await _databaseService.updateItem(updatedItem);
        }

        _loadPriceHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Price entry added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding price entry: $e')),
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



  String _formatDaysDifference(int days) {
    if (days < 30) {
      return 'After $days days';
    } else {
      final months = days ~/ 30;
      final remainingDays = days % 30;
      if (remainingDays == 0) {
        return months == 1 ? 'After 1 month' : 'After $months months';
      } else {
        final monthText = months == 1 ? '1 month' : '$months months';
        final dayText = remainingDays == 1 ? '1 day' : '$remainingDays days';
        return 'After $monthText and $dayText';
      }
    }
  }

  String _getEndDateWithDaysDifference(DateTime startDate, DateTime endDate) {
    final daysDifference = endDate.difference(startDate).inDays;
    final endDateFormatted = DateFormat('MMM dd').format(endDate);

    if (daysDifference == 0) {
      return '(Ended: $endDateFormatted)';
    } else if (daysDifference == 1) {
      return '(Ended: $endDateFormatted, 1 day)';
    } else {
      final formattedDifference = _formatDaysDifferenceForEnd(daysDifference.abs());
      return '(Ended: $endDateFormatted, $formattedDifference)';
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

  Future<void> _editPriceEntry(PriceHistory history) async {
    final priceController = TextEditingController(
      text: NumberFormat('#,###').format(history.price.round()),
    );
    DateTime selectedDate = history.recordedAt;

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
                child: const Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Edit Price Entry',
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

        final updatedPriceHistory = history.copyWith(
          price: price,
          recordedAt: recordedAt,
        );

        await _databaseService.updatePriceHistory(updatedPriceHistory);

        // Update item's current price if this is the most recent entry
        final allHistory = await _databaseService.getPriceHistory(_currentItem!.id!);
        final mostRecent = allHistory.reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
        if (mostRecent.id == updatedPriceHistory.id) {
          final updatedItem = _currentItem!.copyWith(
            currentPrice: price,
            updatedAt: DateTime.now(),
          );
          await _databaseService.updateItem(updatedItem);
        }

        _loadPriceHistory();

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
                    lastDate: DateTime.now().add(const Duration(days: 365)), // Allow future dates
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
        await _databaseService.updatePriceHistoryFinishedAt(history.id!, result);

        _loadPriceHistory();

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

      _loadPriceHistory();

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
        content: const Text('Are you sure you want to delete this price entry?'),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

        // Update item's current price if this was the most recent entry
        final allHistory = await _databaseService.getPriceHistory(_currentItem!.id!);
        if (allHistory.isNotEmpty) {
          final mostRecent = allHistory.reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
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

        _loadPriceHistory();

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

    // Calculate intervals between purchases
    List<int> intervals = [];
    for (int i = 1; i < filteredHistory.length; i++) {
      final daysDiff = filteredHistory[i]
          .recordedAt
          .difference(filteredHistory[i - 1].recordedAt)
          .inDays;
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

  @override
  Widget build(BuildContext context) {
    if (_currentItem == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
          child: AppBar(
            title: Text(_currentItem!.name),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddItemScreen(item: _currentItem),
                    ),
                  ).then((_) => _loadPriceHistory());
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addPriceEntry,
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                                  _currentItem!.name[0].toUpperCase(),
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
                                    _currentItem!.name,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (_currentItem!.description != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _currentItem!.description!,
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
                                      '${NumberFormat('#,###').format(_currentItem!.currentPrice.round())} Rwf',
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
                          ...(_priceHistory
                                  .where((entry) => entry.entryType == 'manual')
                                  .toList()
                                ..sort((a, b) =>
                                    a.recordedAt.compareTo(b.recordedAt)))
                              .reversed
                              .toList()
                              .asMap()
                              .entries
                              .map((entry) {
                            final history = entry.value;
                            final sortedHistory = _priceHistory
                                .where((e) => e.entryType == 'manual')
                                .toList()
                              ..sort((a, b) =>
                                  a.recordedAt.compareTo(b.recordedAt));

                            // Find the current entry's position in chronologically sorted list
                            final chronologicalIndex = sortedHistory.indexWhere(
                                (e) =>
                                    e.recordedAt == history.recordedAt &&
                                    e.price == history.price);

                            // Get the chronologically next entry (the one that came after this one in time)
                            final nextDate = chronologicalIndex < sortedHistory.length - 1
                                ? sortedHistory[chronologicalIndex + 1]
                                    .recordedAt
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
                                  color: const Color(0xFFFF8C00)
                                      .withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 40), // Add space for the menu button
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
                                                  colors: [
                                                    Color(0xFFFFB700),
                                                    Color(0xFFFF8C00)
                                                  ],
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    DateFormat('MMM dd, yyyy').format(history.recordedAt),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Color(0xFF2C3E50),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    history.finishedAt != null
                                                      ? _getEndDateWithDaysDifference(history.recordedAt, history.finishedAt!)
                                                      : nextDate != null 
                                                          ? _getEndDateWithDaysDifference(history.recordedAt, nextDate)
                                                          : (chronologicalIndex == sortedHistory.length - 1 ? '(Latest Entry)' : '(Initial Price)'),
                                                    style: const TextStyle(
                                                      fontStyle: FontStyle.italic,
                                                      color: Color(0xFFFF8C00),
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
                                                    Color(0xFFFFB700),
                                                    Color(0xFFFF8C00)
                                                  ],
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
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: const [
                                            Icon(Icons.edit, size: 18),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      if (history.finishedAt == null)
                                        PopupMenuItem(
                                          value: 'mark_ended',
                                          child: Row(
                                            children: const [
                                              Icon(Icons.flag, size: 18, color: Colors.orange),
                                              SizedBox(width: 8),
                                              Text('Mark as Ended'),
                                            ],
                                          ),
                                        )
                                      else
                                        PopupMenuItem(
                                          value: 'mark_unended',
                                          child: Row(
                                            children: const [
                                              Icon(Icons.flag, size: 18, color: Colors.green),
                                              SizedBox(width: 8),
                                              Text('Mark as Unended'),
                                            ],
                                          ),
                                        ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: const [
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
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
