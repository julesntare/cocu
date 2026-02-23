import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const PinScreen({super.key, required this.onAuthenticated});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const _storage = FlutterSecureStorage();
  static const int _maxAttempts = 5;
  static const int _baseLockoutSeconds = 30;

  String _pin = '';
  String? _storedPin;
  bool _isSettingPin = false;
  bool _isLoading = true;
  String _confirmPin = '';
  bool _isConfirming = false;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  @override
  void initState() {
    super.initState();
    _checkForExistingPin();
  }

  Future<void> _checkForExistingPin() async {
    final storedPin = await _storage.read(key: 'user_pin');
    final attemptsStr = await _storage.read(key: 'pin_failed_attempts');
    final lockoutStr = await _storage.read(key: 'pin_lockout_until');

    DateTime? lockoutUntil;
    if (lockoutStr != null) {
      lockoutUntil = DateTime.tryParse(lockoutStr);
    }

    setState(() {
      _storedPin = storedPin;
      _isSettingPin = storedPin == null;
      _failedAttempts = int.tryParse(attemptsStr ?? '0') ?? 0;
      _lockoutUntil = lockoutUntil;
      _isLoading = false;
    });
  }

  bool get _isLockedOut {
    if (_lockoutUntil == null) return false;
    return DateTime.now().isBefore(_lockoutUntil!);
  }

  Duration get _remainingLockout {
    if (!_isLockedOut) return Duration.zero;
    return _lockoutUntil!.difference(DateTime.now());
  }

  void _addDigit(String digit) {
    if (_isLockedOut) {
      _showError('Too many attempts. Try again in ${_remainingLockout.inSeconds}s.');
      return;
    }
    if (_isConfirming) {
      if (_confirmPin.length < 4) {
        setState(() {
          _confirmPin += digit;
        });
        if (_confirmPin.length == 4) {
          _validateConfirmPin();
        }
      }
    } else {
      if (_pin.length < 4) {
        setState(() {
          _pin += digit;
        });
        if (_pin.length == 4) {
          if (_isSettingPin) {
            _startConfirmation();
          } else {
            _validatePin();
          }
        }
      }
    }
  }

  void _removeDigit() {
    if (_isConfirming) {
      if (_confirmPin.isNotEmpty) {
        setState(() {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        });
      }
    } else {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin = _pin.substring(0, _pin.length - 1);
        });
      }
    }
  }

  void _startConfirmation() {
    setState(() {
      _isConfirming = true;
    });
  }

  Future<void> _validateConfirmPin() async {
    if (_pin == _confirmPin) {
      await _storage.write(key: 'user_pin', value: _pin);
      await _storage.write(key: 'is_authenticated', value: 'true');
      await _resetLockout();
      widget.onAuthenticated();
    } else {
      _showError('PINs do not match. Please try again.');
      setState(() {
        _pin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
    }
  }

  Future<void> _validatePin() async {
    if (_isLockedOut) {
      _showError('Too many attempts. Try again in ${_remainingLockout.inSeconds}s.');
      setState(() { _pin = ''; });
      return;
    }

    if (_pin == _storedPin) {
      await _storage.write(key: 'is_authenticated', value: 'true');
      await _resetLockout();
      widget.onAuthenticated();
    } else {
      final newAttempts = _failedAttempts + 1;
      await _storage.write(key: 'pin_failed_attempts', value: '$newAttempts');

      if (newAttempts >= _maxAttempts) {
        // Exponential backoff: 30s * 2^(n-5), capped at 1 hour
        final multiplier = 1 << (newAttempts - _maxAttempts); // 1, 2, 4, 8...
        final lockSeconds = (_baseLockoutSeconds * multiplier).clamp(0, 3600);
        final until = DateTime.now().add(Duration(seconds: lockSeconds));
        await _storage.write(key: 'pin_lockout_until', value: until.toIso8601String());
        setState(() {
          _failedAttempts = newAttempts;
          _lockoutUntil = until;
          _pin = '';
        });
        _showError('Too many attempts. Locked for ${lockSeconds}s.');
      } else {
        final remaining = _maxAttempts - newAttempts;
        setState(() {
          _failedAttempts = newAttempts;
          _pin = '';
        });
        _showError('Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.');
      }
    }
  }

  Future<void> _resetLockout() async {
    await _storage.delete(key: 'pin_failed_attempts');
    await _storage.delete(key: 'pin_lockout_until');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildPinDots() {
    String currentPin = _isConfirming ? _confirmPin : _pin;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < currentPin.length ? Colors.blue : Colors.grey[300],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final locked = _isLockedOut;
    return Column(
      children: [
        for (int row = 0; row < 3; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int col = 1; col <= 3; col++)
                _buildKeypadButton((row * 3 + col).toString(), disabled: locked),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 80, height: 80),
            _buildKeypadButton('0', disabled: locked),
            _buildBackspaceButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit, {bool disabled = false}) {
    return GestureDetector(
      onTap: disabled ? null : () => _addDigit(digit),
      child: Container(
        width: 80,
        height: 80,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: disabled ? Colors.grey[100] : Colors.grey[200],
        ),
        child: Center(
          child: Text(
            digit,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: disabled ? Colors.grey[400] : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return GestureDetector(
      onTap: _removeDigit,
      child: Container(
        width: 80,
        height: 80,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[200],
        ),
        child: const Center(
          child: Icon(Icons.backspace, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    String title = _isSettingPin
        ? (_isConfirming ? 'Confirm PIN' : 'Set PIN')
        : 'Enter PIN';

    String subtitle = _isSettingPin
        ? (_isConfirming
            ? 'Enter your PIN again to confirm'
            : 'Create a 4-digit PIN to secure your app')
        : _isLockedOut
            ? 'Too many failed attempts.\nTry again in ${_remainingLockout.inSeconds}s.'
            : 'Enter your PIN to access the app';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Icon(
                _isLockedOut ? Icons.lock : Icons.security,
                size: 80,
                color: _isLockedOut ? Colors.red : Colors.blue,
              ),
              const SizedBox(height: 40),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _isLockedOut ? Colors.red : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 60),
              _buildPinDots(),
              const SizedBox(height: 60),
              _buildKeypad(),
            ],
          ),
        ),
      ),
    );
  }
}
