import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

class MonthlySummaryWidget extends StatefulWidget {
  final VoidCallback? onRefresh;

  const MonthlySummaryWidget({super.key, this.onRefresh});

  @override
  State<MonthlySummaryWidget> createState() => _MonthlySummaryWidgetState();
}

class _MonthlySummaryWidgetState extends State<MonthlySummaryWidget> {
  final DatabaseService _databaseService = DatabaseService();
  Map<String, double> _monthlySpending = {};
  List<String> _months = [];
  int _currentMonthIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonthlyData();
  }

  void refreshData() {
    _loadMonthlyData();
  }

  Future<void> _loadMonthlyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final monthlyData = await _databaseService.getMonthlySpending();
      setState(() {
        _monthlySpending = monthlyData;
        _months = monthlyData.keys.toList();
        _currentMonthIndex = 0; // Start with the most recent month
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatMonth(String monthKey) {
    try {
      final date = DateTime.parse('$monthKey-01');
      return DateFormat('MMMM yyyy').format(date);
    } catch (e) {
      return monthKey;
    }
  }

  void _previousMonth() {
    if (_currentMonthIndex < _months.length - 1) {
      setState(() {
        _currentMonthIndex++;
      });
    }
  }

  void _nextMonth() {
    if (_currentMonthIndex > 0) {
      setState(() {
        _currentMonthIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_months.isEmpty) {
      return const SizedBox.shrink(); // Don't show anything if no data
    }

    final currentMonth = _months[_currentMonthIndex];
    final currentSpending = _monthlySpending[currentMonth] ?? 0.0;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Spending Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _currentMonthIndex < _months.length - 1
                      ? _previousMonth
                      : null,
                  icon: const Icon(Icons.arrow_left),
                  tooltip: 'Previous month',
                ),
                Expanded(
                  child: Column(
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
                      Text(
                        '${NumberFormat('#,###').format(currentSpending.round())} Rwf',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _currentMonthIndex > 0 ? _nextMonth : null,
                  icon: const Icon(Icons.arrow_right),
                  tooltip: 'Next month',
                ),
              ],
            ),
            if (_months.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentMonthIndex + 1} of ${_months.length}',
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
    );
  }
}
