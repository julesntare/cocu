import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/price_history.dart';
import '../services/database_service.dart';
import '../widgets/finish_date_popup.dart';

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

  List<PriceHistory> _getSortedHistory() {
    // Sort all history by recordedAt in descending order (most recent first)
    final sortedHistory = List<PriceHistory>.from(_allHistory);
    sortedHistory.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sortedHistory;
  }

  List<Widget> _buildHistoryWithGaps() {
    final sortedHistory = _getSortedHistory();
    final List<Widget> widgets = [];

    if (sortedHistory.isEmpty) return widgets;

    for (int i = 0; i < sortedHistory.length; i++) {
      final currentHistory = sortedHistory[i];
      
      // Add the current history item
      widgets.add(_buildHistoryItem(currentHistory));
    }

    return widgets;
  }



  Future<void> _markAsFinished(PriceHistory history) async {
    final DateTime? finishedDate = await showDialog<DateTime?>(
      context: context,
      builder: (context) => FinishDatePopup(
        initialDate: DateTime.now(),
        onDateSelected: (date) => date,
      ),
    );

    if (finishedDate != null) {
      try {
        await _databaseService.updatePriceHistoryFinishedAt(history.id!, finishedDate);
        
        // Reload the data to reflect changes
        await _loadHistory();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Record marked as finished on ${DateFormat('MMM dd, yyyy').format(finishedDate)}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error marking as finished: $e')),
          );
        }
      }
    }
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
                    children: _buildHistoryWithGaps(),
                  ),
                ),
    );
  }



  String _formatTimeDifference(DateTime startDate, DateTime endDate) {
    final difference = endDate.difference(startDate);
    final days = difference.inDays;
    
    if (days == 0) {
      return 'Less than a day';
    } else if (days == 1) {
      return '1 day';
    } else if (days <= 30) {
      return '$days days';
    } else if (days <= 60) {
      final weeks = (days / 7).round();
      if (weeks == 1) {
        return '1 week';
      } else {
        return '$weeks weeks';
      }
    } else {
      final months = (days / 30).floor();
      final remainingDays = days % 30;
      
      if (remainingDays == 0) {
        return months == 1 ? '1 month' : '$months months';
      } else {
        return '$months month${months > 1 ? 's' : ''} and $remainingDays day${remainingDays != 1 ? 's' : ''}';
      }
    }
  }

  Widget _buildHistoryItem(PriceHistory history) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: history.finishedAt != null ? Colors.green : Colors.grey,
          child: Text(
            'Rwf',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            if (history.finishedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '(Finished after ${_formatTimeDifference(history.recordedAt, history.finishedAt!)})',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF2E7D32),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Finished: ${DateFormat('MMM dd, yyyy').format(history.finishedAt!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (history.finishedAt == null) // Only show mark as finished if not already marked
              IconButton(
                icon: const Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: Colors.green,
                ),
                onPressed: () => _markAsFinished(history),
                tooltip: 'Mark as finished',
              ),
            Text(
              '${NumberFormat('#,###').format(history.price.round())} Rwf',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
