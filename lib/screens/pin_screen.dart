import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const PinScreen({super.key, required this.onAuthenticated});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String? _storedPin;
  bool _isSettingPin = false;
  bool _isLoading = true;
  String _confirmPin = '';
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _checkForExistingPin();
  }

  Future<void> _checkForExistingPin() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPin = prefs.getString('user_pin');
    setState(() {
      _storedPin = storedPin;
      _isSettingPin = storedPin == null;
      _isLoading = false;
    });
  }

  void _addDigit(String digit) {
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_pin', _pin);
      await prefs.setBool('is_authenticated', true);
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
    if (_pin == _storedPin) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_authenticated', true);
      widget.onAuthenticated();
    } else {
      _showError('Incorrect PIN. Please try again.');
      setState(() {
        _pin = '';
      });
    }
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
    return Column(
      children: [
        for (int row = 0; row < 3; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int col = 1; col <= 3; col++)
                _buildKeypadButton((row * 3 + col).toString()),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 80, height: 80),
            _buildKeypadButton('0'),
            _buildBackspaceButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit) {
    return GestureDetector(
      onTap: () => _addDigit(digit),
      child: Container(
        width: 80,
        height: 80,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[200],
        ),
        child: Center(
          child: Text(
            digit,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
        : 'Enter your PIN to access the app';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              const Icon(
                Icons.security,
                size: 80,
                color: Colors.blue,
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
                  color: Colors.grey[600],
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
