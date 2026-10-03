class ApiEndpoints {
  static const String baseUrl = 'http://10.0.2.2:8000/api/trading';

  static const String status = '$baseUrl/status/';
  static const String executeCycle = '$baseUrl/execute/';
  static const String instances = '$baseUrl/instances/';
  static String stopInstance(String id) => '$baseUrl/instances/$id/stop/';
  static const String configs = '$baseUrl/configs/';
  static const String history = '$baseUrl/history/';
  static const String backtest = '$baseUrl/backtest/';
  static const String evaluateIndicator = '$baseUrl/indicator/evaluate/';
}
