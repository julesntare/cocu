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
      version: 2, // Increment version to trigger migration
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
        note TEXT,
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
      note: 'Initial price',
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
      // Insert new price history if price changed
      await insertPriceHistory(PriceHistory(
        itemId: item.id!,
        price: item.currentPrice,
        recordedAt: item.updatedAt,
        note: 'Price updated',
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
}
