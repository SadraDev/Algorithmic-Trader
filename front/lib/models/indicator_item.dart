class ConfiguredIndicatorItem {
  String id;
  String name;
  String timeframe;
  Map<String, dynamic> params;
  double weight;

  ConfiguredIndicatorItem({
    required this.id,
    required this.name,
    this.timeframe = 'M5',
    required this.params,
    this.weight = 0.5,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timeframe': timeframe,
    'params': params,
    'weight': weight,
  };

  factory ConfiguredIndicatorItem.fromJson(Map<String, dynamic> json) => ConfiguredIndicatorItem(
    id: json['id'] ?? 'rsi',
    name: json['name'] ?? 'Indicator',
    timeframe: json['timeframe'] ?? 'M5',
    params: (json['params'] as Map<String, dynamic>?) ?? {},
    weight: (json['weight'] as num?)?.toDouble() ?? 0.5,
  );
}
