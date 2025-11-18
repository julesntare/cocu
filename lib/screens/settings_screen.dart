import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService _backupService = BackupService();

  bool _isAutoBackupEnabled = false;
  String _autoBackupFrequency = BackupService.frequencyWeekly;
  DateTime? _lastBackupDate;
  String? _autoBackupPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final enabled = await _backupService.isAutoBackupEnabled();
    final frequency = await _backupService.getAutoBackupFrequency();
    final lastBackup = await _backupService.getLastBackupDate();
    final backupPath = await _backupService.getAutoBackupPath();

    setState(() {
      _isAutoBackupEnabled = enabled;
      _autoBackupFrequency = frequency;
      _lastBackupDate = lastBackup;
      _autoBackupPath = backupPath;
      _isLoading = false;
    });
  }

  Future<void> _toggleAutoBackup(bool value) async {
    await _backupService.setAutoBackupEnabled(value);
    setState(() => _isAutoBackupEnabled = value);
  }

  Future<void> _changeFrequency(String? value) async {
    if (value != null) {
      await _backupService.setAutoBackupFrequency(value);
      setState(() => _autoBackupFrequency = value);
    }
  }

  Future<void> _createManualBackup() async {
    if (!mounted) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final filePath = await _backupService.exportBackupWithPicker();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (filePath != null) {
          await _loadSettings(); // Refresh last backup date

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Backup created successfully!\n$filePath'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _restoreFromBackup() async {
    if (!mounted) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Text(
          'This will replace all current data with the backup data. '
          'This action cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await _backupService.restoreFromFile();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup restored successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Go back to home screen and refresh
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectAutoBackupPath() async {
    if (!mounted) return;

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Auto-Backup Location',
      );

      if (selectedDirectory != null) {
        await _backupService.setAutoBackupPath(selectedDirectory);
        setState(() {
          _autoBackupPath = selectedDirectory;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Auto-backup location updated'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select directory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Settings'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Manual Backup Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manual Backup',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create or restore backups manually',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _createManualBackup,
                                icon: const Icon(Icons.backup),
                                label: const Text('Create Backup'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _restoreFromBackup,
                                icon: const Icon(Icons.restore),
                                label: const Text('Restore'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_lastBackupDate != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Last backup: ${DateFormat('MMM dd, yyyy HH:mm').format(_lastBackupDate!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Auto-Backup Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Auto-Backup',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Switch(
                              value: _isAutoBackupEnabled,
                              onChanged: _toggleAutoBackup,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Automatically create backups on a schedule',
                          style: TextStyle(color: Colors.grey),
                        ),
                        if (_isAutoBackupEnabled) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Backup Frequency',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _autoBackupFrequency,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: BackupService.frequencyDaily,
                                child: Text('Daily'),
                              ),
                              DropdownMenuItem(
                                value: BackupService.frequencyWeekly,
                                child: Text('Weekly'),
                              ),
                              DropdownMenuItem(
                                value: BackupService.frequencyMonthly,
                                child: Text('Monthly'),
                              ),
                            ],
                            onChanged: _changeFrequency,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Backup Location',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _selectAutoBackupPath,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_outlined, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _autoBackupPath ?? 'Default (App Storage)',
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.edit, size: 18, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Auto-backups keep the last 5 backups. Tap above to change backup location.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // About Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About Backups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          Icons.save,
                          'Backup Format',
                          'JSON (Human-readable)',
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.folder,
                          'Manual Backup',
                          'Choose location when creating',
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.schedule,
                          'Auto Backup',
                          'Configurable location + cleanup',
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.inventory,
                          'Backup Content',
                          'All items and price history',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
