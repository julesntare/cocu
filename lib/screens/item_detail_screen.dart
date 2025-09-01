import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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

      setState(() {
        _priceHistory = history;
        _currentItem = updatedItem ?? widget.item;
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
    final priceController = TextEditingController();
    final noteController = TextEditingController();
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
                decoration: const InputDecoration(
                  labelText: 'Price',
                  suffixText: 'Rwf',
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
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (Optional)',
                ),
                textCapitalization: TextCapitalization.sentences,
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
                    'note': noteController.text,
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
        final note = result['note']!.trim();
        final recordedAt = result['date'] as DateTime;

        final priceHistory = PriceHistory(
          itemId: _currentItem!.id!,
          price: price,
          recordedAt: recordedAt,
          note: note.isEmpty ? null : note,
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

    return _priceHistory.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
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

  String _getPriceChangeText() {
    if (_priceHistory.length < 2) return '';

    final firstPrice = _priceHistory.first.price;
    final lastPrice = _priceHistory.last.price;
    final change = lastPrice - firstPrice;
    final changePercent = (change / firstPrice) * 100;

    final prefix = change >= 0 ? '+' : '';
    final formattedChange = NumberFormat('#,###').format(change.abs().round());

    return '$prefix$formattedChange Rwf ($prefix${changePercent.toStringAsFixed(1)}%)';
  }

  Color _getPriceChangeColor() {
    if (_priceHistory.length < 2) return Colors.grey;

    final firstPrice = _priceHistory.first.price;
    final lastPrice = _priceHistory.last.price;
    final change = lastPrice - firstPrice;

    return change >= 0 ? Colors.red : Colors.green;
  }

  Map<String, String> _getDateWithDaysDifference(
      DateTime date, DateTime? previousDate) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);

    if (previousDate == null) {
      return {'date': dateStr, 'difference': '(Initial)'};
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
                            if (_priceHistory.length >= 2)
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

                // Price Chart
                if (_priceHistory.length >= 2)
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
                                      getTitlesWidget: (value, meta) {
                                        if (value.toInt() >= 0 &&
                                            value.toInt() <
                                                _priceHistory.length) {
                                          return Text(
                                            DateFormat('MM/dd').format(
                                                _priceHistory[value.toInt()]
                                                    .recordedAt),
                                            style:
                                                const TextStyle(fontSize: 10),
                                          );
                                        }
                                        return const Text('');
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          '${value.toStringAsFixed(0)} Rwf',
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
                                maxX: (_priceHistory.length - 1).toDouble(),
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
                        else
                          ...(_priceHistory.reversed
                              .toList()
                              .asMap()
                              .entries
                              .map((entry) {
                            final index = entry.key;
                            final history = entry.value;
                            final reversedIndex =
                                _priceHistory.length - 1 - index;
                            final previousDate = reversedIndex > 0
                                ? _priceHistory[reversedIndex - 1].recordedAt
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
                                        if (history.note != null)
                                          Text(
                                            history.note!,
                                            style: TextStyle(
                                                color: Colors.grey[600]),
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
                          })),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
