class Item {
  final int? id;
  final String name;
  final double currentPrice;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool trackUsage;
  final String? usageUnit;

  Item({
    this.id,
    required this.name,
    required this.currentPrice,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.trackUsage = false,
    this.usageUnit,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'current_price': currentPrice,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'track_usage': trackUsage ? 1 : 0,
      'usage_unit': usageUnit,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'],
      name: map['name'],
      currentPrice: map['current_price'],
      description: map['description'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      trackUsage: map['track_usage'] == 1,
      usageUnit: map['usage_unit'],
    );
  }

  Item copyWith({
    int? id,
    String? name,
    double? currentPrice,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? trackUsage,
    String? usageUnit,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      currentPrice: currentPrice ?? this.currentPrice,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trackUsage: trackUsage ?? this.trackUsage,
      usageUnit: usageUnit ?? this.usageUnit,
    );
  }
}
