import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/item.dart';
import '../models/price_history.dart';

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
    String path = join(await getDatabasesPath(), 'cocu.db');
    return await openDatabase(
      path,
      version: 5, // Increment version to add finished_date field
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        current_price REAL NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        price REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        finished_at TEXT,
        entry_type TEXT NOT NULL DEFAULT 'manual',
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
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
        print('Error upgrading database to version 3: $e');
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
        print('Error upgrading database to version 4: $e');
      }
    }

    if (oldVersion < 5) {
      // Add finished_at field to price_history table
      try {
        await db.execute('ALTER TABLE price_history ADD COLUMN finished_at TEXT');
      } catch (e) {
        print('Error upgrading database to version 5: $e');
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

  Future<int> deletePriceHistory(int id) async {
    final db = await database;
    return await db.delete(
      'price_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PriceHistory>> getPriceHistory(int itemId) async {
    final db = await database;
    final maps = await db.query(
      'price_history',
      where: 'item_id = ?',
      whereArgs: [itemId],
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

  Future<Map<String, Map<String, dynamic>>> getMonthlySpendingForItem(int itemId) async {
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

    return maps.map((map) => {
      'name': map['item_name'] as String,
      'amount': (map['total_amount'] as num).toDouble(),
    }).toList();
  }
}
