import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'item_detail_screen.dart';

class _UpcomingItem {
  final Item item;
  final DateTime expectedDate;
  final double price;

  const _UpcomingItem({
    required this.item,
    required this.expectedDate,
    required this.price,
  });
}

class UpcomingPurchasesScreen extends StatefulWidget {
  const UpcomingPurchasesScreen({super.key});

  @override
  State<UpcomingPurchasesScreen> createState() =>
      _UpcomingPurchasesScreenState();
}

class _UpcomingPurchasesScreenState extends State<UpcomingPurchasesScreen> {
  final DatabaseService _db = DatabaseService();
  bool _isLoading = true;

  Map<String, List<_UpcomingItem>> _byMonth = {};
  List<String> _monthOrder = [];
  int _initialTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _daysBetween(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return db.difference(da).inDays.abs();
  }

  int _naiveAvgCycleDays(List<dynamic> manual) {
    int total = 0;
    for (int i = 1; i < manual.length; i++) {
      total += _daysBetween(manual[i - 1].recordedAt, manual[i].recordedAt);
    }
    return (total / (manual.length - 1)).round();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final items = await _db.getAllItems();
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      final Map<String, List<_UpcomingItem>> byMonth = {};

      for (final item in items) {
        if (item.isPriceOnly) continue;

        final history = await _db.getPriceHistory(item.id!);
        final manual = history
            .where((e) => e.entryType == 'manual' && e.subItemId == null)
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

        if (manual.length < 2) continue;

        final lastEntry = manual.last;
        final lastPurchase = DateTime(
          lastEntry.recordedAt.year,
          lastEntry.recordedAt.month,
          lastEntry.recordedAt.day,
        );

        // --- Quantity-aware cycle estimation ---
        // Compute avgDailyUsage from all completed purchases (everything except
        // the most recent, which is still ongoing).
        double totalConsumed = 0.0;
        int totalQtyDays = 0;

        for (int i = 0; i < manual.length - 1; i++) {
          final entry = manual[i];
          if (entry.quantityPurchased == null) continue;

          // End date: explicit finishedAt or next entry's start date
          final endDate = entry.finishedAt ?? manual[i + 1].recordedAt;
          final days = _daysBetween(entry.recordedAt, endDate);
          if (days <= 0) continue;

          // Resolve effective remaining (same logic as getPurchaseCycleStats)
          final double effectiveRemaining;
          if (entry.quantityRemaining != null) {
            effectiveRemaining = entry.quantityRemaining!;
          } else if (entry.quantityConsumed != null) {
            effectiveRemaining =
                (entry.quantityPurchased! - entry.quantityConsumed!)
                    .clamp(0.0, entry.quantityPurchased!);
          } else {
            effectiveRemaining = 0.0;
          }

          final consumed = entry.quantityPurchased! - effectiveRemaining;
          if (consumed > 0) {
            totalConsumed += consumed;
            totalQtyDays += days;
          }
        }

        // Use quantity-proportional estimate when data is available
        int estimatedCycleDays;
        if (totalQtyDays > 0 && lastEntry.quantityPurchased != null) {
          final avgDailyUsage = totalConsumed / totalQtyDays;
          if (avgDailyUsage > 0) {
            estimatedCycleDays =
                (lastEntry.quantityPurchased! / avgDailyUsage).round();
          } else {
            estimatedCycleDays = _naiveAvgCycleDays(manual);
          }
        } else {
          // Fallback: naive date-gap average
          estimatedCycleDays = _naiveAvgCycleDays(manual);
        }

        DateTime expectedDate =
            lastPurchase.add(Duration(days: estimatedCycleDays));

        if (expectedDate.isBefore(todayDate)) {
          expectedDate = todayDate;
        }

        final monthKey =
            '${expectedDate.year}-${expectedDate.month.toString().padLeft(2, '0')}';

        byMonth.putIfAbsent(monthKey, () => []).add(_UpcomingItem(
              item: item,
              expectedDate: expectedDate,
              price: item.currentPrice,
            ));
      }

      final orderedKeys = byMonth.keys.toList()..sort();

      for (final key in orderedKeys) {
        byMonth[key]!.sort((a, b) {
          final dateCmp = a.expectedDate.compareTo(b.expectedDate);
          return dateCmp != 0 ? dateCmp : a.item.name.compareTo(b.item.name);
        });
      }

      // Default to current month tab
      final now = DateTime.now();
      final currentKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final initialIndex = orderedKeys.indexOf(currentKey);

      setState(() {
        _byMonth = byMonth;
        _monthOrder = orderedKeys;
        _initialTabIndex = initialIndex >= 0 ? initialIndex : 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  String _tabLabel(String key) {
    final month = int.parse(key.split('-')[1]);
    const short = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return short[month - 1];
  }

  String _formatMonthKey(String key) {
    final parts = key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month - 1]} $year';
  }

  String _formatDate(DateTime date) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == todayDate) return 'Today';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatAmount(double amount) {
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k Rwf';
    }
    return '${amount.toStringAsFixed(0)} Rwf';
  }

  bool _isCurrentMonth(String key) {
    final now = DateTime.now();
    return key == '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            child: AppBar(
              title: const Text('Upcoming Purchases'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_monthOrder.isEmpty) {
      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            child: AppBar(
              title: const Text('Upcoming Purchases'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
          ),
        ),
        body: _buildEmpty(),
      );
    }

    return DefaultTabController(
      length: _monthOrder.length,
      initialIndex: _initialTabIndex,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Container(
            decoration:
                const BoxDecoration(gradient: AppColors.primaryGradient),
            child: AppBar(
              title: const Text('Upcoming Purchases'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              bottom: TabBar(
                tabs: _monthOrder
                    .map((key) => Tab(text: _tabLabel(key)))
                    .toList(),
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: _monthOrder.map((key) => _buildMonthTab(key)).toList(),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_outlined,
              size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No upcoming purchases',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add at least 2 purchase records per item\nto enable cycle prediction',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthTab(String key) {
    final entries = _byMonth[key]!;
    final monthTotal = entries.fold(0.0, (sum, e) => sum + e.price);
    final isCurrent = _isCurrentMonth(key);

    // Group by date
    final Map<String, List<_UpcomingItem>> byDate = {};
    for (final entry in entries) {
      final dateKey =
          '${entry.expectedDate.year}-${entry.expectedDate.month.toString().padLeft(2, '0')}-${entry.expectedDate.day.toString().padLeft(2, '0')}';
      byDate.putIfAbsent(dateKey, () => []).add(entry);
    }
    final dateKeys = byDate.keys.toList()..sort();

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: isCurrent
                ? AppColors.primaryGradient
                : const LinearGradient(
                    colors: [Color(0xFF607D8B), Color(0xFF78909C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isCurrent
                        ? AppColors.primaryStart
                        : const Color(0xFF607D8B))
                    .withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCurrent ? 'This Month' : 'Expected Total',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatMonthKey(key),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatAmount(monthTotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${entries.length} item${entries.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: dateKeys.length,
            itemBuilder: (context, i) {
              final dateKey = dateKeys[i];
              final dateEntries = byDate[dateKey]!;
              final subtotal =
                  dateEntries.fold(0.0, (sum, e) => sum + e.price);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateHeader(
                      dateEntries.first.expectedDate, isCurrent, subtotal),
                  ...dateEntries.map((e) => _buildItemCard(e, isCurrent)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateHeader(
      DateTime date, bool isCurrent, double subtotal) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    final Color pillColor = isToday
        ? const Color(0xFFF44336)
        : isCurrent
            ? AppColors.primaryStart
            : const Color(0xFF607D8B);

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatDate(date),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
                color: Colors.grey[300], height: 1, thickness: 1),
          ),
          const SizedBox(width: 10),
          Text(
            _formatAmount(subtotal),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isToday
                  ? const Color(0xFFF44336)
                  : isCurrent
                      ? AppColors.primaryStart
                      : const Color(0xFF607D8B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(_UpcomingItem entry, bool isCurrent) {
    final now = DateTime.now();
    final isToday = entry.expectedDate.year == now.year &&
        entry.expectedDate.month == now.month &&
        entry.expectedDate.day == now.day;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ItemDetailScreen(item: entry.item),
              ),
            ).then((_) => _loadData());
          },
          child: Row(
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  gradient: isToday
                      ? const LinearGradient(
                          colors: [Color(0xFFF44336), Color(0xFFEF5350)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : isCurrent
                          ? const LinearGradient(
                              colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : AppColors.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (entry.item.description != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                entry.item.description!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatAmount(entry.price),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isCurrent
                                  ? AppColors.primaryStart
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
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
  }
}
