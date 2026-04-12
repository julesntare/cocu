import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import '../models/item.dart';
import '../models/price_history.dart';
import '../models/sub_item.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    _database ??= await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    const storage = FlutterSecureStorage();
    String? dbKey = await storage.read(key: 'db_encryption_key');
    if (dbKey == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      dbKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await storage.write(key: 'db_encryption_key', value: dbKey);
    }

    final path = join(await getDatabasesPath(), 'cocu.db');
    try {
      _database = await openDatabase(
        path,
        password: dbKey,
        version: 11,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
      );
    } catch (_) {
      // Existing unencrypted database — delete it and create a fresh encrypted one.
      final dbFile = File(path);
      if (await dbFile.exists()) await dbFile.delete();
      _database = await openDatabase(
        path,
        password: dbKey,
        version: 11,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
      );
    }
    return _database!;
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        current_price REAL NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        track_usage INTEGER DEFAULT 0,
        usage_unit TEXT,
        is_price_only INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sub_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        current_price REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        track_usage INTEGER DEFAULT 0,
        usage_unit TEXT,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        sub_item_id INTEGER,
        price REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        finished_at TEXT,
        entry_type TEXT NOT NULL DEFAULT 'manual',
        description TEXT,
        quantity_purchased REAL,
        quantity_remaining REAL,
        quantity_consumed REAL,
        remaining_updated_at TEXT,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE,
        FOREIGN KEY (sub_item_id) REFERENCES sub_items (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Remove category column from items table
      await db.execute('''
        CREATE TABLE items_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          current_price REAL NOT NULL,
          description TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // Copy data without category column
      await db.execute('''
        INSERT INTO items_new (id, name, current_price, description, created_at, updated_at)
        SELECT id, name, current_price, description, created_at, updated_at FROM items
      ''');

      // Drop old table and rename new one
      await db.execute('DROP TABLE items');
      await db.execute('ALTER TABLE items_new RENAME TO items');
    }

    if (oldVersion < 3) {
      // Add new fields to price_history table
      try {
        await db
            .execute('ALTER TABLE price_history ADD COLUMN created_at TEXT');
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN entry_type TEXT DEFAULT "manual"');

        // Update existing records to set proper values
        await db.execute('''
          UPDATE price_history 
          SET created_at = recorded_at, 
              entry_type = CASE 
                WHEN note = "Price updated" THEN "automatic" 
                ELSE "manual" 
              END
          WHERE created_at IS NULL
        ''');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 3: $e');
      }
    }

    if (oldVersion < 4) {
      // Remove note field from price_history table
      try {
        // Create new table without note field
        await db.execute('''
          CREATE TABLE price_history_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            price REAL NOT NULL,
            recorded_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            entry_type TEXT NOT NULL DEFAULT 'manual',
            FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
          )
        ''');

        // Copy data without note field
        await db.execute('''
          INSERT INTO price_history_new (id, item_id, price, recorded_at, created_at, entry_type)
          SELECT id, item_id, price, recorded_at, created_at, entry_type FROM price_history
        ''');

        // Drop old table and rename new one
        await db.execute('DROP TABLE price_history');
        await db
            .execute('ALTER TABLE price_history_new RENAME TO price_history');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 4: $e');
      }
    }

    if (oldVersion < 5) {
      // Add finished_at field to price_history table
      try {
        await db
            .execute('ALTER TABLE price_history ADD COLUMN finished_at TEXT');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 5: $e');
      }
    }

    if (oldVersion < 6) {
      // Add sub_items table and sub_item_id to price_history
      try {
        // Create sub_items table
        await db.execute('''
          CREATE TABLE sub_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            current_price REAL NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
          )
        ''');

        // Add sub_item_id column to price_history
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN sub_item_id INTEGER');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 6: $e');
      }
    }

    if (oldVersion < 7) {
      // Add description column to price_history
      try {
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN description TEXT');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 7: $e');
      }
    }

    if (oldVersion < 8) {
      // Add usage tracking fields
      try {
        await db.execute(
            'ALTER TABLE items ADD COLUMN track_usage INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE items ADD COLUMN usage_unit TEXT');
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN quantity_purchased REAL');
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN quantity_remaining REAL');
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN quantity_consumed REAL');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 8: $e');
      }
    }

    if (oldVersion < 9) {
      // Add track_usage to sub_items
      try {
        await db.execute(
            'ALTER TABLE sub_items ADD COLUMN track_usage INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE sub_items ADD COLUMN usage_unit TEXT');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 9: $e');
      }
    }

    if (oldVersion < 10) {
      // Add remaining_updated_at to track when quantity_remaining was last manually set
      try {
        await db.execute(
            'ALTER TABLE price_history ADD COLUMN remaining_updated_at TEXT');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 10: $e');
      }
    }

    if (oldVersion < 11) {
      // Add is_price_only flag to items (pure price-history tracker, no cycle tracking)
      try {
        await db.execute(
            'ALTER TABLE items ADD COLUMN is_price_only INTEGER DEFAULT 0');
      } catch (e) {
        if (kDebugMode) debugPrint('Error upgrading database to version 11: $e');
      }
    }
  }

  // Item CRUD operations
  Future<int> insertItem(Item item) async {
    final db = await database;
    final id = await db.insert('items', item.toMap());

    // Insert initial price history
    await insertPriceHistory(PriceHistory(
      itemId: id,
      price: item.currentPrice,
      recordedAt: item.createdAt,
      createdAt: DateTime.now(),
      entryType: 'manual',
    ));

    return id;
  }

  Future<List<Item>> getAllItems() async {
    final db = await database;
    final maps = await db.query('items', orderBy: 'updated_at DESC');
    return maps.map((map) => Item.fromMap(map)).toList();
  }

  Future<Item?> getItemById(int id) async {
    final db = await database;
    final maps = await db.query('items', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Item.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Item>> searchItems(String query) async {
    final db = await database;
    final maps = await db.query(
      'items',
      where: 'name LIKE ? OR description LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => Item.fromMap(map)).toList();
  }

  Future<int> updateItem(Item item) async {
    final db = await database;

    // Get the old item to check if price changed
    final oldItem = await getItemById(item.id!);
    if (oldItem != null && oldItem.currentPrice != item.currentPrice) {
      // Insert new price history with automatic entry type
      await insertPriceHistory(PriceHistory(
        itemId: item.id!,
        price: item.currentPrice,
        recordedAt: item.updatedAt,
        createdAt: DateTime.now(),
        entryType: 'automatic',
      ));
    }

    return await db.update(
      'items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  // Price History operations
  Future<int> insertPriceHistory(PriceHistory priceHistory) async {
    final db = await database;
    return await db.insert('price_history', priceHistory.toMap());
  }

  Future<int> updatePriceHistory(PriceHistory priceHistory) async {
    final db = await database;
    return await db.update(
      'price_history',
      priceHistory.toMap(),
      where: 'id = ?',
      whereArgs: [priceHistory.id],
    );
  }

  Future<int> updatePriceHistoryFinishedAt(int id, DateTime? finishedAt) async {
    final db = await database;
    return await db.update(
      'price_history',
      {'finished_at': finishedAt?.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get the most recent ongoing purchase (no finishedAt) for an item or sub-item
  Future<PriceHistory?> getMostRecentOngoingPurchase(int itemId, {int? subItemId}) async {
    final db = await database;
    String whereClause = 'item_id = ? AND finished_at IS NULL AND entry_type = ?';
    List<dynamic> whereArgs = [itemId, 'manual'];

    if (subItemId != null) {
      whereClause += ' AND sub_item_id = ?';
      whereArgs.add(subItemId);
    } else {
      whereClause += ' AND sub_item_id IS NULL';
    }

    final maps = await db.query(
      'price_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'recorded_at DESC',
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return PriceHistory.fromMap(maps.first);
    }
    return null;
  }

  // Finish an ongoing purchase by setting finishedAt.
  // - If quantity_remaining or quantity_consumed is already set (manual edit),
  //   preserve those values and only update finished_at.
  // - If no quantity data exists but quantity_purchased is set,
  //   estimate remaining using historical avg daily usage pattern.
  // - Otherwise, fall back to setting remaining = 0.
  Future<int> finishOngoingPurchase(
    int id,
    DateTime finishedAt, {
    int? itemId,
    int? subItemId,
  }) async {
    final db = await database;

    // Fetch the current purchase record
    final maps = await db.query(
      'price_history',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return 0;

    final purchase = PriceHistory.fromMap(maps.first);

    // Case A: User already has manual remaining/consumed — only update finishedAt
    if (purchase.quantityRemaining != null || purchase.quantityConsumed != null) {
      return await db.update(
        'price_history',
        {'finished_at': finishedAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // Case B: Has quantityPurchased — estimate remaining via historical pattern
    if (purchase.quantityPurchased != null && itemId != null) {
      final historicalAvg = await _computeHistoricalAvgDailyUsage(
        itemId,
        subItemId: subItemId,
        excludeId: id,
      );

      if (historicalAvg != null && historicalAvg > 0) {
        final days = _daysBetween(purchase.recordedAt, finishedAt);
        final estimatedConsumed = historicalAvg * days;
        final estimatedRemaining = purchase.quantityPurchased! - estimatedConsumed;

        return await db.update(
          'price_history',
          {
            'quantity_remaining': estimatedRemaining < 0 ? 0.0 : estimatedRemaining,
            'finished_at': finishedAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    // Case C: No quantity data or no historical pattern — fall back to remaining = 0
    return await db.update(
      'price_history',
      {
        'quantity_remaining': 0.0,
        'finished_at': finishedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePriceHistory(int id) async {
    final db = await database;
    return await db.delete(
      'price_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PriceHistory>> getPriceHistory(int itemId,
      {bool includeSubItems = true}) async {
    final db = await database;
    String whereClause = 'item_id = ?';
    List<dynamic> whereArgs = [itemId];

    if (!includeSubItems) {
      whereClause += ' AND sub_item_id IS NULL';
    }

    final maps = await db.query(
      'price_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'recorded_at ASC',
    );
    return maps.map((map) => PriceHistory.fromMap(map)).toList();
  }

  Future<List<PriceHistory>> getAllPriceHistory() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT ph.*, i.name as item_name 
      FROM price_history ph 
      JOIN items i ON ph.item_id = i.id 
      ORDER BY ph.recorded_at DESC
    ''');
    return maps.map((map) => PriceHistory.fromMap(map)).toList();
  }

  Future<Map<String, double>> getMonthlySpending() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        strftime('%Y-%m', recorded_at) as month,
        SUM(price) as total
      FROM price_history
      WHERE entry_type = 'manual'
      GROUP BY strftime('%Y-%m', recorded_at)
      ORDER BY month DESC
    ''');

    Map<String, double> monthlySpending = {};
    for (var map in maps) {
      monthlySpending[map['month'] as String] =
          (map['total'] as num).toDouble();
    }
    return monthlySpending;
  }

  Future<Map<String, Map<String, double>>> getMonthlySpendingPerItem() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        strftime('%Y-%m', ph.recorded_at) as month,
        i.name as item_name,
        COUNT(*) as frequency,
        SUM(ph.price) as total_spent
      FROM price_history ph
      JOIN items i ON ph.item_id = i.id
      GROUP BY strftime('%Y-%m', ph.recorded_at), i.name
      HAVING COUNT(*) > 1
      ORDER BY month DESC, total_spent DESC
    ''');

    Map<String, Map<String, double>> monthlySpendingPerItem = {};
    for (var map in maps) {
      final month = map['month'] as String;
      final itemName = map['item_name'] as String;
      final totalSpent = (map['total_spent'] as num).toDouble();

      if (!monthlySpendingPerItem.containsKey(month)) {
        monthlySpendingPerItem[month] = {};
      }
      monthlySpendingPerItem[month]![itemName] = totalSpent;
    }
    return monthlySpendingPerItem;
  }

  Future<Map<String, Map<String, dynamic>>> getMonthlySpendingForItem(
      int itemId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        strftime('%Y-%m', recorded_at) as month,
        COUNT(*) as frequency,
        SUM(price) as total_spent
      FROM price_history
      WHERE item_id = ? AND entry_type = 'manual'
      GROUP BY strftime('%Y-%m', recorded_at)
      ORDER BY month DESC
    ''', [itemId]);

    Map<String, Map<String, dynamic>> monthlySpending = {};
    for (var map in maps) {
      final month = map['month'] as String;
      monthlySpending[month] = {
        'frequency': map['frequency'] as int,
        'total_spent': (map['total_spent'] as num).toDouble(),
      };
    }
    return monthlySpending;
  }

  Future<List<Map<String, dynamic>>> getMonthlyItems(String monthKey) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        i.name as item_name,
        SUM(ph.price) as total_amount
      FROM price_history ph
      JOIN items i ON ph.item_id = i.id
      WHERE strftime('%Y-%m', ph.recorded_at) = ? AND ph.entry_type = 'manual'
      GROUP BY i.id, i.name
      ORDER BY total_amount DESC
    ''', [monthKey]);

    return maps
        .map((map) => {
              'name': map['item_name'] as String,
              'amount': (map['total_amount'] as num).toDouble(),
            })
        .toList();
  }

  // SubItem CRUD operations
  Future<int> insertSubItem(SubItem subItem) async {
    final db = await database;
    final id = await db.insert('sub_items', subItem.toMap());

    // Insert initial price history for sub-item
    await insertPriceHistory(PriceHistory(
      itemId: subItem.itemId,
      subItemId: id,
      price: subItem.currentPrice,
      recordedAt: subItem.createdAt,
      createdAt: DateTime.now(),
      entryType: 'manual',
    ));

    return id;
  }

  Future<List<SubItem>> getSubItemsByItemId(int itemId) async {
    final db = await database;
    final maps = await db.query(
      'sub_items',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'created_at ASC',
    );
    return maps.map((map) => SubItem.fromMap(map)).toList();
  }

  Future<SubItem?> getSubItemById(int id) async {
    final db = await database;
    final maps = await db.query('sub_items', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return SubItem.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateSubItem(SubItem subItem) async {
    final db = await database;

    // Get the old sub-item to check if price changed
    final oldSubItem = await getSubItemById(subItem.id!);
    if (oldSubItem != null && oldSubItem.currentPrice != subItem.currentPrice) {
      // Insert new price history with automatic entry type
      await insertPriceHistory(PriceHistory(
        itemId: subItem.itemId,
        subItemId: subItem.id!,
        price: subItem.currentPrice,
        recordedAt: subItem.updatedAt,
        createdAt: DateTime.now(),
        entryType: 'automatic',
      ));
    }

    return await db.update(
      'sub_items',
      subItem.toMap(),
      where: 'id = ?',
      whereArgs: [subItem.id],
    );
  }

  Future<int> deleteSubItem(int id) async {
    final db = await database;
    return await db.delete('sub_items', where: 'id = ?', whereArgs: [id]);
  }

  // Get price history for a specific sub-item
  Future<List<PriceHistory>> getPriceHistoryForSubItem(
      int itemId, int subItemId) async {
    final db = await database;
    final maps = await db.query(
      'price_history',
      where: 'item_id = ? AND sub_item_id = ?',
      whereArgs: [itemId, subItemId],
      orderBy: 'recorded_at ASC',
    );
    return maps.map((map) => PriceHistory.fromMap(map)).toList();
  }

  // Get monthly spending for a specific sub-item
  Future<Map<String, Map<String, dynamic>>> getMonthlySpendingForSubItem(
      int itemId, int subItemId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        strftime('%Y-%m', recorded_at) as month,
        COUNT(*) as frequency,
        SUM(price) as total_spent
      FROM price_history
      WHERE item_id = ? AND sub_item_id = ? AND entry_type = 'manual'
      GROUP BY strftime('%Y-%m', recorded_at)
      ORDER BY month DESC
    ''', [itemId, subItemId]);

    Map<String, Map<String, dynamic>> monthlySpending = {};
    for (var map in maps) {
      final month = map['month'] as String;
      monthlySpending[month] = {
        'frequency': map['frequency'] as int,
        'total_spent': (map['total_spent'] as num).toDouble(),
      };
    }
    return monthlySpending;
  }

  // Usage tracking methods

  // Get usage entries for an item (entries with quantity data)
  Future<List<PriceHistory>> getUsageHistory(int itemId) async {
    final db = await database;
    final maps = await db.query(
      'price_history',
      where:
          'item_id = ? AND (quantity_purchased IS NOT NULL OR quantity_remaining IS NOT NULL OR quantity_consumed IS NOT NULL)',
      whereArgs: [itemId],
      orderBy: 'recorded_at ASC',
    );
    return maps.map((map) => PriceHistory.fromMap(map)).toList();
  }

  // Get the latest remaining quantity for an item.
  // Prefers entries with a direct quantity_remaining; falls back to deriving
  // remaining from quantity_purchased - quantity_consumed when available.
  Future<double?> getLatestRemainingQuantity(int itemId) async {
    final db = await database;

    // First: entries with directly recorded remaining
    final mapsWithRemaining = await db.query(
      'price_history',
      where: 'item_id = ? AND quantity_remaining IS NOT NULL',
      whereArgs: [itemId],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    if (mapsWithRemaining.isNotEmpty) {
      return (mapsWithRemaining.first['quantity_remaining'] as num?)?.toDouble();
    }

    // Fallback: derive remaining from consumed when both fields are present
    final mapsWithConsumed = await db.query(
      'price_history',
      where:
          'item_id = ? AND quantity_consumed IS NOT NULL AND quantity_purchased IS NOT NULL',
      whereArgs: [itemId],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    if (mapsWithConsumed.isNotEmpty) {
      final purchased =
          (mapsWithConsumed.first['quantity_purchased'] as num?)?.toDouble();
      final consumed =
          (mapsWithConsumed.first['quantity_consumed'] as num?)?.toDouble();
      if (purchased != null && consumed != null) {
        return (purchased - consumed).clamp(0.0, purchased);
      }
    }

    return null;
  }

  // Calculate overall average daily usage across all completed purchases
  // Uses recordedAt (purchase date) and finishedAt (end date) from each entry
  //
  // Example: Milk carton with 12 pieces
  // - Purchase entry: recordedAt = Jan 1, finishedAt = Jan 10, quantityPurchased = 12, quantityRemaining = 3
  // - Consumed = 12 - 3 = 9 pieces over 9 days
  // - Avg daily usage = 9/9 = 1 piece/day
  Future<Map<String, dynamic>> calculateUsageStats(int itemId) async {
    final purchases = await getPurchaseCycleStats(itemId);

    if (purchases.isEmpty) {
      return {
        'avgDailyUsage': 0.0,
        'totalConsumed': 0.0,
        'totalPurchased': 0.0,
        'daysTracked': 0,
        'latestRemaining': null,
        'estimatedDaysRemaining': null,
        'completedPurchases': 0,
      };
    }

    double totalConsumed = 0.0;
    double totalPurchased = 0.0;
    int totalDaysTracked = 0;
    int completedPurchases = 0;
    double? latestRemaining;

    for (final purchase in purchases) {
      totalPurchased += (purchase['quantityPurchased'] as double?) ?? 0.0;

      // Only count completed purchases for average calculation
      if (purchase['isComplete'] == true) {
        final consumed = purchase['consumed'] as double?;
        final days = purchase['daysTracked'] as int;

        if (consumed != null && consumed > 0 && days > 0) {
          totalConsumed += consumed;
          totalDaysTracked += days;
          completedPurchases++;
        }
      }

      // Track latest remaining (first in list is most recent)
      if (latestRemaining == null && purchase['quantityRemaining'] != null) {
        latestRemaining = purchase['quantityRemaining'] as double;
      }
    }

    // Calculate overall average daily usage
    double avgDailyUsage = totalDaysTracked > 0 ? totalConsumed / totalDaysTracked : 0.0;

    // Estimate days remaining based on overall average
    int? estimatedDaysRemaining;
    if (latestRemaining != null && avgDailyUsage > 0) {
      estimatedDaysRemaining = (latestRemaining / avgDailyUsage).floor();
    }

    return {
      'avgDailyUsage': avgDailyUsage,
      'totalConsumed': totalConsumed,
      'totalPurchased': totalPurchased,
      'daysTracked': totalDaysTracked,
      'latestRemaining': latestRemaining,
      'estimatedDaysRemaining': estimatedDaysRemaining,
      'completedPurchases': completedPurchases,
    };
  }

  // Helper to calculate days between two dates (calendar days, not 24h periods)
  int _daysBetween(DateTime start, DateTime end) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    final days = endDate.difference(startDate).inDays;
    return days < 0 ? 0 : days;
  }

  // Returns historical average daily usage from all COMPLETED purchase cycles
  // for [itemId] (and optionally [subItemId]), excluding the record [excludeId]
  // (the one currently being closed, which is not yet completed).
  // Returns null if there is no usable historical data.
  Future<double?> _computeHistoricalAvgDailyUsage(
    int itemId, {
    int? subItemId,
    int? excludeId,
  }) async {
    final db = await database;

    String whereClause;
    List<dynamic> whereArgs;

    if (subItemId != null) {
      whereClause =
          'item_id = ? AND sub_item_id = ? AND entry_type = ? AND finished_at IS NOT NULL';
      whereArgs = [itemId, subItemId, 'manual'];
    } else {
      whereClause =
          'item_id = ? AND sub_item_id IS NULL AND entry_type = ? AND finished_at IS NOT NULL';
      whereArgs = [itemId, 'manual'];
    }

    final maps = await db.query(
      'price_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'recorded_at DESC',
    );

    double totalConsumed = 0.0;
    int totalDays = 0;
    double? defaultQtyPurchased;

    // Find most recent quantityPurchased to use as fallback for entries missing it
    for (final map in maps) {
      final entry = PriceHistory.fromMap(map);
      if (entry.id == excludeId) continue;
      if (entry.quantityPurchased != null) {
        defaultQtyPurchased = entry.quantityPurchased;
        break;
      }
    }

    for (final map in maps) {
      final entry = PriceHistory.fromMap(map);
      if (entry.id == excludeId) continue;

      final qtyPurchased = entry.quantityPurchased ?? defaultQtyPurchased;
      final finishedAt = entry.finishedAt;

      if (qtyPurchased != null && finishedAt != null) {
        final days = _daysBetween(entry.recordedAt, finishedAt);

        // Resolve effective remaining: prefer stored remaining, else derive from consumed
        final double effectiveRemaining;
        if (entry.quantityRemaining != null) {
          effectiveRemaining = entry.quantityRemaining!;
        } else if (entry.quantityConsumed != null) {
          effectiveRemaining = (qtyPurchased - entry.quantityConsumed!).clamp(0.0, qtyPurchased);
        } else {
          effectiveRemaining = 0.0;
        }

        final consumed = qtyPurchased - effectiveRemaining;
        if (consumed > 0 && days > 0) {
          totalConsumed += consumed;
          totalDays += days;
        }
      }
    }

    return totalDays > 0 ? totalConsumed / totalDays : null;
  }

  // Get all purchase entries for an item with usage tracking enabled
  // Each manual price entry is a purchase period
  // Uses recordedAt (purchase date) and finishedAt (end date) from the entry
  // Returns list sorted by date, most recent first (index 0)
  Future<List<Map<String, dynamic>>> getPurchaseCycleStats(int itemId, {int? subItemId}) async {
    final db = await database;

    // Get ALL manual entries for this item/sub-item (not just ones with quantity)
    String whereClause;
    List<dynamic> whereArgs;

    if (subItemId != null) {
      whereClause = 'item_id = ? AND sub_item_id = ? AND entry_type = ?';
      whereArgs = [itemId, subItemId, 'manual'];
    } else {
      whereClause = 'item_id = ? AND sub_item_id IS NULL AND entry_type = ?';
      whereArgs = [itemId, 'manual'];
    }

    final maps = await db.query(
      'price_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'recorded_at DESC', // Most recent first
    );

    if (maps.isEmpty) {
      return [];
    }

    List<Map<String, dynamic>> purchases = [];

    // First pass: find the default quantityPurchased from entries that have it
    double? defaultQuantityPurchased;
    for (final map in maps) {
      final entry = PriceHistory.fromMap(map);
      if (entry.quantityPurchased != null) {
        defaultQuantityPurchased = entry.quantityPurchased;
        break; // Use the most recent one (list is sorted DESC)
      }
    }

    // Second pass: calculate historical average from completed purchases
    // We need this first to apply pattern to ongoing purchases
    double historicalTotalConsumed = 0.0;
    int historicalTotalDays = 0;

    for (int i = 0; i < maps.length; i++) {
      final entry = PriceHistory.fromMap(maps[i]);
      final purchaseDate = entry.recordedAt;
      DateTime? endDate = entry.finishedAt;

      // Infer end date from newer purchase if not set
      if (endDate == null && i > 0) {
        final newerEntry = PriceHistory.fromMap(maps[i - 1]);
        endDate = newerEntry.recordedAt;
      }

      // Only count completed purchases with their own quantityPurchased for accuracy
      // (skip fallback entries to avoid skewing the average with borrowed quantities)
      if (endDate != null && entry.quantityPurchased != null) {
        final days = _daysBetween(purchaseDate, endDate);
        final qtyPurchased = entry.quantityPurchased!;

        // Resolve effective remaining. If the cycle ended because the next
        // purchase was recorded (no finishedAt), any stored remaining was a
        // mid-cycle checkpoint — treat as fully consumed (remaining = 0).
        final double effectiveRemaining;
        if (entry.finishedAt == null) {
          effectiveRemaining = 0.0; // completed by next purchase
        } else if (entry.quantityRemaining != null) {
          effectiveRemaining = entry.quantityRemaining!;
        } else if (entry.quantityConsumed != null) {
          effectiveRemaining = (qtyPurchased - entry.quantityConsumed!).clamp(0.0, qtyPurchased);
        } else {
          effectiveRemaining = 0.0;
        }

        if (days > 0) {
          final consumed = qtyPurchased - effectiveRemaining;
          if (consumed > 0) {
            historicalTotalConsumed += consumed;
            historicalTotalDays += days;
          }
        }
      }
    }

    final double? historicalAvgDailyUsage =
        historicalTotalDays > 0 ? historicalTotalConsumed / historicalTotalDays : null;

    // Third pass: build purchase list with historical pattern applied
    for (int i = 0; i < maps.length; i++) {
      final entry = PriceHistory.fromMap(maps[i]);

      final purchaseDate = entry.recordedAt;
      DateTime? endDate = entry.finishedAt;
      bool usedFallback = false;
      bool usedHistoricalPattern = false;

      // For entries without explicit end date, infer from the next (newer) purchase
      // i-1 is the newer purchase since list is DESC sorted
      DateTime? inferredEndDate;
      if (endDate == null && i > 0) {
        final newerEntry = PriceHistory.fromMap(maps[i - 1]);
        inferredEndDate = newerEntry.recordedAt;
      }

      // Determine effective end date and completion status
      final effectiveEndDate = endDate ?? inferredEndDate;
      final bool isComplete = effectiveEndDate != null;

      // Use entry's quantityPurchased if specified, otherwise use default
      double? quantityPurchased = entry.quantityPurchased;
      if (quantityPurchased == null && defaultQuantityPurchased != null) {
        quantityPurchased = defaultQuantityPurchased;
        usedFallback = true;
      }

      // Resolve effective remaining: prefer stored remaining, else derive from
      // quantityConsumed. This normalizes both recording modes into one value.
      double? resolvedRemaining;
      if (entry.quantityRemaining != null) {
        resolvedRemaining = entry.quantityRemaining;
      } else if (entry.quantityConsumed != null && quantityPurchased != null) {
        resolvedRemaining = (quantityPurchased - entry.quantityConsumed!)
            .clamp(0.0, quantityPurchased);
      }

      // Calculate consumed and daily usage
      double? consumed;
      double? avgDailyUsage;
      double? estimatedRemaining;
      int daysTracked;

      if (isComplete) {
        // Completed purchase: use effective end date
        daysTracked = _daysBetween(purchaseDate, effectiveEndDate);

        if (quantityPurchased != null) {
          // For completed entries: if the cycle ended because the next purchase
          // was recorded (no explicit finishedAt), any stored remaining was a
          // mid-cycle checkpoint — assume all was consumed.
          // Only honour resolvedRemaining when finishedAt was explicitly set.
          final completedByNextPurchase = endDate == null;
          final effectiveRemaining = (usedFallback || completedByNextPurchase)
              ? 0.0
              : (resolvedRemaining ?? 0.0);
          consumed = quantityPurchased - effectiveRemaining;
          if (daysTracked > 0 && consumed > 0) {
            avgDailyUsage = consumed / daysTracked;
          }
        }
      } else {
        // Ongoing purchase: calculate days from purchase to now
        daysTracked = _daysBetween(purchaseDate, DateTime.now());

        // Try to compute usage from resolved remaining.
        // Only use the remainingUpdatedAt checkpoint when the user directly set
        // quantityRemaining (not when it was derived from quantityConsumed,
        // since consumed entries don't carry a meaningful checkpoint timestamp).
        if (quantityPurchased != null && resolvedRemaining != null) {
          final remainingUpdatedAt =
              entry.quantityRemaining != null ? entry.remainingUpdatedAt : null;

          if (remainingUpdatedAt != null &&
              remainingUpdatedAt.isAfter(purchaseDate)) {
            // User manually updated remaining after the purchase date — use as
            // a checkpoint. Derive daily rate up to that point, then project
            // consumption forward from there to get a current estimate.
            final daysToCheckpoint =
                _daysBetween(purchaseDate, remainingUpdatedAt);
            final consumedToCheckpoint = quantityPurchased - resolvedRemaining;

            if (daysToCheckpoint > 0 && consumedToCheckpoint > 0) {
              // Normal checkpoint: derive rate up to checkpoint, project forward.
              final rateAtCheckpoint = consumedToCheckpoint / daysToCheckpoint;
              final checkpointDay = DateTime(remainingUpdatedAt.year,
                  remainingUpdatedAt.month, remainingUpdatedAt.day);
              final nowDay = DateTime.now();
              final todayDay = DateTime(nowDay.year, nowDay.month, nowDay.day);
              final daysSinceCheckpoint =
                  todayDay.difference(checkpointDay).inDays;
              final projectedRemaining =
                  resolvedRemaining - (rateAtCheckpoint * daysSinceCheckpoint);
              if (projectedRemaining >= 0) {
                estimatedRemaining = projectedRemaining;
                consumed = quantityPurchased - projectedRemaining;
                if (daysTracked > 0 && consumed > 0) {
                  avgDailyUsage = consumed / daysTracked;
                }
              } else {
                // Overdue: cap consumed at purchased, remaining N/A.
                // Daily usage = purchased / total days (reduces as time passes).
                consumed = quantityPurchased;
                estimatedRemaining = null;
                avgDailyUsage =
                    daysTracked > 0 ? quantityPurchased / daysTracked : null;
              }
              usedHistoricalPattern = true; // display estimated remaining
            } else {
              // Same-day edit or zero consumption: no in-cycle rate derivable.
              // Project forward from resolvedRemaining using historical rate so
              // remaining keeps decreasing instead of sticking at the manual value.
              if (historicalAvgDailyUsage != null) {
                usedHistoricalPattern = true;
                final checkpointDay = DateTime(remainingUpdatedAt.year,
                    remainingUpdatedAt.month, remainingUpdatedAt.day);
                final nowDay = DateTime.now();
                final todayDay =
                    DateTime(nowDay.year, nowDay.month, nowDay.day);
                final daysSinceUpdate =
                    todayDay.difference(checkpointDay).inDays;
                final projectedRemaining =
                    resolvedRemaining - (historicalAvgDailyUsage * daysSinceUpdate);
                if (projectedRemaining >= 0) {
                  estimatedRemaining = projectedRemaining;
                  consumed = quantityPurchased - projectedRemaining;
                  avgDailyUsage = daysTracked > 0 ? consumed / daysTracked : null;
                } else {
                  consumed = quantityPurchased;
                  estimatedRemaining = null;
                  avgDailyUsage =
                      daysTracked > 0 ? quantityPurchased / daysTracked : null;
                }
              } else {
                consumed = quantityPurchased - resolvedRemaining;
                if (daysTracked > 0 && consumed > 0) {
                  avgDailyUsage = consumed / daysTracked;
                }
              }
            }
          } else {
            // No remainingUpdatedAt timestamp (old data): can't project forward
            // from the recorded remaining. Let the historical fallback below
            // handle the estimate instead of sticking at the manual value.
            // Only set consumed for display; leave avgDailyUsage null so the
            // historical fallback can take over.
            consumed = quantityPurchased - resolvedRemaining;
          }
        }

        // If daily usage still unknown (no remaining/consumed data),
        // fall back to historical pattern to estimate current consumption
        if (avgDailyUsage == null &&
            quantityPurchased != null &&
            historicalAvgDailyUsage != null &&
            daysTracked > 0) {
          usedHistoricalPattern = true;
          // Estimate remaining from uncapped projection to detect overdue.
          final startingRemaining = resolvedRemaining ?? quantityPurchased;
          final projectedRemaining2 =
              startingRemaining - (historicalAvgDailyUsage * daysTracked);
          if (projectedRemaining2 < 0) {
            // Overdue: cap consumed at purchased, remaining N/A.
            // Daily usage = purchased / total days (reduces as time passes).
            consumed = quantityPurchased;
            estimatedRemaining = null;
            avgDailyUsage =
                daysTracked > 0 ? quantityPurchased / daysTracked : null;
          } else {
            avgDailyUsage = historicalAvgDailyUsage;
            consumed = (historicalAvgDailyUsage * daysTracked)
                .clamp(0.0, quantityPurchased);
            estimatedRemaining = projectedRemaining2;
          }
        }
      }

      purchases.add({
        'id': entry.id,
        'purchaseDate': purchaseDate,
        'endDate': effectiveEndDate,
        'quantityPurchased': quantityPurchased,
        // For ongoing purchases using historical pattern, show estimated current
        // remaining. For completed, use resolved remaining (derived from either
        // quantityRemaining or quantityConsumed).
        'quantityRemaining': usedFallback && isComplete
            ? 0.0
            : (usedHistoricalPattern && !isComplete
                ? estimatedRemaining
                : (resolvedRemaining ?? estimatedRemaining)),
        'consumed': consumed,
        'daysTracked': daysTracked,
        'avgDailyUsage': avgDailyUsage,
        'isComplete': isComplete,
        'price': entry.price,
        'description': entry.description,
        'usedFallback': usedFallback,
        'usedHistoricalPattern': usedHistoricalPattern,
      });
    }

    return purchases;
  }

  /// Returns how far through the expected purchase cycle the item currently is,
  /// as a fraction (e.g. 0.9 = 90%, 1.2 = 120% / overdue). Returns null if
  /// fewer than 2 manual purchase entries exist (cycle length cannot be determined).
  ///
  /// When quantity data is available, the expected cycle length is estimated as
  /// `currentQuantityPurchased / avgDailyUsage` so that purchases of different
  /// sizes are judged against the right expected duration — a 40-unit purchase
  /// should not be flagged overdue using a cycle length derived from a 22-unit
  /// purchase. Falls back to a naive date-gap average when no quantity data exists.
  Future<double?> getPurchaseCycleProgress(int itemId,
      {int? subItemId}) async {
    final db = await database;

    String whereClause;
    List<dynamic> whereArgs;

    if (subItemId != null) {
      whereClause = 'item_id = ? AND sub_item_id = ? AND entry_type = ?';
      whereArgs = [itemId, subItemId, 'manual'];
    } else {
      whereClause = 'item_id = ? AND sub_item_id IS NULL AND entry_type = ?';
      whereArgs = [itemId, 'manual'];
    }

    final maps = await db.query(
      'price_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'recorded_at ASC',
    );

    if (maps.length < 2) return null;

    final entries = maps.map((m) => PriceHistory.fromMap(m)).toList();
    final lastEntry = entries.last;

    // Days elapsed since the most recent purchase
    final lastPurchaseDate = DateTime(
      lastEntry.recordedAt.year,
      lastEntry.recordedAt.month,
      lastEntry.recordedAt.day,
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final daysElapsed = todayDate.difference(lastPurchaseDate).inDays;

    // --- Quantity-aware estimation ---
    // Compute avgDailyUsage from all completed purchases that have quantity data.
    // "Completed" = has a finishedAt, or is superseded by a newer purchase.
    double totalConsumed = 0.0;
    int totalDays = 0;

    for (int i = 0; i < entries.length - 1; i++) {
      final entry = entries[i];
      if (entry.quantityPurchased == null) continue;

      // End date: always use next purchase date (purchase interval), not
      // finishedAt — consumption duration ≠ repurchase interval.
      final endDate = entries[i + 1].recordedAt;
      final days = _daysBetween(entry.recordedAt, endDate);
      if (days <= 0) continue;

      // All entries here are completed by the next purchase (not finishedAt),
      // so any stored remaining is a mid-cycle checkpoint — treat as 0.
      const double effectiveRemaining = 0.0;

      final consumed = entry.quantityPurchased! - effectiveRemaining;
      if (consumed > 0) {
        totalConsumed += consumed;
        totalDays += days;
      }
    }

    // If we have a reliable avgDailyUsage and the current purchase has a known
    // quantity, use quantity-proportional cycle estimation.
    if (totalDays > 0 && lastEntry.quantityPurchased != null) {
      final avgDailyUsage = totalConsumed / totalDays;
      if (avgDailyUsage > 0) {
        final estimatedCycleDays = lastEntry.quantityPurchased! / avgDailyUsage;
        return daysElapsed / estimatedCycleDays;
      }
    }

    // --- Fallback: naive date-gap average (no quantity data available) ---
    int totalCycleDays = 0;
    for (int i = 1; i < entries.length; i++) {
      totalCycleDays +=
          _daysBetween(entries[i - 1].recordedAt, entries[i].recordedAt);
    }
    final avgCycleDays = totalCycleDays / (entries.length - 1);
    return daysElapsed / avgCycleDays;
  }

  // Clear all data (for backup restore)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('price_history');
    await db.delete('sub_items');
    await db.delete('items');
  }
}
