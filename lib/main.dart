import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'screens/pin_screen.dart';
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
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  static const _storage = FlutterSecureStorage();
  static const Duration _sessionTimeout = Duration(minutes: 5);

  bool _isAuthenticated = false;
  bool _isLoading = true;
  DateTime? _lastActiveTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuthStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionTimeout();
    } else if (state == AppLifecycleState.paused) {
      _lastActiveTime = DateTime.now();
    }
  }

  void _checkSessionTimeout() {
    if (!_isAuthenticated) return;
    if (_lastActiveTime == null) return;

    final elapsed = DateTime.now().difference(_lastActiveTime!);
    if (elapsed >= _sessionTimeout) {
      _storage.write(key: 'is_authenticated', value: 'false');
      setState(() {
        _isAuthenticated = false;
      });
    }
  }

  Future<void> _checkAuthStatus() async {
    final hasPin = await _storage.read(key: 'user_pin') != null;
    final isAuthenticated = await _storage.read(key: 'is_authenticated') == 'true';

    setState(() {
      _isAuthenticated = hasPin && isAuthenticated;
      _isLoading = false;
    });
  }

  void _onAuthenticated() {
    setState(() {
      _isAuthenticated = true;
      _lastActiveTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _isAuthenticated
        ? const HomeScreen()
        : PinScreen(onAuthenticated: _onAuthenticated);
  }
}
