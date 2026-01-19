import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/item.dart';
import '../services/database_service.dart';

class AddItemScreen extends StatefulWidget {
  final Item? item; // For editing existing items

  const AddItemScreen({super.key, this.item});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _customUnitController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();

  bool _isLoading = false;
  DateTime? _selectedDate;
  bool _trackUsage = false;
  String? _selectedUnit;
  bool _useCustomUnit = false;

  static const List<String> _predefinedUnits = [
    'kWh',
    'kg',
    'g',
    'L',
    'ml',
    'pieces',
    'units',
  ];

  @override
  void initState() {
    super.initState();

    if (widget.item != null) {
      _nameController.text = widget.item!.name;
      _priceController.text =
          NumberFormat('#,###').format(widget.item!.currentPrice.round());
      _descriptionController.text = widget.item!.description ?? '';
      _selectedDate = widget.item!.createdAt;
      _trackUsage = widget.item!.trackUsage;
      if (widget.item!.usageUnit != null) {
        if (_predefinedUnits.contains(widget.item!.usageUnit)) {
          _selectedUnit = widget.item!.usageUnit;
          _useCustomUnit = false;
        } else {
          _useCustomUnit = true;
          _customUnitController.text = widget.item!.usageUnit!;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _customUnitController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      final createdDate = widget.item?.createdAt ?? _selectedDate ?? now;

      // Parse price, default to 0.0 if not provided
      final priceText = _priceController.text.replaceAll(',', '').trim();
      final price = priceText.isEmpty ? 0.0 : double.parse(priceText);

      // Determine usage unit
      String? usageUnit;
      if (_trackUsage) {
        if (_useCustomUnit && _customUnitController.text.trim().isNotEmpty) {
          usageUnit = _customUnitController.text.trim();
        } else if (_selectedUnit != null) {
          usageUnit = _selectedUnit;
        }
      }

      final item = Item(
        id: widget.item?.id,
        name: _nameController.text.trim(),
        currentPrice: price,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        createdAt: createdDate,
        updatedAt: now,
        trackUsage: _trackUsage,
        usageUnit: usageUnit,
      );

      if (widget.item == null) {
        await _databaseService.insertItem(item);
      } else {
        await _databaseService.updateItem(item);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.item == null
                ? 'Item added successfully'
                : 'Item updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving item: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8C00), Color(0xFFFF6B35)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            title: Text(widget.item == null ? 'Add Item' : 'Edit Item'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: _saveItem,
                ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Item Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFF8C00), width: 2),
                ),
                prefixIcon: const Icon(Icons.shopping_cart, color: Color(0xFFFF8C00)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an item name';
                }
                return null;
              },
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'Price (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFF8C00), width: 2),
                ),
                prefixIcon: const Icon(Icons.payments, color: Color(0xFFFFC107)),
                suffixText: 'Rwf',
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                TextInputFormatter.withFunction((oldValue, newValue) {
                  if (newValue.text.isEmpty) return newValue;
                  final int value = int.parse(newValue.text);
                  final formatted = NumberFormat('#,###').format(value);
                  return TextEditingValue(
                    text: formatted,
                    selection:
                        TextSelection.collapsed(offset: formatted.length),
                  );
                }),
              ],
              validator: (value) {
                // Price is now optional, only validate if provided
                if (value != null && value.trim().isNotEmpty) {
                  final cleanValue = value.replaceAll(',', '');
                  final price = double.tryParse(cleanValue);
                  if (price == null || price <= 0) {
                    return 'Please enter a valid price';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFF8C00), width: 2),
                ),
                prefixIcon: const Icon(Icons.description, color: Color(0xFFFFB700)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),
            // Usage tracking toggle
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade50,
              ),
              child: SwitchListTile(
                title: const Text('Track daily usage'),
                subtitle: Text(
                  'Monitor consumption (e.g., electricity, groceries)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: _trackUsage,
                onChanged: (value) {
                  setState(() {
                    _trackUsage = value;
                    if (!value) {
                      _selectedUnit = null;
                      _useCustomUnit = false;
                      _customUnitController.clear();
                    }
                  });
                },
                activeTrackColor: const Color(0xFFFFE0B2),
                activeThumbColor: const Color(0xFFFF8C00),
                secondary: Icon(
                  Icons.trending_up,
                  color: _trackUsage ? const Color(0xFFFF8C00) : Colors.grey,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            // Usage unit selector (shown when tracking is enabled)
            if (_trackUsage) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usage Unit',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._predefinedUnits.map((unit) => ChoiceChip(
                              label: Text(unit),
                              selected: !_useCustomUnit && _selectedUnit == unit,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedUnit = unit;
                                    _useCustomUnit = false;
                                    _customUnitController.clear();
                                  }
                                });
                              },
                              selectedColor: const Color(0xFFFFE0B2),
                              labelStyle: TextStyle(
                                color: !_useCustomUnit && _selectedUnit == unit
                                    ? const Color(0xFFFF8C00)
                                    : Colors.grey.shade700,
                                fontWeight: !_useCustomUnit && _selectedUnit == unit
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            )),
                        ChoiceChip(
                          label: const Text('Custom'),
                          selected: _useCustomUnit,
                          onSelected: (selected) {
                            setState(() {
                              _useCustomUnit = selected;
                              if (selected) {
                                _selectedUnit = null;
                              }
                            });
                          },
                          selectedColor: const Color(0xFFFFE0B2),
                          labelStyle: TextStyle(
                            color: _useCustomUnit
                                ? const Color(0xFFFF8C00)
                                : Colors.grey.shade700,
                            fontWeight:
                                _useCustomUnit ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    if (_useCustomUnit) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _customUnitController,
                        decoration: InputDecoration(
                          labelText: 'Custom unit',
                          hintText: 'e.g., sachets, bottles',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFFF8C00), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (value) {
                          if (_trackUsage &&
                              _useCustomUnit &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Please enter a custom unit';
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Purchase Date (Optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFFFF9500)),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                child: Text(
                  _selectedDate != null
                      ? DateFormat('MMM dd, yyyy').format(_selectedDate!)
                      : 'Select date (defaults to today)',
                  style: TextStyle(
                    color:
                        _selectedDate != null ? Colors.black : Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB700), Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB700).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.item == null ? 'Add Item' : 'Update Item',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
