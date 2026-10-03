import 'indicator_item.dart';

class StrategyConfigModel {
  final int? id;
  final String name;
  final String symbol;
  final int timeframe;
  final double riskPercentage;
  final double slTpRatio;
  final int maxActivePositions;
  final String operator;
  final double signalThreshold;
  final Map<String, dynamic> configJson;

  const StrategyConfigModel({
    this.id,
    required this.name,
    this.symbol = 'EURUSD',
    this.timeframe = 5,
    this.riskPercentage = 1.0,
    this.slTpRatio = 2.0,
    this.maxActivePositions = 1,
    this.operator = 'WEIGHTED',
    this.signalThreshold = 0.5,
    this.configJson = const {},
  });

  factory StrategyConfigModel.fromJson(Map<String, dynamic> json) {
    return StrategyConfigModel(
      id: (json['id'] as num?)?.toInt(),
      name: json['name'] ?? 'Strategy',
      symbol: json['symbol'] ?? 'EURUSD',
      timeframe: (json['timeframe'] as num?)?.toInt() ?? 5,
      riskPercentage: (json['risk_percentage'] as num?)?.toDouble() ?? 1.0,
      slTpRatio: (json['sl_tp_ratio'] as num?)?.toDouble() ?? 2.0,
      maxActivePositions: (json['max_active_positions'] as num?)?.toInt() ?? 1,
      operator: json['operator'] ?? 'WEIGHTED',
      signalThreshold: (json['signal_threshold'] as num?)?.toDouble() ?? 0.5,
      configJson: (json['config_json'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'symbol': symbol,
    'timeframe': timeframe,
    'risk_percentage': riskPercentage,
    'sl_tp_ratio': slTpRatio,
    'max_active_positions': maxActivePositions,
    'operator': operator,
    'signal_threshold': signalThreshold,
    'config_json': configJson,
  };

  List<ConfiguredIndicatorItem> get indicators {
    final List<dynamic> raw = configJson['indicators'] ?? [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => ConfiguredIndicatorItem.fromJson(e))
        .toList();
  }
}
