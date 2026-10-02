import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static final List<String> _candidateUrls = kIsWeb
      ? ['http://localhost:8000/api/trading', 'http://127.0.0.1:8000/api/trading']
      : (defaultTargetPlatform == TargetPlatform.android
          ? ['http://10.0.2.2:8000/api/trading', 'http://localhost:8000/api/trading', 'http://127.0.0.1:8000/api/trading']
          : ['http://localhost:8000/api/trading', 'http://127.0.0.1:8000/api/trading']);

  static String baseUrl = _candidateUrls.first;

  /// Fetches current MT5 connection state and account info with automatic host resolution.
  static Future<Map<String, dynamic>> getAccountStatus() async {
    for (final url in [baseUrl, ..._candidateUrls.where((u) => u != baseUrl)]) {
      try {
        final response = await http
            .get(Uri.parse('$url/status/'))
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          baseUrl = url;
          return json.decode(response.body) as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('Failed to connect to $url: $e');
      }
    }

    return {'connected': false, 'account': null};
  }

  /// Triggers a trading execution cycle on demand.
  static Future<Map<String, dynamic>> executeTradingCycle({
    String symbol = 'EURUSD',
    int timeframe = 5,
    double riskPercentage = 1.0,
    double slTpRatio = 2.0,
    String operator = 'OR',
    double signalThreshold = 0.5,
    int maxActivePositions = 1,
    List<Map<String, dynamic>>? indicators,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/execute/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'symbol': symbol,
              'timeframe': timeframe,
              'risk_percentage': riskPercentage,
              'sl_tp_ratio': slTpRatio,
              'operator': operator,
              'signal_threshold': signalThreshold,
              'max_active_positions': maxActivePositions,
              if (indicators != null && indicators.isNotEmpty) 'indicators': indicators,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error executing trading cycle: $e');
      return {'error': e.toString(), 'order_executed': false};
    }
    return {'error': 'Failed response', 'order_executed': false};
  }

  /// Starts a continuous background algorithm instance.
  static Future<Map<String, dynamic>> startInstance({
    required String name,
    required String symbol,
    required int timeframe,
    required double riskPercentage,
    required double slTpRatio,
    required String operator,
    required double signalThreshold,
    int maxActivePositions = 1,
    List<Map<String, dynamic>>? indicators,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/instances/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'symbol': symbol,
              'timeframe': timeframe,
              'risk_percentage': riskPercentage,
              'sl_tp_ratio': slTpRatio,
              'operator': operator,
              'signal_threshold': signalThreshold,
              'max_active_positions': maxActivePositions,
              if (indicators != null && indicators.isNotEmpty) 'indicators': indicators,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error starting instance: $e');
    }
    return {'error': 'Failed to start instance'};
  }

  /// Fetches all active running algorithm instances from backend.
  static Future<List<Map<String, dynamic>>> getActiveInstances() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/instances/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> instances = data['instances'] ?? [];
        return instances.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching active instances: $e');
    }
    return [];
  }

  /// Pauses or resumes an active algorithm instance.
  static Future<bool> pauseInstance(String instanceId) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/instances/$instanceId/pause/'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error pausing instance $instanceId: $e');
      return false;
    }
  }

  /// Stops and terminates an active algorithm instance.
  static Future<bool> stopInstance(String instanceId) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/instances/$instanceId/stop/'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error stopping instance $instanceId: $e');
      return false;
    }
  }

  /// Fetches real MT5 history deals directly from the connected terminal.
  static Future<List<Map<String, dynamic>>> getMt5HistoryDeals() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/history/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> deals = data['history_deals'] ?? [];
        return deals.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching MT5 history deals: $e');
    }
    return [];
  }

  /// Saves or updates a strategy configuration in Django database with JSON indicator pipeline.
  static Future<bool> createStrategyConfig({
    required String name,
    String symbol = 'EURUSD',
    int timeframe = 5,
    double riskPercentage = 1.0,
    double slTpRatio = 2.0,
    String operator = 'WEIGHTED',
    double signalThreshold = 0.5,
    Map<String, dynamic>? configJson,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/configs/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'symbol': symbol,
              'timeframe': timeframe,
              'risk_percentage': riskPercentage,
              'sl_tp_ratio': slTpRatio,
              'operator': operator,
              'signal_threshold': signalThreshold,
              'config_json': configJson ?? {},
            }),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating/updating strategy config: $e');
      return false;
    }
  }

  /// Deletes a strategy configuration from Django database by ID or Name.
  static Future<bool> deleteStrategyConfig({int? id, String? name}) async {
    try {
      final payload = <String, dynamic>{};
      if (id != null) payload['id'] = id;
      if (name != null) payload['name'] = name;

      final response = await http
          .delete(
            Uri.parse('$baseUrl/configs/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting strategy config: $e');
      return false;
    }
  }

  /// Fetches strategy configurations from backend.
  static Future<List<Map<String, dynamic>>> getStrategyConfigs() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/configs/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> configs = data['configs'] ?? [];
        return configs.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching strategy configs: $e');
    }
    return [];
  }

  /// Fetches recent trade execution logs from backend.
  static Future<List<Map<String, dynamic>>> getTradeLogs() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/logs/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> logs = data['logs'] ?? [];
        return logs.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching trade logs: $e');
    }
    return [];
  }

  /// Fetches list of available normalized indicators from backend.
  static Future<List<Map<String, dynamic>>> getIndicators() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/indicators/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> indicators = data['indicators'] ?? [];
        return indicators.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching indicators: $e');
    }
    return [];
  }

  /// Evaluates a normalized indicator or dynamic WeightedCombiner over live MT5 rate data.
  static Future<Map<String, dynamic>> evaluateIndicator({
    required String indicatorId,
    String symbol = 'EURUSD',
    int timeframe = 5,
    Map<String, dynamic>? params,
    List<Map<String, dynamic>>? indicators,
  }) async {
    try {
      final payload = {
        'indicator_id': indicatorId,
        'symbol': symbol,
        'timeframe': timeframe,
        if (indicators != null && indicators.isNotEmpty) 'indicators': indicators, ...?params,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/indicators/evaluate/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error evaluating indicator $indicatorId: $e');
    }
    return {'error': 'Evaluation failed', 'latest_value': 0.0, 'series': <double>[]};
  }
}
