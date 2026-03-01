import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService().initDatabase();

  // Run auto-backup if needed
  BackupService().runAutoBackupIfNeeded();

  runApp(const CocuApp());
}

class CocuApp extends StatelessWidget {
  const CocuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoCu',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
