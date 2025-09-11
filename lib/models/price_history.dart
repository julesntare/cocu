class PriceHistory {
  final int? id;
  final int itemId;
  final double price;
  final DateTime recordedAt;
  final DateTime? createdAt;
  final String entryType; // 'manual' or 'automatic'

  PriceHistory({
    this.id,
    required this.itemId,
    required this.price,
    required this.recordedAt,
    this.createdAt,
    this.entryType = 'manual',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'price': price,
      'recorded_at': recordedAt.toIso8601String(),
      'created_at':
          createdAt?.toIso8601String() ?? recordedAt.toIso8601String(),
      'entry_type': entryType,
    };
  }

  factory PriceHistory.fromMap(Map<String, dynamic> map) {
    return PriceHistory(
      id: map['id'],
      itemId: map['item_id'],
      price: map['price'],
      recordedAt: DateTime.parse(map['recorded_at']),
      createdAt:
          map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      entryType: map['entry_type'] ?? 'manual',
    );
  }
}
