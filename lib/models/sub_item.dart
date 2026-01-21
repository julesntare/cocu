class SubItem {
  final int? id;
  final int itemId;
  final String name;
  final double currentPrice;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool trackUsage;
  final String? usageUnit;

  SubItem({
    this.id,
    required this.itemId,
    required this.name,
    required this.currentPrice,
    required this.createdAt,
    required this.updatedAt,
    this.trackUsage = false,
    this.usageUnit,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'name': name,
      'current_price': currentPrice,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'track_usage': trackUsage ? 1 : 0,
      'usage_unit': usageUnit,
    };
  }

  factory SubItem.fromMap(Map<String, dynamic> map) {
    return SubItem(
      id: map['id'] as int?,
      itemId: map['item_id'] as int,
      name: map['name'] as String,
      currentPrice: map['current_price'] as double,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      trackUsage: map['track_usage'] == 1,
      usageUnit: map['usage_unit'] as String?,
    );
  }

  SubItem copyWith({
    int? id,
    int? itemId,
    String? name,
    double? currentPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? trackUsage,
    String? usageUnit,
  }) {
    return SubItem(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      currentPrice: currentPrice ?? this.currentPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trackUsage: trackUsage ?? this.trackUsage,
      usageUnit: usageUnit ?? this.usageUnit,
    );
  }
}
