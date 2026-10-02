import 'dart:async';
import 'package:flutter/material.dart';
import 'services/api_service.dart';

void main() {
  runApp(const AlgorithmicTraderApp());
}

// =============================================================================
// COLOR PALETTE & STYLES
// =============================================================================
class AppColors {
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFF282828);
  static const Color border = Color(0xFF2C2C2C);

  static const Color green = Color(0xFF00C853);
  static const Color red = Color(0xFFD50000);
  static const Color amber = Color(0xFFFFB300);
  static const Color mutedText = Color(0xFF9E9E9E);
  static const Color white = Colors.white;
}

class AppTextStyles {
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    color: AppColors.white,
  );

  static const TextStyle monoGreen = TextStyle(
    fontFamily: 'monospace',
    color: AppColors.green,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle monoRed = TextStyle(
    fontFamily: 'monospace',
    color: AppColors.red,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle monoMuted = TextStyle(
    fontFamily: 'monospace',
    color: AppColors.mutedText,
  );
}

// =============================================================================
// CUSTOM SPARKLINE PAINTER
// =============================================================================
class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final bool showGradient;

  SparklinePainter({
    required this.data,
    required this.lineColor,
    this.showGradient = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final double minY = data.reduce((a, b) => a < b ? a : b);
    final double maxY = data.reduce((a, b) => a > b ? a : b);
    final double rangeY = (maxY - minY) == 0 ? 1 : (maxY - minY);

    final double stepX = size.width / (data.length - 1);

    final Path path = Path();
    final List<Offset> points = [];

    for (int i = 0; i < data.length; i++) {
      final double x = i * stepX;
      final double normalizedY = (data[i] - minY) / rangeY;
      final double y = size.height - (normalizedY * (size.height - 4)) - 2;
      points.add(Offset(x, y));
    }

    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p1.dx,
        p1.dy,
      );
    }

    if (showGradient) {
      final Path fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      final Paint fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.3),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(fillPath, fillPaint);
    }

    final Paint linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.lineColor != lineColor;
  }
}

// =============================================================================
// MAIN APPLICATION ENTRY & THEME
// =============================================================================
class AlgorithmicTraderApp extends StatelessWidget {
  const AlgorithmicTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Algorithmic Trader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.green,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// =============================================================================
// DASHBOARD SCREEN (REAL-TIME EQUITY CURVE & ACTIVE WORKERS)
// =============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentNavIndex = 0;
  Timer? _pollingTimer;

  // Real MT5 Terminal Account State
  bool _isLoading = false;
  bool _isMt5Connected = false;
  double _accountBalance = 0.0;
  double _accountEquity = 0.0;
  double _accountProfit = 0.0;
  double _accountFreeMargin = 0.0;
  int _accountLeverage = 1;
  String _serverName = 'N/A';
  int _loginAccount = 0;
  String _currency = 'USD';

  List<Map<String, dynamic>> _strategyConfigs = [];
  List<Map<String, dynamic>> _activeInstances = [];
  List<Map<String, dynamic>> _historyDeals = [];

  @override
  void initState() {
    super.initState();
    _fetchBackendData();
    // 3-second live background polling stream timer
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _currentNavIndex == 0) {
        _fetchBackendData(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBackendData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);

    try {
      final status = await ApiService.getAccountStatus();
      final configs = await ApiService.getStrategyConfigs();
      final instances = await ApiService.getActiveInstances();
      final history = await ApiService.getMt5HistoryDeals();

      if (mounted) {
        setState(() {
          _isMt5Connected = status['connected'] ?? false;
          final acc = status['account'];
          if (acc != null) {
            _accountBalance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
            _accountEquity = (acc['equity'] as num?)?.toDouble() ?? 0.0;
            _accountProfit = (acc['profit'] as num?)?.toDouble() ?? 0.0;
            _accountFreeMargin = (acc['free_margin'] as num?)?.toDouble() ?? 0.0;
            _accountLeverage = (acc['leverage'] as num?)?.toInt() ?? 1;
            _serverName = acc['server']?.toString() ?? 'MT5 Terminal';
            _loginAccount = (acc['login'] as num?)?.toInt() ?? 0;
            _currency = acc['currency']?.toString() ?? 'USD';
          }
          _strategyConfigs = configs;
          _activeInstances = instances;
          _historyDeals = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pauseInstance(String instanceId) async {
    await ApiService.pauseInstance(instanceId);
    _fetchBackendData();
  }

  Future<void> _stopInstance(String instanceId) async {
    await ApiService.stopInstance(instanceId);
    _fetchBackendData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentNavIndex,
        children: [
          _buildDashboardView(),
          AlgorithmsView(
            strategyConfigs: _strategyConfigs,
            onRefreshConfigs: _fetchBackendData,
            onStartInstance: () {
              setState(() => _currentNavIndex = 0);
              _fetchBackendData();
            },
          ),
          HistoryView(
            historyDeals: _historyDeals,
            onRefreshLogs: _fetchBackendData,
          ),
          SettingsView(
            serverName: _serverName,
            loginAccount: _loginAccount,
            balance: _accountBalance,
            currency: _currency,
            isConnected: _isMt5Connected,
            onRefresh: _fetchBackendData,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final titles = ['DASHBOARD', 'ALGORITHMS', 'TRADE HISTORY', 'SETTINGS'];

    return AppBar(
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsets.only(left: 16.0),
        child: CircleAvatar(
          backgroundColor: AppColors.surfaceLight,
          child: Icon(
            Icons.person,
            color: AppColors.white,
            size: 20,
          ),
        ),
      ),
      title: Text(
        titles[_currentNavIndex],
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.refresh,
            color: _isLoading ? AppColors.amber : AppColors.white,
          ),
          onPressed: _fetchBackendData,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDashboardView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isMt5Connected) ...[
            _buildConnectionBanner(),
            const SizedBox(height: 16),
          ],
          _buildPortfolioCard(),
          const SizedBox(height: 24),
          _buildActiveInstancesHeader(),
          const SizedBox(height: 12),
          _buildActiveInstancesList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backend / MT5 Connection Standby',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  'Ensure `python back/manage.py runserver` is running and MT5 terminal is open.',
                  style: TextStyle(color: AppColors.mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.white, size: 20),
            onPressed: _fetchBackendData,
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioCard() {
    // Build real-time cumulative equity points from MT5 history deals
    final List<double> equityPoints = [];
    double totalRealizedPnl = 0.0;

    if (_historyDeals.isNotEmpty) {
      final sortedDeals = List<Map<String, dynamic>>.from(_historyDeals.reversed);
      totalRealizedPnl = sortedDeals.fold(0.0, (sum, d) => sum + ((d['profit'] as num?)?.toDouble() ?? 0.0));

      double cumulativeBalance = _accountBalance - totalRealizedPnl;
      equityPoints.add(cumulativeBalance);

      for (final deal in sortedDeals) {
        final pnl = (deal['profit'] as num?)?.toDouble() ?? 0.0;
        cumulativeBalance += pnl;
        equityPoints.add(cumulativeBalance);
      }
    }

    if (equityPoints.length < 2) {
      equityPoints.clear();
      equityPoints.addAll([_accountBalance * 0.98, _accountBalance * 0.99, _accountBalance]);
    }

    final bool isRealizedProfitPositive = totalRealizedPnl >= 0;
    final String pnlSign = isRealizedProfitPositive ? '+' : '';
    final Color pnlColor = isRealizedProfitPositive ? AppColors.green : AppColors.red;

    final bool isOpenProfitPositive = _accountProfit >= 0;
    final String openProfitSign = isOpenProfitPositive ? '+' : '';
    final Color openProfitColor = isOpenProfitPositive ? AppColors.green : AppColors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isMt5Connected ? 'MT5 ACCOUNT #$_loginAccount' : 'REAL MT5 TERMINAL',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (_isMt5Connected ? AppColors.green : AppColors.amber).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (_isMt5Connected ? AppColors.green : AppColors.amber).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _isMt5Connected ? AppColors.green : AppColors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isMt5Connected ? 'CONNECTED' : 'OFFLINE',
                      style: TextStyle(
                        color: _isMt5Connected ? AppColors.green : AppColors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '\$${_accountBalance.toStringAsFixed(2)} $_currency',
                        style: AppTextStyles.mono.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Realized P&L: $pnlSign\$${totalRealizedPnl.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: pnlColor,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Real-Time Equity Curve Chart
              SizedBox(
                width: 100,
                height: 42,
                child: CustomPaint(
                  painter: SparklinePainter(
                    data: equityPoints,
                    lineColor: pnlColor,
                    showGradient: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Equity', style: TextStyle(color: AppColors.mutedText, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text('\$${_accountEquity.toStringAsFixed(2)}', style: AppTextStyles.monoGreen.copyWith(fontSize: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Open P&L', style: TextStyle(color: AppColors.mutedText, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text('$openProfitSign\$${_accountProfit.toStringAsFixed(2)}', style: TextStyle(color: openProfitColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Free Margin', style: TextStyle(color: AppColors.mutedText, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text('\$${_accountFreeMargin.toStringAsFixed(2)}', style: AppTextStyles.mono.copyWith(fontSize: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Leverage', style: TextStyle(color: AppColors.mutedText, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text('1:$_accountLeverage', style: AppTextStyles.monoMuted.copyWith(fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Server: $_serverName',
            style: AppTextStyles.monoMuted.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveInstancesHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'ACTIVE ALGORITHM WORKERS',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_activeInstances.length} RUNNING',
                  style: AppTextStyles.monoGreen.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveInstancesList() {
    if (_activeInstances.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.memory, color: AppColors.green, size: 36),
            SizedBox(height: 10),
            Text(
              'No Continuous Workers Deployed',
              style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Switch to "Algorithms" tab, tap "RUN ALGORITHM ON MT5", select target symbol, and spawn a continuous background worker.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedText, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _activeInstances.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final inst = _activeInstances[index];
        return _buildInstanceCard(inst);
      },
    );
  }

  Widget _buildInstanceCard(Map<String, dynamic> inst) {
    final String instanceId = inst['instance_id'] ?? 'N/A';
    final String name = inst['name'] ?? 'Worker';
    final String symbol = inst['symbol'] ?? 'EURUSD';
    final int timeframe = (inst['timeframe'] as num?)?.toInt() ?? 5;
    final String status = inst['status'] ?? 'RUNNING';
    final double threshold = (inst['signal_threshold'] as num?)?.toDouble() ?? 0.5;
    final double score = (inst['latest_score'] as num?)?.toDouble() ?? 0.0;

    final bool isRunning = status == 'RUNNING';
    final bool isPaused = status == 'PAUSED';
    final bool isTriggered = status == 'TRIGGERED';

    final Color statusColor = isRunning
        ? AppColors.green
        : (isPaused ? AppColors.amber : (isTriggered ? Colors.blueAccent : AppColors.red));

    final bool isBullish = score > 0.2;
    final bool isBearish = score < -0.2;
    final Color scoreColor = isBullish ? AppColors.green : (isBearish ? AppColors.red : AppColors.amber);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name (ID: #$instanceId)',
                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TARGET: $symbol • TIMEFRAME: M$timeframe',
                      style: AppTextStyles.monoGreen.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Threshold Score Bidirectional Gauge [-1.0, 1.0] with Threshold Markers
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Polling: 5s', style: AppTextStyles.monoMuted.copyWith(fontSize: 11)),
                  Text(
                    'Score: ${score >= 0 ? "+" : ""}${score.toStringAsFixed(2)} / ±$threshold Target',
                    style: TextStyle(color: scoreColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  // Gauge track bar
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.border),
                    ),
                  ),

                  // Negative Threshold Marker (-n)
                  Align(
                    alignment: Alignment(-threshold.clamp(0.01, 1.0), 0),
                    child: Container(
                      width: 3,
                      height: 14,
                      color: AppColors.red,
                    ),
                  ),

                  // Positive Threshold Marker (+n)
                  Align(
                    alignment: Alignment(threshold.clamp(0.01, 1.0), 0),
                    child: Container(
                      width: 3,
                      height: 14,
                      color: AppColors.green,
                    ),
                  ),

                  // Center Zero Marker
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: AppColors.mutedText,
                    ),
                  ),

                  // Live Score Pointer Indicator
                  Align(
                    alignment: Alignment(score.clamp(-1.0, 1.0), 0),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: scoreColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceLight,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () => _pauseInstance(instanceId),
                icon: Icon(isRunning ? Icons.pause : Icons.play_arrow, size: 14),
                label: Text(isRunning ? 'PAUSE' : 'RESUME', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red.withValues(alpha: 0.8),
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () => _stopInstance(instanceId),
                icon: const Icon(Icons.stop, size: 14),
                label: const Text('STOP WORKER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1.0),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (index) {
          setState(() {
            _currentNavIndex = index;
          });
        },
        backgroundColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.green,
        unselectedItemColor: AppColors.mutedText,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.memory_outlined),
            activeIcon: Icon(Icons.memory),
            label: 'Algorithms',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ALGORITHMS VIEW WITH SYMBOL SELECTION MODAL & SIMPLE BUY-IN CONTROLS
// =============================================================================
class AlgorithmsView extends StatefulWidget {
  final List<Map<String, dynamic>> strategyConfigs;
  final VoidCallback onRefreshConfigs;
  final VoidCallback onStartInstance;

  const AlgorithmsView({
    super.key,
    required this.strategyConfigs,
    required this.onRefreshConfigs,
    required this.onStartInstance,
  });

  @override
  State<AlgorithmsView> createState() => _AlgorithmsViewState();
}

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

class _AlgorithmsViewState extends State<AlgorithmsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _timeframeOptions = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'];

  // Simple Buy-in State
  double _simpleBuyInRisk = 1.0;
  double _simpleBuyInRatio = 2.0;
  int _simpleBuyInMaxPositions = 1;

  // Available indicators for dynamic dropdown
  final List<Map<String, String>> _availableIndicators = [
    {'id': 'rsi', 'name': 'RSI Indicator'},
    {'id': 'macd', 'name': 'MACD Z-Score'},
    {'id': 'bollinger', 'name': 'Bollinger Bands Deviation'},
    {'id': 'stochastic', 'name': 'Stochastic Oscillator'},
  ];

  // Indicator Parameters & Timeframes Internal State
  final Map<String, String> _indicatorTimeframes = {
    'rsi': 'M5',
    'stochastic': 'M5',
    'macd': 'M5',
    'bollinger': 'M5',
  };

  final Map<String, dynamic> _rsiParams = {'period': 14};
  final Map<String, dynamic> _stochParams = {'k_period': 14, 'd_period': 3};
  final Map<String, dynamic> _macdParams = {'fast': 12, 'slow': 26, 'signal': 9, 'z_window': 100};
  final Map<String, dynamic> _bollingerParams = {'period': 20, 'std_dev': 2.0};

  // Evaluation Signals [-1.0, 1.0]
  final Map<String, double> _indicatorValues = {};
  final Map<String, String> _indicatorBiases = {};
  final Map<String, List<double>> _indicatorSeries = {};

  // Custom Algorithm Evaluation Scores [-1.0, 1.0]
  final Map<String, double> _algoScores = {};
  final Map<String, String> _algoBiases = {};
  final Map<String, List<double>> _algoSeries = {};

  bool _evaluating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _getParamsForIndicator(String indicatorId) {
    switch (indicatorId) {
      case 'rsi':
        return Map<String, dynamic>.from(_rsiParams);
      case 'stochastic':
        return Map<String, dynamic>.from(_stochParams);
      case 'macd':
        return Map<String, dynamic>.from(_macdParams);
      case 'bollinger':
        return Map<String, dynamic>.from(_bollingerParams);
      default:
        return {};
    }
  }

  Future<void> _testIndicator(String indicatorId) async {
    setState(() => _evaluating = true);
    final params = _getParamsForIndicator(indicatorId);
    final tf = _indicatorTimeframes[indicatorId] ?? 'M5';

    final res = await ApiService.evaluateIndicator(
      indicatorId: indicatorId,
      symbol: 'EURUSD',
      timeframe: int.tryParse(tf.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5,
      params: {...params, 'timeframe': tf},
    );

    if (mounted) {
      setState(() {
        final val = (res['latest_value'] as num?)?.toDouble() ?? 0.0;
        _indicatorValues[indicatorId] = val;
        _indicatorBiases[indicatorId] = res['bias']?.toString() ?? 'NEUTRAL (0.00)';

        final List<dynamic> seriesList = res['series'] ?? [];
        _indicatorSeries[indicatorId] = seriesList.map((e) => (e as num).toDouble()).toList();
        _evaluating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Indicator $indicatorId ($tf) evaluated: ${_indicatorBiases[indicatorId]}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _testAlgorithmScore(Map<String, dynamic> config) async {
    setState(() => _evaluating = true);

    final String algoKey = config['id']?.toString() ?? config['name'] ?? 'Algo';
    final configJson = (config['config_json'] as Map<String, dynamic>?) ?? {};
    final List<dynamic> rawIndicators = configJson['indicators'] ?? [];

    List<Map<String, dynamic>> payloadIndicators = [];
    for (final item in rawIndicators) {
      if (item is Map<String, dynamic>) {
        payloadIndicators.add(item);
      }
    }

    final res = await ApiService.evaluateIndicator(
      indicatorId: 'weighted_combiner',
      symbol: 'EURUSD',
      timeframe: 5,
      indicators: payloadIndicators.isNotEmpty ? payloadIndicators : null,
    );

    if (mounted) {
      setState(() {
        final val = (res['latest_value'] as num?)?.toDouble() ?? 0.0;
        _algoScores[algoKey] = val;
        _algoBiases[algoKey] = res['bias']?.toString() ?? 'NEUTRAL (0.00)';

        final List<dynamic> seriesList = res['series'] ?? [];
        _algoSeries[algoKey] = seriesList.map((e) => (e as num).toDouble()).toList();
        _evaluating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Algorithm "${config['name']}" Signal: ${_algoBiases[algoKey]}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openSymbolSelectionModal(Map<String, dynamic> config) {
    String selectedSymbol = 'EURUSD';
    String selectedTf = 'M5';
    final symbolCtrl = TextEditingController(text: 'EURUSD');

    final availableSymbols = ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'BTCUSD', 'XAUUSD'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Deploy Worker: ${config['name']}',
                        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.mutedText),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 10),
                  const Text('SELECT TARGET ASSET SYMBOL', style: TextStyle(color: AppColors.mutedText, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSymbol,
                    dropdownColor: AppColors.surfaceLight,
                    decoration: const InputDecoration(filled: true, fillColor: AppColors.surfaceLight),
                    items: availableSymbols.map((sym) => DropdownMenuItem(value: sym, child: Text(sym))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          selectedSymbol = val;
                          symbolCtrl.text = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: symbolCtrl,
                    decoration: const InputDecoration(labelText: 'OR TYPE CUSTOM SYMBOL (e.g. BTCUSD)', filled: true, fillColor: AppColors.surfaceLight),
                    onChanged: (val) {
                      selectedSymbol = val.trim().toUpperCase();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTf,
                    dropdownColor: AppColors.surfaceLight,
                    decoration: const InputDecoration(labelText: 'TIMEFRAME', filled: true, fillColor: AppColors.surfaceLight),
                    items: _timeframeOptions.map((tf) => DropdownMenuItem(value: tf, child: Text(tf))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedTf = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final tfMinutes = int.tryParse(selectedTf.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                        final String finalSymbol = symbolCtrl.text.trim().isNotEmpty ? symbolCtrl.text.trim().toUpperCase() : selectedSymbol;

                        final configJson = (config['config_json'] as Map<String, dynamic>?) ?? {};
                        final List<dynamic> rawIndicators = configJson['indicators'] ?? [];
                        List<Map<String, dynamic>> payloadIndicators = [];
                        for (final item in rawIndicators) {
                          if (item is Map<String, dynamic>) payloadIndicators.add(item);
                        }

                        Navigator.of(ctx).pop();

                        await ApiService.startInstance(
                          name: config['name'] ?? 'Strategy Instance',
                          symbol: finalSymbol,
                          timeframe: tfMinutes,
                          riskPercentage: _simpleBuyInRisk,
                          slTpRatio: _simpleBuyInRatio,
                          operator: config['operator'] ?? 'WEIGHTED',
                          signalThreshold: (config['signal_threshold'] as num?)?.toDouble() ?? 0.5,
                          maxActivePositions: _simpleBuyInMaxPositions,
                          indicators: payloadIndicators,
                        );

                        if (context.mounted) {
                          widget.onStartInstance();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Continuous Worker started on $finalSymbol (M$tfMinutes)!')),
                          );
                        }
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('START BACKGROUND WORKER', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openIndicatorConfigModal(String indicatorId, String title) {
    final Map<String, dynamic> currentParams = _getParamsForIndicator(indicatorId);
    String currentTimeframe = _indicatorTimeframes[indicatorId] ?? 'M5';
    final controllers = <String, TextEditingController>{};

    currentParams.forEach((key, val) {
      controllers[key] = TextEditingController(text: val.toString());
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Configure $title',
                        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.mutedText),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: currentTimeframe,
                    dropdownColor: AppColors.surfaceLight,
                    decoration: const InputDecoration(
                      labelText: 'TIMEFRAME',
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(),
                    ),
                    items: _timeframeOptions.map((tf) {
                      return DropdownMenuItem(value: tf, child: Text(tf));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => currentTimeframe = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  ...controllers.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextField(
                        controller: entry.value,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: entry.key.replaceAll('_', ' ').toUpperCase(),
                          labelStyle: const TextStyle(color: AppColors.mutedText),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _indicatorTimeframes[indicatorId] = currentTimeframe;
                          controllers.forEach((key, controller) {
                            final valStr = controller.text;
                            final parsedNum = num.tryParse(valStr);
                            if (parsedNum != null) {
                              if (indicatorId == 'rsi') _rsiParams[key] = parsedNum.toInt();
                              if (indicatorId == 'stochastic') _stochParams[key] = parsedNum.toInt();
                              if (indicatorId == 'macd') _macdParams[key] = parsedNum.toInt();
                              if (indicatorId == 'bollinger') _bollingerParams[key] = parsedNum.toDouble();
                            }
                          });
                        });
                        Navigator.of(ctx).pop();
                        _testIndicator(indicatorId);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('SAVE & RE-EVALUATE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openAlgorithmBuilderModal({Map<String, dynamic>? existingConfig}) {
    final bool isEditing = existingConfig != null;
    final nameCtrl = TextEditingController(
      text: isEditing ? existingConfig['name'] : 'Asset-Agnostic Strategy ${widget.strategyConfigs.length + 1}',
    );
    final thresholdCtrl = TextEditingController(
      text: isEditing ? (existingConfig['signal_threshold'] ?? 0.5).toString() : '0.5',
    );
    String selectedOperator = isEditing ? (existingConfig['operator'] ?? 'WEIGHTED') : 'WEIGHTED';
    String selectedBuyInMethod = 'Simple Buy-in';
    String selectedIndicatorToAdd = 'rsi';

    List<ConfiguredIndicatorItem> selectedIndicators = [];

    if (isEditing && existingConfig['config_json'] != null) {
      final configJson = (existingConfig['config_json'] as Map<String, dynamic>?) ?? {};
      final List<dynamic> savedIndicators = configJson['indicators'] ?? [];
      for (final item in savedIndicators) {
        if (item is Map<String, dynamic>) {
          selectedIndicators.add(ConfiguredIndicatorItem.fromJson(item));
        }
      }
    }

    if (selectedIndicators.isEmpty) {
      selectedIndicators = [
        ConfiguredIndicatorItem(id: 'rsi', name: 'RSI Indicator', timeframe: 'M5', params: {'period': 14}, weight: 0.40),
        ConfiguredIndicatorItem(id: 'macd', name: 'MACD Z-Score', timeframe: 'M5', params: {'fast': 12, 'slow': 26, 'signal': 9, 'z_window': 100}, weight: 0.60),
      ];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final double totalWeight = selectedIndicators.fold(0.0, (sum, ind) => sum + ind.weight);

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Edit Custom Algorithm' : 'Build Asset-Agnostic Algorithm',
                          style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.mutedText),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'ALGORITHM NAME', filled: true, fillColor: AppColors.surfaceLight),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedOperator,
                            isExpanded: true,
                            dropdownColor: AppColors.surfaceLight,
                            decoration: const InputDecoration(
                              labelText: 'COMBINER LOGIC',
                              filled: true,
                              fillColor: AppColors.surfaceLight,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'WEIGHTED', child: Text('WEIGHTED AVERAGE', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'OR', child: Text('OR (Any Signal)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'AND', child: Text('AND (All Agree)', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (val) {
                              if (val != null) setModalState(() => selectedOperator = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: thresholdCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'SIGNAL THRESHOLD (n)', filled: true, fillColor: AppColors.surfaceLight),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Buy-in Method Selector Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: selectedBuyInMethod,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceLight,
                      decoration: const InputDecoration(
                        labelText: 'ASSIGN BUY-IN METHOD',
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Simple Buy-in', child: Text('Simple Buy-in (Risk % & SL/TP Ratio)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedBuyInMethod = val);
                      },
                    ),

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'INCLUDED INDICATORS (${selectedIndicators.length})',
                          style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          'Total Weight: ${totalWeight.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: (totalWeight - 1.0).abs() < 0.05 ? AppColors.green : AppColors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Granular Indicator Cards
                    ...selectedIndicators.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ind = entry.value;

                      final weightCtrl = TextEditingController(text: ind.weight.toStringAsFixed(2));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ind.name,
                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                                  onPressed: () {
                                    if (selectedIndicators.length > 1) {
                                      setModalState(() {
                                        selectedIndicators.removeAt(idx);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: ind.timeframe,
                                    dropdownColor: AppColors.surface,
                                    decoration: const InputDecoration(labelText: 'TIMEFRAME', filled: true, fillColor: AppColors.surface),
                                    items: _timeframeOptions.map((tf) => DropdownMenuItem(value: tf, child: Text(tf))).toList(),
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => ind.timeframe = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: weightCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'WEIGHT (e.g. 0.40)', filled: true, fillColor: AppColors.surface),
                                    onChanged: (val) {
                                      final parsed = double.tryParse(val);
                                      if (parsed != null) {
                                        ind.weight = parsed;
                                        setModalState(() {});
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Granular Specific Parameters
                            if (ind.id == 'rsi') ...[
                              TextField(
                                controller: TextEditingController(text: (ind.params['period'] ?? 14).toString()),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'RSI PERIOD', filled: true, fillColor: AppColors.surface),
                                onChanged: (val) {
                                  final p = int.tryParse(val);
                                  if (p != null) ind.params['period'] = p;
                                },
                              ),
                            ] else if (ind.id == 'macd') ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: (ind.params['fast'] ?? 12).toString()),
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'FAST PERIOD', filled: true, fillColor: AppColors.surface),
                                      onChanged: (val) {
                                        final p = int.tryParse(val);
                                        if (p != null) ind.params['fast'] = p;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: (ind.params['slow'] ?? 26).toString()),
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'SLOW PERIOD', filled: true, fillColor: AppColors.surface),
                                      onChanged: (val) {
                                        final p = int.tryParse(val);
                                        if (p != null) ind.params['slow'] = p;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (ind.id == 'stochastic') ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: (ind.params['k_period'] ?? 14).toString()),
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: '%K PERIOD', filled: true, fillColor: AppColors.surface),
                                      onChanged: (val) {
                                        final p = int.tryParse(val);
                                        if (p != null) ind.params['k_period'] = p;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: (ind.params['d_period'] ?? 3).toString()),
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: '%D PERIOD', filled: true, fillColor: AppColors.surface),
                                      onChanged: (val) {
                                        final p = int.tryParse(val);
                                        if (p != null) ind.params['d_period'] = p;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (ind.id == 'bollinger') ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: (ind.params['period'] ?? 20).toString()),
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'PERIOD', filled: true, fillColor: AppColors.surface),
                                      onChanged: (val) {
                                        final p = int.tryParse(val);
                                        if (p != null) ind.params['period'] = p;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: (ind.params['std_dev'] ?? 2.0).toString()),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: 'STD DEV', filled: true, fillColor: AppColors.surface),
                                      onChanged: (val) {
                                        final p = double.tryParse(val);
                                        if (p != null) ind.params['std_dev'] = p;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 8),

                    // Dynamic Indicator Selection Dropdown
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedIndicatorToAdd,
                            isExpanded: true,
                            dropdownColor: AppColors.surfaceLight,
                            decoration: const InputDecoration(
                              labelText: 'SELECT INDICATOR TO APPEND',
                              filled: true,
                              fillColor: AppColors.surfaceLight,
                            ),
                            items: _availableIndicators.map((item) {
                              return DropdownMenuItem<String>(
                                value: item['id'],
                                child: Text(item['name']!, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setModalState(() => selectedIndicatorToAdd = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                          onPressed: () {
                            setModalState(() {
                              final match = _availableIndicators.firstWhere((i) => i['id'] == selectedIndicatorToAdd);
                              selectedIndicators.add(
                                ConfiguredIndicatorItem(
                                  id: match['id']!,
                                  name: match['name']!,
                                  timeframe: 'M5',
                                  params: _getParamsForIndicator(match['id']!),
                                  weight: 0.30,
                                ),
                              );
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('APPEND', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final threshold = double.tryParse(thresholdCtrl.text) ?? 0.5;

                          final serializedIndicators = selectedIndicators.map((e) => e.toJson()).toList();

                          // Persist strategy config in Django DB
                          await ApiService.createStrategyConfig(
                            name: name.isNotEmpty ? name : 'Asset-Agnostic Strategy',
                            symbol: 'EURUSD',
                            timeframe: 5,
                            riskPercentage: _simpleBuyInRisk,
                            slTpRatio: _simpleBuyInRatio,
                            operator: selectedOperator,
                            signalThreshold: threshold,
                            configJson: {
                              'indicators': serializedIndicators,
                              'operator': selectedOperator,
                              'threshold': threshold,
                              'buyInMethod': selectedBuyInMethod,
                            },
                          );

                          if (context.mounted) {
                            Navigator.of(ctx).pop();
                            widget.onRefreshConfigs();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Algorithm "$name" Persisted Successfully!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('PERSIST ALGORITHM TO DATABASE', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAlgorithm(Map<String, dynamic> config) {
    final int? id = (config['id'] as num?)?.toInt();
    final String name = config['name'] ?? 'Algorithm';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Algorithm?', style: TextStyle(color: AppColors.white)),
        content: Text('Are you sure you want to delete "$name"?', style: const TextStyle(color: AppColors.mutedText)),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: AppColors.mutedText)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('DELETE', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ApiService.deleteStrategyConfig(id: id, name: name);
              widget.onRefreshConfigs();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Algorithm "$name" deleted successfully.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.green,
            labelColor: AppColors.green,
            unselectedLabelColor: AppColors.mutedText,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Custom Algorithms'),
              Tab(text: 'Indicators'),
              Tab(text: 'Buy-in methods'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCustomAlgorithmsSection(),
              _buildIndicatorsSection(),
              _buildBuyInMethodsSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomAlgorithmsSection() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'YOUR CUSTOM ALGORITHMS',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _openAlgorithmBuilderModal(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Build Algorithm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.strategyConfigs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14.0),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: const [
                  Icon(Icons.memory, color: AppColors.green, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'No Custom Algorithms Configured Yet',
                    style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap "+ Build Algorithm" above to combine multi-timeframe indicators into a symbol-agnostic strategy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.mutedText, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.strategyConfigs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final config = widget.strategyConfigs[index];
                return _buildCustomAlgoCard(config);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCustomAlgoCard(Map<String, dynamic> config) {
    final String name = config['name'] ?? 'Custom Strategy';
    final String operator = config['operator'] ?? 'WEIGHTED';
    final double threshold = (config['signal_threshold'] as num?)?.toDouble() ?? 0.5;
    final String algoKey = config['id']?.toString() ?? name;

    final double score = _algoScores[algoKey] ?? 0.0;
    final String bias = _algoBiases[algoKey] ?? 'NEUTRAL (0.00)';
    final List<double> series = _algoSeries[algoKey] ?? [0.0, 0.1, 0.3, 0.2, 0.5];

    final bool isBullish = score > 0.2;
    final bool isBearish = score < -0.2;
    final Color scoreColor = isBullish ? AppColors.green : (isBearish ? AppColors.red : AppColors.amber);

    return InkWell(
      onTap: () => _openAlgorithmBuilderModal(existingConfig: config),
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text('ASSET-AGNOSTIC PIPELINE • Tap to Edit', style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceLight,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () => _testAlgorithmScore(config),
                      icon: const Icon(Icons.analytics, size: 14),
                      label: const Text('TEST SIGNAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.red),
                      onPressed: () => _confirmDeleteAlgorithm(config),
                      tooltip: 'Delete Algorithm',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Signal Thresh: ±$threshold', style: AppTextStyles.mono.copyWith(fontSize: 12)),
                Text('Combiner: $operator', style: AppTextStyles.monoGreen.copyWith(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),

            // Continuous Signal Score Gauge [-1.0, 1.0]
            Row(
              children: [
                const Text('-1.0 (SELL)', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Align(
                          alignment: Alignment(((score.clamp(-1.0, 1.0))), 0),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: scoreColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text('+1.0 (BUY)', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Composite Score: ', style: TextStyle(color: AppColors.mutedText, fontSize: 12)),
                    Text(
                      bias,
                      style: TextStyle(color: scoreColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                if (series.isNotEmpty)
                  SizedBox(
                    width: 60,
                    height: 24,
                    child: CustomPaint(
                      painter: SparklinePainter(data: series, lineColor: scoreColor, showGradient: false),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _openSymbolSelectionModal(config),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('RUN ALGORITHM ON MT5', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorsSection() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NORMALIZED CONTINUOUS INDICATORS [-1.0, +1.0]',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap any indicator card below to open its mathematical settings modal.',
            style: TextStyle(color: AppColors.mutedText, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // 1. RSI Indicator
          _buildIndicatorCard(
            id: 'rsi',
            name: 'RSI Indicator (Normalized)',
            formula: '(RSI - 50) / 50',
            params: 'Period: ${_rsiParams['period']} | TF: ${_indicatorTimeframes['rsi']}',
            value: _indicatorValues['rsi'] ?? 0.0,
            bias: _indicatorBiases['rsi'] ?? 'NEUTRAL (0.00)',
            series: _indicatorSeries['rsi'] ?? [0.0, 0.1, -0.2, 0.3, 0.4, 0.2, 0.5],
            onTapCard: () => _openIndicatorConfigModal('rsi', 'RSI Indicator'),
            onTest: () => _testIndicator('rsi'),
          ),
          const SizedBox(height: 12),

          // 2. Stochastic Oscillator
          _buildIndicatorCard(
            id: 'stochastic',
            name: 'Stochastic Oscillator (Normalized)',
            formula: '(Stoch %K - 50) / 50',
            params: '%K Period: ${_stochParams['k_period']}, %D Period: ${_stochParams['d_period']} | TF: ${_indicatorTimeframes['stochastic']}',
            value: _indicatorValues['stochastic'] ?? 0.0,
            bias: _indicatorBiases['stochastic'] ?? 'NEUTRAL (0.00)',
            series: _indicatorSeries['stochastic'] ?? [-0.3, -0.4, -0.2, 0.0, 0.2, 0.6],
            onTapCard: () => _openIndicatorConfigModal('stochastic', 'Stochastic Oscillator'),
            onTest: () => _testIndicator('stochastic'),
          ),
          const SizedBox(height: 12),

          // 3. MACD Z-Score
          _buildIndicatorCard(
            id: 'macd',
            name: 'MACD Z-Score (Squashed)',
            formula: 'np.tanh(Z-score(Histogram))',
            params: 'Fast: ${_macdParams['fast']}, Slow: ${_macdParams['slow']}, Signal: ${_macdParams['signal']}, Window: ${_macdParams['z_window']} | TF: ${_indicatorTimeframes['macd']}',
            value: _indicatorValues['macd'] ?? 0.0,
            bias: _indicatorBiases['macd'] ?? 'NEUTRAL (0.00)',
            series: _indicatorSeries['macd'] ?? [0.1, 0.3, 0.5, 0.7, 0.6, 0.8],
            onTapCard: () => _openIndicatorConfigModal('macd', 'MACD Z-Score'),
            onTest: () => _testIndicator('macd'),
          ),
          const SizedBox(height: 12),

          // 4. Bollinger Bands Deviation
          _buildIndicatorCard(
            id: 'bollinger',
            name: 'Bollinger Bands Deviation',
            formula: 'np.tanh((SMA - Close) / (Std * Dev))',
            params: 'Period: ${_bollingerParams['period']}, Std Dev: ${_bollingerParams['std_dev']} | TF: ${_indicatorTimeframes['bollinger']}',
            value: _indicatorValues['bollinger'] ?? 0.0,
            bias: _indicatorBiases['bollinger'] ?? 'NEUTRAL (0.00)',
            series: _indicatorSeries['bollinger'] ?? [0.2, 0.0, -0.3, -0.6, -0.4],
            onTapCard: () => _openIndicatorConfigModal('bollinger', 'Bollinger Bands Deviation'),
            onTest: () => _testIndicator('bollinger'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildIndicatorCard({
    required String id,
    required String name,
    required String formula,
    required String params,
    required double value,
    required String bias,
    required List<double> series,
    required VoidCallback onTapCard,
    required VoidCallback onTest,
  }) {
    final bool isBullish = value > 0.2;
    final bool isBearish = value < -0.2;
    final Color valueColor = isBullish ? AppColors.green : (isBearish ? AppColors.red : AppColors.amber);

    return InkWell(
      onTap: onTapCard,
      borderRadius: BorderRadius.circular(14.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.settings, size: 14, color: AppColors.mutedText),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(formula, style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceLight,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: _evaluating ? null : onTest,
                  icon: const Icon(Icons.analytics, size: 14),
                  label: const Text('TEST SIGNAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(params, style: AppTextStyles.monoMuted.copyWith(fontSize: 11)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('-1.0 (SELL)', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Align(
                          alignment: Alignment(((value.clamp(-1.0, 1.0))), 0),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: valueColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text('+1.0 (BUY)', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Live Signal: ', style: TextStyle(color: AppColors.mutedText, fontSize: 12)),
                    Text(
                      bias,
                      style: TextStyle(color: valueColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                if (series.isNotEmpty)
                  SizedBox(
                    width: 60,
                    height: 24,
                    child: CustomPaint(
                      painter: SparklinePainter(data: series, lineColor: valueColor, showGradient: false),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Single "Simple Buy-in" Configuration Card
  Widget _buildBuyInMethodsSection() {
    final riskCtrl = TextEditingController(text: _simpleBuyInRisk.toStringAsFixed(1));
    final ratioCtrl = TextEditingController(text: _simpleBuyInRatio.toStringAsFixed(1));
    final maxPosCtrl = TextEditingController(text: _simpleBuyInMaxPositions.toString());

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SIMPLE BUY-IN CONFIGURATION',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Configure execution parameters, risk, SL/TP ratios, and position caps for simple buy-in trades.',
            style: TextStyle(color: AppColors.mutedText, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(Icons.calculate, color: AppColors.green, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Simple Buy-in Execution Model',
                            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          SizedBox(height: 2),
                          Text('Swing Extrema SL/TP & Max Position Control', style: TextStyle(color: AppColors.mutedText, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: riskCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'RISK PERCENTAGE (%)',
                          hintText: 'e.g. 1.0',
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                        ),
                        onChanged: (val) {
                          final p = double.tryParse(val);
                          if (p != null) {
                            setState(() => _simpleBuyInRisk = p);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: ratioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'SL / TP RATIO',
                          hintText: 'e.g. 2.0',
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                        ),
                        onChanged: (val) {
                          final p = double.tryParse(val);
                          if (p != null) {
                            setState(() => _simpleBuyInRatio = p);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxPosCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'MAX POSITIONS CAP',
                          hintText: 'e.g. 1',
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                        ),
                        onChanged: (val) {
                          final p = int.tryParse(val);
                          if (p != null) {
                            setState(() => _simpleBuyInMaxPositions = p);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      final r = double.tryParse(riskCtrl.text) ?? 1.0;
                      final ratio = double.tryParse(ratioCtrl.text) ?? 2.0;
                      final maxP = int.tryParse(maxPosCtrl.text) ?? 1;
                      setState(() {
                        _simpleBuyInRisk = r;
                        _simpleBuyInRatio = ratio;
                        _simpleBuyInMaxPositions = maxP;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Simple Buy-in Saved: Risk $r%, SL/TP Ratio $ratio, Max Positions $maxP')),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('SAVE BUY-IN CONFIGURATION', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// =============================================================================
// HISTORY VIEW (CONSOLIDATED ROUND-TRIP POSITIONS WITH DURATION)
// =============================================================================
class HistoryView extends StatelessWidget {
  final List<Map<String, dynamic>> historyDeals;
  final VoidCallback onRefreshLogs;

  const HistoryView({
    super.key,
    required this.historyDeals,
    required this.onRefreshLogs,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('CONSOLIDATED MT5 POSITION HISTORY', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              IconButton(icon: const Icon(Icons.refresh, color: AppColors.green), onPressed: onRefreshLogs),
            ],
          ),
          const SizedBox(height: 12),
          if (historyDeals.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12.0), border: Border.all(color: AppColors.border)),
              child: const Center(
                child: Text('No closed positions recorded on connected MT5 account yet.', style: TextStyle(color: AppColors.mutedText, fontSize: 12)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: historyDeals.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final deal = historyDeals[index];
                return _buildPositionCard(deal);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPositionCard(Map<String, dynamic> deal) {
    final String direction = deal['direction'] ?? deal['type'] ?? 'BUY';
    final bool isBuy = direction == 'BUY';
    final double profit = (deal['profit'] as num?)?.toDouble() ?? 0.0;
    final bool isProfit = profit >= 0;
    final String duration = deal['duration'] ?? 'N/A';

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isBuy ? AppColors.green : AppColors.red).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      direction,
                      style: TextStyle(
                        color: isBuy ? AppColors.green : AppColors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${deal['symbol']} • ${deal['volume']} Lots',
                    style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Text(
                '${isProfit ? "+" : ""}\$${profit.toStringAsFixed(2)}',
                style: TextStyle(
                  color: isProfit ? AppColors.green : AppColors.red,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Entry: \$${deal['open_price']} → Exit: \$${deal['close_price']}',
                style: AppTextStyles.mono.copyWith(fontSize: 11),
              ),
              Text(
                'Pos #${deal['position_id'] ?? deal['ticket']}',
                style: AppTextStyles.monoMuted.copyWith(fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Open: ${deal['open_time']}',
                style: AppTextStyles.monoMuted.copyWith(fontSize: 10),
              ),
              Text(
                'Duration: $duration',
                style: AppTextStyles.monoGreen.copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SETTINGS VIEW
// =============================================================================
class SettingsView extends StatefulWidget {
  final String serverName;
  final int loginAccount;
  final double balance;
  final String currency;
  final bool isConnected;
  final VoidCallback onRefresh;

  const SettingsView({
    super.key,
    required this.serverName,
    required this.loginAccount,
    required this.balance,
    required this.currency,
    required this.isConnected,
    required this.onRefresh,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ApiService.baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SYSTEM & API SETTINGS', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12.0), border: Border.all(color: AppColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BACKEND DJANGO API BASE URL', style: TextStyle(color: AppColors.mutedText, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(filled: true, fillColor: AppColors.surfaceLight, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: AppColors.background),
                    onPressed: () {
                      setState(() {
                        ApiService.baseUrl = _urlCtrl.text;
                      });
                      widget.onRefresh();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('API URL updated to ${ApiService.baseUrl}')));
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('UPDATE API BASE URL', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12.0), border: Border.all(color: AppColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('METATRADER 5 TERMINAL DIAGNOSTIC', style: TextStyle(color: AppColors.mutedText, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('Connection Status: ${widget.isConnected ? "ONLINE" : "STANDBY"}', style: TextStyle(color: widget.isConnected ? AppColors.green : AppColors.amber, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Account Number: #${widget.loginAccount}', style: const TextStyle(color: AppColors.white)),
                Text('Server: ${widget.serverName}', style: const TextStyle(color: AppColors.white)),
                Text('Balance: \$${widget.balance.toStringAsFixed(2)} ${widget.currency}', style: const TextStyle(color: AppColors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
