import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import '../models/item.dart';
import '../models/sub_item.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final DatabaseService _dbService = DatabaseService();

  // Settings keys
  static const String _autoBackupEnabledKey = 'auto_backup_enabled';
  static const String _autoBackupFrequencyKey = 'auto_backup_frequency';
  static const String _lastBackupDateKey = 'last_backup_date';
  static const String _autoBackupPathKey = 'auto_backup_path';

  // Auto-backup frequency options
  static const String frequencyDaily = 'daily';
  static const String frequencyWeekly = 'weekly';
  static const String frequencyMonthly = 'monthly';

  static const _storage = FlutterSecureStorage();

  /// Derive a 32-byte AES key from the stored DB encryption key.
  Future<enc.Key> _getBackupKey() async {
    final hexKey = await _storage.read(key: 'db_encryption_key');
    if (hexKey == null) throw Exception('Encryption key not found');
    // Convert hex string to bytes (each pair of hex chars = 1 byte)
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = int.parse(hexKey.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return enc.Key(bytes);
  }

  /// Encrypt [plaintext] with AES-256-CBC and return "base64(iv):base64(ciphertext)".
  Future<String> _encrypt(String plaintext) async {
    final key = await _getBackupKey();
    final ivBytes = Uint8List(16);
    final rng = Random.secure();
    for (int i = 0; i < 16; i++) ivBytes[i] = rng.nextInt(256);
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${base64.encode(ivBytes)}:${encrypted.base64}';
  }

  /// Decrypt a string produced by [_encrypt].
  Future<String> _decrypt(String payload) async {
    final parts = payload.split(':');
    if (parts.length != 2) throw const FormatException('Invalid backup format');
    final key = await _getBackupKey();
    final iv = enc.IV(base64.decode(parts[0]));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  /// Export all data to JSON format
  Future<Map<String, dynamic>> exportToJson() async {
    final items = await _dbService.getAllItems();
    final priceHistory = await _dbService.getAllPriceHistory();

    // Get all sub-items for all items
    List<SubItem> allSubItems = [];
    for (var item in items) {
      final subItems = await _dbService.getSubItemsByItemId(item.id!);
      allSubItems.addAll(subItems);
    }

    return {
      'version': '1.1.0', // Bumped version to indicate sub-items support
      'export_date': DateTime.now().toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'sub_items': allSubItems.map((subItem) => subItem.toMap()).toList(),
      'price_history': priceHistory.map((ph) => ph.toMap()).toList(),
    };
  }

  /// Validate that [map] contains [required] string keys with non-null values.
  void _requireFields(Map<dynamic, dynamic> map, List<String> required, String context) {
    for (final key in required) {
      if (!map.containsKey(key) || map[key] == null) {
        throw FormatException('Invalid backup: missing "$key" in $context');
      }
    }
  }

  /// Import data from JSON format
  Future<void> importFromJson(Map<String, dynamic> data) async {
    if (data['version'] == null) {
      throw const FormatException('Invalid backup file: missing version');
    }
    if (data['version'] is! String) {
      throw const FormatException('Invalid backup file: version must be a string');
    }

    // Clear existing data
    await _dbService.clearAllData();

    // Import items first (parent entities)
    if (data['items'] != null) {
      if (data['items'] is! List) throw const FormatException('Invalid backup: items must be a list');
      for (final raw in data['items'] as List) {
        if (raw is! Map) continue;
        try {
          _requireFields(raw, ['name', 'current_price', 'created_at', 'updated_at'], 'items');
          final item = Item.fromMap(Map<String, dynamic>.from(raw));
          final db = await _dbService.database;
          await db.insert('items', item.toMap());
        } catch (_) {
          // Skip malformed entries rather than aborting the whole restore
        }
      }
    }

    // Import sub-items second (child entities of items)
    if (data['sub_items'] != null) {
      if (data['sub_items'] is! List) throw const FormatException('Invalid backup: sub_items must be a list');
      for (final raw in data['sub_items'] as List) {
        if (raw is! Map) continue;
        try {
          _requireFields(raw, ['item_id', 'name', 'current_price', 'created_at', 'updated_at'], 'sub_items');
          final subItem = SubItem.fromMap(Map<String, dynamic>.from(raw));
          final db = await _dbService.database;
          await db.insert('sub_items', subItem.toMap());
        } catch (_) {
          // Skip malformed entries
        }
      }
    }

    // Import price history last (references both items and sub-items)
    if (data['price_history'] != null) {
      if (data['price_history'] is! List) throw const FormatException('Invalid backup: price_history must be a list');
      for (final raw in data['price_history'] as List) {
        if (raw is! Map) continue;
        try {
          _requireFields(raw, ['item_id', 'price', 'recorded_at', 'entry_type'], 'price_history');
          final db = await _dbService.database;
          await db.insert('price_history', Map<String, dynamic>.from(raw));
        } catch (_) {
          // Skip malformed entries
        }
      }
    }
  }

  /// Create a backup file and save it to device storage
  Future<String?> createBackup() async {
    try {
      // Export data to JSON
      final data = await exportToJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      // Generate filename with timestamp
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'cocu_backup_$timestamp.json';

      // Get custom path or default path
      final customPath = await getAutoBackupPath();
      Directory? directory;

      if (customPath != null && customPath.isNotEmpty) {
        directory = Directory(customPath);
      } else {
        // Use default location
        if (Platform.isAndroid) {
          directory = await getExternalStorageDirectory();
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory == null) {
          throw Exception('Could not access storage directory');
        }

        // Create backups folder if it doesn't exist
        directory = Directory('${directory.path}/CoCu_Backups');
      }

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Encrypt and write file
      final encryptedContent = await _encrypt(jsonString);
      final file = File('${directory.path}/$filename');
      await file.writeAsString(encryptedContent);

      // Update last backup date
      await _updateLastBackupDate();

      // Cleanup old backups
      await cleanupOldBackups();

      return file.path;
    } catch (e) {
      rethrow;
    }
  }

  /// Export backup with user-selected directory
  Future<String?> exportBackupWithPicker() async {
    try {
      // Export data to JSON
      final data = await exportToJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      // Generate filename with timestamp
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'cocu_backup_$timestamp.json';

      // Let user choose directory
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Backup Location',
      );

      if (selectedDirectory != null) {
        final encryptedContent = await _encrypt(jsonString);
        final file = File('$selectedDirectory/$filename');
        await file.writeAsString(encryptedContent);

        // Update last backup date
        await _updateLastBackupDate();

        return file.path;
      }

      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Restore from backup file
  Future<void> restoreFromFile() async {
    try {
      // Let user pick backup file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final rawContent = await file.readAsString();

        // Try decrypting first (new format); fall back to plain JSON (old format)
        String jsonString;
        try {
          jsonString = await _decrypt(rawContent);
        } catch (_) {
          jsonString = rawContent;
        }

        final data = json.decode(jsonString) as Map<String, dynamic>;
        await importFromJson(data);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get auto-backup settings
  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? false;
  }

  /// Set auto-backup enabled/disabled
  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
  }

  /// Get auto-backup frequency
  Future<String> getAutoBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_autoBackupFrequencyKey) ?? frequencyWeekly;
  }

  /// Set auto-backup frequency
  Future<void> setAutoBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_autoBackupFrequencyKey, frequency);
  }

  /// Get auto-backup path
  Future<String?> getAutoBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_autoBackupPathKey);
  }

  /// Set auto-backup path
  Future<void> setAutoBackupPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_autoBackupPathKey);
    } else {
      await prefs.setString(_autoBackupPathKey, path);
    }
  }

  /// Get last backup date
  Future<DateTime?> getLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(_lastBackupDateKey);
    if (dateString != null) {
      return DateTime.parse(dateString);
    }
    return null;
  }

  /// Update last backup date
  Future<void> _updateLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupDateKey, DateTime.now().toIso8601String());
  }

  /// Check if auto-backup should run
  Future<bool> shouldRunAutoBackup() async {
    final enabled = await isAutoBackupEnabled();
    if (!enabled) return false;

    final lastBackup = await getLastBackupDate();
    if (lastBackup == null) return true;

    final frequency = await getAutoBackupFrequency();
    final now = DateTime.now();

    switch (frequency) {
      case frequencyDaily:
        return now.difference(lastBackup).inDays >= 1;
      case frequencyWeekly:
        return now.difference(lastBackup).inDays >= 7;
      case frequencyMonthly:
        return now.difference(lastBackup).inDays >= 30;
      default:
        return false;
    }
  }

  /// Run auto-backup if needed
  Future<void> runAutoBackupIfNeeded() async {
    try {
      final shouldRun = await shouldRunAutoBackup();
      if (shouldRun) {
        await createBackup();
      }
    } catch (e) {
      // Silent fail for auto-backup
      if (kDebugMode) debugPrint('Auto-backup failed: $e');
    }
  }

  /// Get list of backup files
  Future<List<File>> getBackupFiles() async {
    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) return [];

      final backupsDir = Directory('${directory.path}/CoCu_Backups');
      if (!await backupsDir.exists()) {
        return [];
      }

      final files = await backupsDir.list().toList();
      return files
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Delete old backup files (keep last N backups)
  Future<void> cleanupOldBackups({int keepLast = 5}) async {
    try {
      final backupFiles = await getBackupFiles();

      // Sort by modified date (newest first)
      backupFiles
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // Delete older backups
      if (backupFiles.length > keepLast) {
        for (int i = keepLast; i < backupFiles.length; i++) {
          await backupFiles[i].delete();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Cleanup failed: $e');
    }
  }
}
