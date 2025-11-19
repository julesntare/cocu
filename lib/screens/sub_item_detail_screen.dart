import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/sub_item.dart';
import '../models/price_history.dart';
import '../services/database_service.dart';
import '../widgets/finish_date_popup.dart';

class SubItemDetailScreen extends StatefulWidget {
  final SubItem subItem;

  const SubItemDetailScreen({super.key, required this.subItem});

  @override
  State<SubItemDetailScreen> createState() => _SubItemDetailScreenState();
}

class _SubItemDetailScreenState extends State<SubItemDetailScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PriceHistory> _priceHistory = [];
  Map<String, Map<String, dynamic>> _monthlySpending = {};
  List<String> _monthlySpendingKeys = [];
  int _currentMonthIndex = 0;
  bool _isLoading = true;
  SubItem? _currentSubItem;

  @override
  void initState() {
    super.initState();
    _currentSubItem = widget.subItem;
    _loadPriceHistory();
  }

  Future<void> _loadPriceHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final history = await _databaseService.getPriceHistoryForSubItem(
          widget.subItem.itemId, widget.subItem.id!);
      final updatedSubItem =
          await _databaseService.getSubItemById(widget.subItem.id!);
      final monthlySpending =
          await _databaseService.getMonthlySpendingForSubItem(
              widget.subItem.itemId, widget.subItem.id!);

      setState(() {
        _priceHistory = history;
        _currentSubItem = updatedSubItem ?? widget.subItem;
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
    final priceController = TextEditingController(
      text: NumberFormat('#,###').format(_currentSubItem!.currentPrice.round()),
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
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'Price (Rwf)',
                  prefixText: 'Rwf ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
                      selection:
                          TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
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
                  if (picked != null) {
                    setState(() {
                      selectedDate = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[50],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          color: Colors.grey[600], size: 20),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('MMM dd, yyyy').format(selectedDate),
                        style: const TextStyle(fontSize: 16),
                      ),
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
                final priceText =
                    priceController.text.replaceAll(',', '').trim();
                if (priceText.isNotEmpty) {
                  Navigator.of(context).pop({
                    'price': double.parse(priceText),
                    'date': selectedDate,
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final newPrice = result['price'] as double;
        final recordedAt = result['date'] as DateTime;

        await _databaseService.insertPriceHistory(PriceHistory(
          itemId: widget.subItem.itemId,
          subItemId: widget.subItem.id!,
          price: newPrice,
          recordedAt: recordedAt,
          createdAt: DateTime.now(),
          entryType: 'manual',
        ));

        if (newPrice != _currentSubItem!.currentPrice) {
          await _databaseService.updateSubItem(_currentSubItem!.copyWith(
            currentPrice: newPrice,
            updatedAt: DateTime.now(),
          ));
        }

        await _loadPriceHistory();

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

  Future<void> _editPriceEntry(PriceHistory priceHistory) async {
    final priceController = TextEditingController(
      text: NumberFormat('#,###').format(priceHistory.price.round()),
    );
    DateTime selectedDate = priceHistory.recordedAt;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Edit Price Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'Price (Rwf)',
                  prefixText: 'Rwf ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
                      selection:
                          TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      selectedDate = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[50],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          color: Colors.grey[600], size: 20),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('MMM dd, yyyy').format(selectedDate),
                        style: const TextStyle(fontSize: 16),
                      ),
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
                final priceText =
                    priceController.text.replaceAll(',', '').trim();
                if (priceText.isNotEmpty) {
                  Navigator.of(context).pop({
                    'price': double.parse(priceText),
                    'date': selectedDate,
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final newPrice = result['price'] as double;
        final recordedAt = result['date'] as DateTime;

        await _databaseService.updatePriceHistory(priceHistory.copyWith(
          price: newPrice,
          recordedAt: recordedAt,
        ));

        final isLatestEntry = priceHistory.id == _priceHistory.last.id;
        if (isLatestEntry && newPrice != _currentSubItem!.currentPrice) {
          await _databaseService.updateSubItem(_currentSubItem!.copyWith(
            currentPrice: newPrice,
            updatedAt: DateTime.now(),
          ));
        }

        await _loadPriceHistory();

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

  Future<void> _deletePriceEntry(PriceHistory priceHistory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Price Entry'),
        content:
            const Text('Are you sure you want to delete this price entry?'),
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
        await _databaseService.deletePriceHistory(priceHistory.id!);

        final remainingHistory =
            await _databaseService.getPriceHistoryForSubItem(
                widget.subItem.itemId, widget.subItem.id!);
        if (remainingHistory.isNotEmpty) {
          final latestPrice = remainingHistory.last.price;
          if (latestPrice != _currentSubItem!.currentPrice) {
            await _databaseService.updateSubItem(_currentSubItem!.copyWith(
              currentPrice: latestPrice,
              updatedAt: DateTime.now(),
            ));
          }
        }

        await _loadPriceHistory();

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

  Future<void> _markAsEnded(PriceHistory priceHistory) async {
    DateTime? finishDate;

    await showDialog(
      context: context,
      builder: (context) => FinishDatePopup(
        initialDate: priceHistory.recordedAt,
        onDateSelected: (date) {
          finishDate = date;
        },
      ),
    );

    if (finishDate != null) {
      try {
        await _databaseService.updatePriceHistoryFinishedAt(
            priceHistory.id!, finishDate);
        await _loadPriceHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Price period marked as ended')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error marking as ended: $e')),
          );
        }
      }
    }
  }

  Future<void> _markAsUnended(PriceHistory priceHistory) async {
    try {
      await _databaseService.updatePriceHistoryFinishedAt(
          priceHistory.id!, null);
      await _loadPriceHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price period marked as unended')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking as unended: $e')),
        );
      }
    }
  }

  double _calculateTotalPriceChange() {
    if (_priceHistory.isEmpty) return 0;
    final manualEntries =
        _priceHistory.where((p) => p.entryType == 'manual').toList();
    if (manualEntries.isEmpty) return 0;

    final firstPrice = manualEntries.first.price;
    final lastPrice = manualEntries.last.price;
    return lastPrice - firstPrice;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_currentSubItem?.name ?? ''),
        backgroundColor: const Color(0xFFFF8C00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildMonthlySpendingCard(),
                  const SizedBox(height: 16),
                  _buildPriceChart(),
                  const SizedBox(height: 16),
                  _buildPriceHistoryList(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPriceEntry,
        backgroundColor: const Color(0xFFFF8C00),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildHeader() {
    final totalChange = _calculateTotalPriceChange();
    final changePercent =
        _priceHistory.isNotEmpty && _priceHistory.first.price > 0
            ? (totalChange / _priceHistory.first.price) * 100
            : 0.0;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF8C00), Color(0xFFFF6B35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              child: Text(
                _currentSubItem!.name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Rwf ${NumberFormat('#,###').format(_currentSubItem!.currentPrice.round())}',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (totalChange != 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: totalChange >= 0
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      totalChange >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: totalChange >= 0 ? Colors.red : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${totalChange >= 0 ? '+' : ''}${NumberFormat('#,###').format(totalChange.round())} (${changePercent.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        color: totalChange >= 0 ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySpendingCard() {
    if (_monthlySpending.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentMonth = _monthlySpendingKeys[_currentMonthIndex];
    final spending = _monthlySpending[currentMonth]!;
    final frequency = spending['frequency'] as int;
    final totalSpent = spending['total_spent'] as double;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentMonthIndex < _monthlySpendingKeys.length - 1
                    ? () {
                        setState(() {
                          _currentMonthIndex++;
                        });
                      }
                    : null,
              ),
              Text(
                DateFormat('MMMM yyyy')
                    .format(DateTime.parse('$currentMonth-01')),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentMonthIndex > 0
                    ? () {
                        setState(() {
                          _currentMonthIndex--;
                        });
                      }
                    : null,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text(
                    'Purchases',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$frequency',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8C00),
                    ),
                  ),
                ],
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.grey[300],
              ),
              Column(
                children: [
                  const Text(
                    'Total Spent',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rwf ${NumberFormat('#,###').format(totalSpent.round())}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8C00),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceChart() {
    final manualEntries =
        _priceHistory.where((p) => p.entryType == 'manual').toList();

    if (manualEntries.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text('No price history available'),
        ),
      );
    }

    final spots = manualEntries.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();

    final minPrice = manualEntries.map((e) => e.price).reduce(math.min);
    final maxPrice = manualEntries.map((e) => e.price).reduce(math.max);
    final priceRange = maxPrice - minPrice;

    // Handle case when all prices are the same
    final yMin = priceRange == 0
        ? (minPrice * 0.9).floorToDouble()
        : (minPrice - priceRange * 0.1).floorToDouble();
    final yMax = priceRange == 0
        ? (maxPrice * 1.1).ceilToDouble()
        : (maxPrice + priceRange * 0.1).ceilToDouble();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: math.max((yMax - yMin) / 4, 1),
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[300],
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          NumberFormat('#,###').format(value.round()),
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 &&
                            value.toInt() < manualEntries.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('MMM\nyyyy').format(
                                  manualEntries[value.toInt()].recordedAt),
                              style: const TextStyle(fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (manualEntries.length - 1).toDouble(),
                minY: yMin,
                maxY: yMax,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFFFF8C00),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceHistoryList() {
    if (_priceHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    final manualEntries =
        _priceHistory.where((p) => p.entryType == 'manual').toList();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'All Price Entries',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: manualEntries.length,
            itemBuilder: (context, index) {
              final reversedIndex = manualEntries.length - 1 - index;
              final priceHistory = manualEntries[reversedIndex];
              final isLatest = reversedIndex == manualEntries.length - 1;
              final isFirst = reversedIndex == 0;

              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_cart,
                        color: Color(0xFFFF8C00),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          'Rwf ${NumberFormat('#,###').format(priceHistory.price.round())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isFirst)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Initial Price',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        if (isLatest && !isFirst)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Latest Entry',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        if (priceHistory.finishedAt != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Ended',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMM dd, yyyy')
                              .format(priceHistory.recordedAt),
                        ),
                        if (priceHistory.finishedAt != null)
                          Text(
                            'Ended: ${DateFormat('MMM dd, yyyy').format(priceHistory.finishedAt!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editPriceEntry(priceHistory);
                            break;
                          case 'delete':
                            _deletePriceEntry(priceHistory);
                            break;
                          case 'mark_ended':
                            _markAsEnded(priceHistory);
                            break;
                          case 'mark_unended':
                            _markAsUnended(priceHistory);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 20),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 20, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                        if (priceHistory.finishedAt == null)
                          const PopupMenuItem(
                            value: 'mark_ended',
                            child: Row(
                              children: [
                                Icon(Icons.event_busy, size: 20),
                                SizedBox(width: 8),
                                Text('Mark as Ended'),
                              ],
                            ),
                          ),
                        if (priceHistory.finishedAt != null)
                          const PopupMenuItem(
                            value: 'mark_unended',
                            child: Row(
                              children: [
                                Icon(Icons.event_available, size: 20),
                                SizedBox(width: 8),
                                Text('Mark as Unended'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (index < manualEntries.length - 1)
                    const Divider(height: 1),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
