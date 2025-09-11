import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/price_history.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PriceHistory> _allHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final history = await _databaseService.getAllPriceHistory();
      setState(() {
        _allHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: $e')),
        );
      }
    }
  }

  Map<String, List<PriceHistory>> _groupHistoryByDate() {
    final Map<String, List<PriceHistory>> grouped = {};

    for (final history in _allHistory) {
      final dateKey = DateFormat('MMM dd, yyyy').format(history.recordedAt);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(history);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Price History'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No price history yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add items and update their prices to see history',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _buildHistoryGroups(),
                  ),
                ),
    );
  }

  List<Widget> _buildHistoryGroups() {
    final groupedHistory = _groupHistoryByDate();
    final sortedDates = groupedHistory.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('MMM dd, yyyy').parse(a);
        final dateB = DateFormat('MMM dd, yyyy').parse(b);
        return dateB.compareTo(dateA); // Most recent first
      });

    final List<Widget> widgets = [];

    for (final date in sortedDates) {
      final historyForDate = groupedHistory[date]!;

      // Sort history for this date by time (most recent first)
      historyForDate.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      // Add date header
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            date,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
      );

      // Add history items for this date
      for (final history in historyForDate) {
        widgets.add(_buildHistoryItem(history));
      }

      widgets.add(const SizedBox(height: 16));
    }

    return widgets;
  }

  Widget _buildHistoryItem(PriceHistory history) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Text(
            'Rwf',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            const Text('Price Update'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                DateFormat('HH:mm').format(history.recordedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: Text(
          '${NumberFormat('#,###').format(history.price.round())} Rwf',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ),
    );
  }
}
