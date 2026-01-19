class PriceHistory {
  final int? id;
  final int itemId;
  final int? subItemId; // Optional sub-item ID
  final double price;
  final DateTime recordedAt;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final String entryType; // 'manual' or 'automatic'
  final String? description; // Optional description for the price entry
  final double? quantityPurchased; // Units bought (e.g., 100 kWh)
  final double? quantityRemaining; // Units left when recording
  final double? quantityConsumed; // Units used (alternative entry method)

  PriceHistory({
    this.id,
    required this.itemId,
    this.subItemId,
    required this.price,
    required this.recordedAt,
    this.createdAt,
    this.finishedAt,
    this.entryType = 'manual',
    this.description,
    this.quantityPurchased,
    this.quantityRemaining,
    this.quantityConsumed,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'sub_item_id': subItemId,
      'price': price,
      'recorded_at': recordedAt.toIso8601String(),
      'created_at':
          createdAt?.toIso8601String() ?? recordedAt.toIso8601String(),
      'finished_at': finishedAt?.toIso8601String(),
      'entry_type': entryType,
      'description': description,
      'quantity_purchased': quantityPurchased,
      'quantity_remaining': quantityRemaining,
      'quantity_consumed': quantityConsumed,
    };
  }

  factory PriceHistory.fromMap(Map<String, dynamic> map) {
    return PriceHistory(
      id: map['id'],
      itemId: map['item_id'],
      subItemId: map['sub_item_id'],
      price: map['price'],
      recordedAt: DateTime.parse(map['recorded_at']),
      createdAt:
          map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      finishedAt:
          map['finished_at'] != null ? DateTime.parse(map['finished_at']) : null,
      entryType: map['entry_type'] ?? 'manual',
      description: map['description'],
      quantityPurchased: map['quantity_purchased'] != null
          ? (map['quantity_purchased'] as num).toDouble()
          : null,
      quantityRemaining: map['quantity_remaining'] != null
          ? (map['quantity_remaining'] as num).toDouble()
          : null,
      quantityConsumed: map['quantity_consumed'] != null
          ? (map['quantity_consumed'] as num).toDouble()
          : null,
    );
  }

  PriceHistory copyWith({
    int? id,
    int? itemId,
    int? subItemId,
    double? price,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? finishedAt,
    String? entryType,
    String? description,
    double? quantityPurchased,
    double? quantityRemaining,
    double? quantityConsumed,
    bool clearQuantityRemaining = false,
    bool clearQuantityConsumed = false,
  }) {
    return PriceHistory(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      subItemId: subItemId ?? this.subItemId,
      price: price ?? this.price,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      entryType: entryType ?? this.entryType,
      description: description ?? this.description,
      quantityPurchased: quantityPurchased ?? this.quantityPurchased,
      quantityRemaining: clearQuantityRemaining ? null : (quantityRemaining ?? this.quantityRemaining),
      quantityConsumed: clearQuantityConsumed ? null : (quantityConsumed ?? this.quantityConsumed),
    );
  }
}
