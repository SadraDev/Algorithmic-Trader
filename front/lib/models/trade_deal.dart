class TradeDealModel {
  final int ticket;
  final int order;
  final String symbol;
  final String type;
  final double volume;
  final double price;
  final double profit;
  final String? comment;
  final String time;

  const TradeDealModel({
    required this.ticket,
    this.order = 0,
    required this.symbol,
    required this.type,
    required this.volume,
    required this.price,
    required this.profit,
    this.comment,
    required this.time,
  });

  factory TradeDealModel.fromJson(Map<String, dynamic> json) {
    return TradeDealModel(
      ticket: (json['ticket'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
      symbol: json['symbol'] ?? 'EURUSD',
      type: json['type'] ?? 'BUY',
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      profit: (json['profit'] as num?)?.toDouble() ?? 0.0,
      comment: json['comment'] as String?,
      time: json['time'] ?? '',
    );
  }
}
