import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/item.dart';
import '../models/price_history.dart';
import '../services/database_service.dart';
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
      final monthlySpending = await _databaseService.getMonthlySpendingForItem(widget.item.id!);

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
          title: const Text('Add Price Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'Price',
                  suffixText: 'Rwf',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      priceController.clear();
                    },
                  ),
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
              Row(
                children: [
                  const Text('Date: '),
                  TextButton(
                    onPressed: () async {
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
                    child:
                        Text(DateFormat('MMM dd, yyyy').format(selectedDate)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (priceController.text.isNotEmpty) {
                  Navigator.pop(context, {
                    'price': priceController.text,
                    'date': selectedDate,
                  });
                }
              },
              child: const Text('Add'),
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

  Color _getPriceChangeColor() {
    // Filter out automatic entries and sort by date
    final filteredHistory = _priceHistory
        .where((entry) => entry.entryType == 'manual')
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    if (filteredHistory.length < 2) return Colors.grey;

    final firstPrice = filteredHistory.first.price; // Oldest entry
    final lastPrice = filteredHistory.last.price; // Newest entry
    final change = lastPrice - firstPrice;

    return change >= 0 ? Colors.red : Colors.green;
  }

  Map<String, String> _getDateWithDaysDifference(
      DateTime date, DateTime? previousDate) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);

    if (previousDate == null) {
      return {'date': dateStr, 'difference': '(Initial Price)'};
    }

    final daysDifference = date.difference(previousDate).inDays;

    if (daysDifference == 0) {
      return {'date': dateStr, 'difference': '(Same day)'};
    } else if (daysDifference == 1) {
      return {'date': dateStr, 'difference': '(Next day)'};
    } else {
      return {'date': dateStr, 'difference': '(After $daysDifference days)'};
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
      appBar: AppBar(
        title: Text(_currentItem!.name),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Item Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue,
                              radius: 30,
                              child: Text(
                                _currentItem!.name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
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
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_currentItem!.description != null)
                                    Text(
                                      _currentItem!.description!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Current Price'),
                                Text(
                                  '${NumberFormat('#,###').format(_currentItem!.currentPrice.round())} Rwf',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            if (_priceHistory
                                    .where(
                                        (entry) => entry.entryType == 'manual')
                                    .length >=
                                2)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Total Change'),
                                  Text(
                                    _getPriceChangeText(),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _getPriceChangeColor(),
                                    ),
                                  ),
                                ],
                              ),
                          ],
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
                                          .withOpacity(0.1),
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
                                color: Colors.orange,
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
                                onPressed: _currentMonthIndex < _monthlySpendingKeys.length - 1
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
                                        child: Text('No monthly data available'),
                                      );
                                    }

                                    final currentMonth = _monthlySpendingKeys[_currentMonthIndex];
                                    final data = _monthlySpending[currentMonth]!;
                                    final frequency = data['frequency'] as int;
                                    final totalSpent = data['total_spent'] as double;

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
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(12),
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
                                                color: Colors.orange,
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
                                onPressed: _currentMonthIndex > 0 ? _nextMonthlySpendingMonth : null,
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
                if (_monthlySpendingKeys.isNotEmpty)
                  const SizedBox(height: 16),

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
                                    color: Colors.blue,
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

                            // Get the chronologically previous entry (the one that came before this one in time)
                            final previousDate = chronologicalIndex > 0
                                ? sortedHistory[chronologicalIndex - 1]
                                    .recordedAt
                                : null;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              _getDateWithDaysDifference(
                                                  history.recordedAt,
                                                  previousDate)['date']!,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _getDateWithDaysDifference(
                                                  history.recordedAt,
                                                  previousDate)['difference']!,
                                              style: TextStyle(
                                                fontStyle: FontStyle.italic,
                                                color: Colors.blue[600],
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${NumberFormat('#,###').format(history.price.round())} Rwf',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
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
