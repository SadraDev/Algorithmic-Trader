import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_endpoints.dart';

class ApiService {
  static String baseUrl = ApiEndpoints.baseUrl;
  static const String _prefKeyBaseUrl = 'saved_api_base_url';

  /// Loads locally persisted API base URL from SharedPreferences.
  static Future<void> loadSavedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_prefKeyBaseUrl);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        baseUrl = savedUrl.trim();
      }
    } catch (e) {
      debugPrint('Error loading saved base URL: $e');
    }
  }

  /// Persists custom API base URL locally on the phone.
  static Future<bool> saveCustomBaseUrl(String newUrl) async {
    try {
      final trimmed = newUrl.trim();
      if (trimmed.isEmpty) return false;
      baseUrl = trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyBaseUrl, baseUrl);
      return true;
    } catch (e) {
      debugPrint('Error saving custom base URL: $e');
      return false;
    }
  }

  /// Fetches current MT5 connection state and account info using strictly configured baseUrl.
  static Future<Map<String, dynamic>> getAccountStatus() async {
    await loadSavedBaseUrl();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/status/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Failed to connect to $baseUrl: $e');
    }

    return {'status': 'offline', 'connected': false, 'account': null};
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
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error starting instance: $e');
      return {'error': e.toString()};
    }
    return {'error': 'Failed to start instance'};
  }

  /// Stops a running algorithm instance by ID.
  static Future<bool> stopInstance(String instanceId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/instances/$instanceId/stop/'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error stopping instance: $e');
      return false;
    }
  }

  /// Lists active background worker instances.
  static Future<List<Map<String, dynamic>>> getActiveInstances() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/instances/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> list = decoded['instances'] ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching active instances: $e');
    }
    return [];
  }

  /// Lists all strategy configurations saved in database.
  static Future<List<Map<String, dynamic>>> getStrategyConfigs() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/configs/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> list = decoded['configs'] ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching strategy configs: $e');
    }
    return [];
  }

  /// Creates or updates a strategy config in database.
  static Future<bool> createStrategyConfig({
    required String name,
    required String symbol,
    required int timeframe,
    required double riskPercentage,
    required double slTpRatio,
    required String operator,
    required double signalThreshold,
    int maxActivePositions = 1,
    required Map<String, dynamic> configJson,
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
              'max_active_positions': maxActivePositions,
              'operator': operator,
              'signal_threshold': signalThreshold,
              'config_json': configJson,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Error creating strategy config: $e');
      return false;
    }
  }

  /// Deletes a strategy config by ID or name.
  static Future<bool> deleteStrategyConfig({int? id, String? name}) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/configs/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'id': ?id, 'name': ?name}),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting strategy config: $e');
      return false;
    }
  }

  /// Fetches historical trade deal logs.
  static Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/history/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> list = decoded['history'] ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
    }
    return [];
  }

  /// Evaluates an indicator or combiner on symbol rates.
  static Future<Map<String, dynamic>> evaluateIndicator({
    required String indicatorId,
    String symbol = 'EURUSD',
    int timeframe = 5,
    Map<String, dynamic>? params,
    List<Map<String, dynamic>>? indicators,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/indicator/evaluate/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'indicator_id': indicatorId,
              'symbol': symbol,
              'timeframe': timeframe,
              'params': ?params,
              'indicators': ?indicators,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error evaluating indicator: $e');
    }
    return {'latest_value': 0.0, 'bias': 'ERROR', 'series': []};
  }

  /// Runs a modular historical backtest simulation.
  static Future<Map<String, dynamic>> runBacktest({
    required Map<String, dynamic> algorithmConfig,
    required Map<String, dynamic> buyInConfig,
    required String symbol,
    required String dateFrom,
    required String dateTo,
    double initialBalance = 10000.0,
    int timeframe = 5,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/backtest/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'algorithm_config': algorithmConfig,
              'buy_in_config': buyInConfig,
              'symbol': symbol,
              'date_from': dateFrom,
              'date_to': dateTo,
              'initial_balance': initialBalance,
              'timeframe': timeframe,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        return {'error': 'Backtest HTTP error ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('Error executing backtest: $e');
      return {'error': e.toString()};
    }
  }
}
