class PriceHistory {
  final int? id;
  final int itemId;
  final double price;
  final DateTime recordedAt;
  final String? note;

  PriceHistory({
    this.id,
    required this.itemId,
    required this.price,
    required this.recordedAt,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'price': price,
      'recorded_at': recordedAt.toIso8601String(),
      'note': note,
    };
  }

  factory PriceHistory.fromMap(Map<String, dynamic> map) {
    return PriceHistory(
      id: map['id'],
      itemId: map['item_id'],
      price: map['price'],
      recordedAt: DateTime.parse(map['recorded_at']),
      note: map['note'],
    );
  }
}
