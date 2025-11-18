import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import '../models/item.dart';
import '../models/price_history.dart';

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

  /// Export all data to JSON format
  Future<Map<String, dynamic>> exportToJson() async {
    final items = await _dbService.getAllItems();
    final priceHistory = await _dbService.getAllPriceHistory();

    return {
      'version': '1.0.0',
      'export_date': DateTime.now().toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'price_history': priceHistory.map((ph) => ph.toMap()).toList(),
    };
  }

  /// Import data from JSON format
  Future<void> importFromJson(Map<String, dynamic> data) async {
    if (data['version'] == null) {
      throw Exception('Invalid backup file: missing version');
    }

    // Clear existing data
    await _dbService.clearAllData();

    // Import items
    if (data['items'] != null) {
      for (var itemMap in data['items']) {
        await _dbService.insertItem(Item.fromMap(itemMap));
      }
    }

    // Import price history
    if (data['price_history'] != null) {
      for (var phMap in data['price_history']) {
        await _dbService.insertPriceHistory(PriceHistory.fromMap(phMap));
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

      // Write file
      final file = File('${directory.path}/$filename');
      await file.writeAsString(jsonString);

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
        final file = File('$selectedDirectory/$filename');
        await file.writeAsString(jsonString);

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
        final jsonString = await file.readAsString();
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
      print('Auto-backup failed: $e');
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
      print('Cleanup failed: $e');
    }
  }
}
