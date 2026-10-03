import 'dart:math';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../main.dart' show AppColors, AppTextStyles, SparklinePainter;

class BacktestScreen extends StatefulWidget {
  final Map<String, dynamic> algorithmConfig;

  const BacktestScreen({super.key, required this.algorithmConfig});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 90));
  DateTime _dateTo = DateTime.now();

  String _selectedSymbol = 'EURUSD';
  String _selectedBuyInMethod = 'Simple Buy-in';
  final TextEditingController _balanceCtrl = TextEditingController(text: '10000');
  final TextEditingController _symbolCtrl = TextEditingController(text: 'EURUSD');

  late TextEditingController _riskCtrl;
  late TextEditingController _ratioCtrl;
  late TextEditingController _maxPosCtrl;

  final List<String> _availableSymbols = ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'BTCUSD', 'XAUUSD'];

  bool _isBacktesting = false;
  Map<String, dynamic>? _backtestReport;

  @override
  void initState() {
    super.initState();
    final config = widget.algorithmConfig;
    final double initRisk = (config['risk_percentage'] as num?)?.toDouble() ?? 1.0;
    final double initRatio = (config['sl_tp_ratio'] as num?)?.toDouble() ?? 2.0;
    final int initMaxPos = (config['max_active_positions'] as num?)?.toInt() ?? 1;

    _riskCtrl = TextEditingController(text: initRisk.toStringAsFixed(1));
    _ratioCtrl = TextEditingController(text: initRatio.toStringAsFixed(1));
    _maxPosCtrl = TextEditingController(text: initMaxPos.toString());
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.green,
              onPrimary: AppColors.background,
              surface: AppColors.surface,
              onSurface: AppColors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
    }
  }

  Future<void> _executeBacktest() async {
    setState(() => _isBacktesting = true);

    final String finalSymbol = _symbolCtrl.text.trim().isNotEmpty
        ? _symbolCtrl.text.trim().toUpperCase()
        : _selectedSymbol;

    final double initialBal = double.tryParse(_balanceCtrl.text) ?? 10000.0;
    final double risk = double.tryParse(_riskCtrl.text) ?? 1.0;
    final double ratio = double.tryParse(_ratioCtrl.text) ?? 2.0;
    final int maxPos = int.tryParse(_maxPosCtrl.text) ?? 1;

    final configJson = (widget.algorithmConfig['config_json'] as Map<String, dynamic>?) ?? {};
    final List<dynamic> rawIndicators = configJson['indicators'] ?? [];
    List<Map<String, dynamic>> payloadIndicators = [];
    for (final item in rawIndicators) {
      if (item is Map<String, dynamic>) payloadIndicators.add(item);
    }

    final algoConfig = {
      'indicators': payloadIndicators,
      'operator': widget.algorithmConfig['operator'] ?? 'WEIGHTED',
      'signal_threshold': (widget.algorithmConfig['signal_threshold'] as num?)?.toDouble() ?? 0.5,
    };

    final buyInConfig = {
      'method': _selectedBuyInMethod,
      'risk_percentage': risk,
      'sl_tp_ratio': ratio,
      'max_active_positions': maxPos,
    };

    final res = await ApiService.runBacktest(
      algorithmConfig: algoConfig,
      buyInConfig: buyInConfig,
      symbol: finalSymbol,
      dateFrom: _dateFrom.toIso8601String().split('T').first,
      dateTo: _dateTo.toIso8601String().split('T').first,
      initialBalance: initialBal,
      timeframe: 5,
    );

    if (mounted) {
      setState(() {
        _isBacktesting = false;
        if (res.containsKey('report')) {
          _backtestReport = res['report'] as Map<String, dynamic>;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['error'] ?? 'Backtest failed')),
          );
        }
      });
    }
  }

  void _showTradeChartModal(Map<String, dynamic> trade) {
    final List<dynamic> rawSlice = trade['candle_slice'] ?? [];
    final List<Map<String, dynamic>> candleSlice = rawSlice.cast<Map<String, dynamic>>();

    final int entryIdx = (trade['entry_slice_index'] as num?)?.toInt() ?? 0;
    final int exitIdx = (trade['exit_slice_index'] as num?)?.toInt() ?? (candleSlice.length - 1);

    final double entryPrice = (trade['entry_price'] as num?)?.toDouble() ?? 0.0;
    final double exitPrice = (trade['exit_price'] as num?)?.toDouble() ?? 0.0;
    final double slPrice = (trade['sl_price'] as num?)?.toDouble() ?? 0.0;
    final double tpPrice = (trade['tp_price'] as num?)?.toDouble() ?? 0.0;
    final String direction = trade['type'] ?? 'BUY';
    final double profit = (trade['profit'] as num?)?.toDouble() ?? 0.0;
    final bool isProfit = profit >= 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.background,
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (direction == 'BUY' ? AppColors.green : AppColors.red).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  direction,
                                  style: TextStyle(
                                    color: direction == 'BUY' ? AppColors.green : AppColors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Trade #${trade['trade_id']} • ${trade['symbol']}',
                                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Volume: ${trade['volume']} Lots • Exit: ${trade['exit_reason']}',
                            style: AppTextStyles.monoMuted.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isProfit ? "+" : ""}\$${profit.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isProfit ? AppColors.green : AppColors.red,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.mutedText),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const Divider(color: AppColors.border, height: 20),

                // Interactive MT5 Candlestick Chart Canvas
                Container(
                  height: 300,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: CustomPaint(
                    painter: Mt5CandlestickPainter(
                      candleSlice: candleSlice,
                      entrySliceIndex: entryIdx,
                      exitSliceIndex: exitIdx,
                      entryPrice: entryPrice,
                      exitPrice: exitPrice,
                      slPrice: slPrice,
                      tpPrice: tpPrice,
                      direction: direction,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Footer Details Grid
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Entry Price: \$${entryPrice.toStringAsFixed(5)}', style: AppTextStyles.mono.copyWith(fontSize: 11)),
                          Text('Exit Price: \$${exitPrice.toStringAsFixed(5)}', style: AppTextStyles.mono.copyWith(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Stop Loss: \$${slPrice.toStringAsFixed(5)}', style: AppTextStyles.monoRed.copyWith(fontSize: 11)),
                          Text('Take Profit: \$${tpPrice.toStringAsFixed(5)}', style: AppTextStyles.monoGreen.copyWith(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('In: ${trade['entry_time']}', style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
                          Text('Out: ${trade['exit_time']}', style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String algoName = widget.algorithmConfig['name'] ?? 'Strategy Backtest';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'BACKTEST: ${algoName.toUpperCase()}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConfigurationCard(),
            const SizedBox(height: 20),
            if (_isBacktesting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14.0),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: const [
                    CircularProgressIndicator(color: AppColors.green),
                    SizedBox(height: 16),
                    Text(
                      'Simulating Bar-by-Bar Historical Cycles...',
                      style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Evaluating normalized signals, SL/TP levels, and position life cycles without lookahead bias.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.mutedText, fontSize: 11),
                    ),
                  ],
                ),
              )
            else if (_backtestReport != null) ...[
              _buildKpiMetricsGrid(),
              const SizedBox(height: 20),
              _buildEquityCurveChartCard(),
              const SizedBox(height: 20),
              _buildSimulatedTradesListCard(),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationCard() {
    final String dateFromStr = _dateFrom.toString().split(' ').first;
    final String dateToStr = _dateTo.toString().split(' ').first;

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
            children: const [
              Icon(Icons.tune, color: AppColors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'BACKTEST CONFIGURATION',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),

          // Date Range Picker Button
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.date_range, color: AppColors.mutedText, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Range: $dateFromStr  →  $dateToStr',
                        style: AppTextStyles.mono.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const Icon(Icons.edit, color: AppColors.green, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedSymbol,
                  dropdownColor: AppColors.surfaceLight,
                  decoration: const InputDecoration(
                    labelText: 'SELECT SYMBOL',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
                  items: _availableSymbols.map((sym) => DropdownMenuItem(value: sym, child: Text(sym))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedSymbol = val;
                        _symbolCtrl.text = val;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _balanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'INITIAL BALANCE (\$)',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            initialValue: _selectedBuyInMethod,
            dropdownColor: AppColors.surfaceLight,
            decoration: const InputDecoration(
              labelText: 'APPLY BUY-IN STRATEGY',
              filled: true,
              fillColor: AppColors.surfaceLight,
            ),
            items: const [
              DropdownMenuItem(value: 'Simple Buy-in', child: Text('Simple Buy-in (Extrema SL/TP)')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedBuyInMethod = val);
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _riskCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'RISK %',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ratioCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'SL/TP RATIO',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxPosCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'MAX POS',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
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
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isBacktesting ? null : _executeBacktest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('RUN HISTORICAL BACKTEST', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMetricsGrid() {
    final report = _backtestReport!;
    final double netProfit = (report['total_net_profit'] as num?)?.toDouble() ?? 0.0;
    final double netProfitPct = (report['total_net_profit_pct'] as num?)?.toDouble() ?? 0.0;
    final int totalTrades = (report['total_trades'] as num?)?.toInt() ?? 0;
    final int winning = (report['winning_trades'] as num?)?.toInt() ?? 0;
    final int losing = (report['losing_trades'] as num?)?.toInt() ?? 0;
    final double winRate = (report['win_rate'] as num?)?.toDouble() ?? 0.0;
    final double profitFactor = (report['profit_factor'] as num?)?.toDouble() ?? 0.0;
    final double maxDdAmount = (report['max_drawdown_amount'] as num?)?.toDouble() ?? 0.0;
    final double maxDdPct = (report['max_drawdown_pct'] as num?)?.toDouble() ?? 0.0;

    final bool isProfit = netProfit >= 0;
    final Color profitColor = isProfit ? AppColors.green : AppColors.red;
    final String profitSign = isProfit ? '+' : '';

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildKpiCard(
          title: 'NET PROFIT',
          value: '$profitSign\$${netProfit.toStringAsFixed(2)}',
          subtitle: '$profitSign${netProfitPct.toStringAsFixed(2)}% ($totalTrades Trades)',
          valueColor: profitColor,
        ),
        _buildKpiCard(
          title: 'WIN RATE',
          value: '${winRate.toStringAsFixed(1)}%',
          subtitle: '$winning Win / $losing Loss',
          valueColor: winRate >= 50.0 ? AppColors.green : AppColors.amber,
        ),
        _buildKpiCard(
          title: 'PROFIT FACTOR',
          value: profitFactor.toStringAsFixed(2),
          subtitle: 'Gross Profit / Loss',
          valueColor: profitFactor >= 1.2 ? AppColors.green : AppColors.amber,
        ),
        _buildKpiCard(
          title: 'MAX DRAWDOWN',
          value: '-\$${maxDdAmount.toStringAsFixed(2)}',
          subtitle: '-${maxDdPct.toStringAsFixed(2)}% Peak-to-Trough',
          valueColor: AppColors.red,
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: AppColors.mutedText, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(color: valueColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: AppColors.mutedText, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildEquityCurveChartCard() {
    final report = _backtestReport!;
    final List<dynamic> rawCurve = report['equity_curve'] ?? [];
    final List<double> points = rawCurve.map((e) => (e['equity'] as num).toDouble()).toList();

    if (points.length < 2) {
      points.clear();
      points.addAll([10000.0, 10000.0]);
    }

    final double netProfit = (report['total_net_profit'] as num?)?.toDouble() ?? 0.0;
    final Color chartColor = netProfit >= 0 ? AppColors.green : AppColors.red;

    return Container(
      width: double.infinity,
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
              const Text('SIMULATED EQUITY CURVE', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${points.length} Samples', style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: SparklinePainter(
                data: points,
                lineColor: chartColor,
                showGradient: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatedTradesListCard() {
    final report = _backtestReport!;
    final List<dynamic> trades = report['trades'] ?? [];

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
              Text('ITEMIZED TRADES (${trades.length}) • TAP TO VIEW CHART', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          if (trades.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text('No trades generated in this date range.', style: TextStyle(color: AppColors.mutedText, fontSize: 12)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trades.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final trade = trades[index] as Map<String, dynamic>;
                final String type = trade['type'] ?? 'BUY';
                final bool isBuy = type == 'BUY';
                final double profit = (trade['profit'] as num?)?.toDouble() ?? 0.0;
                final bool isProfit = profit >= 0;
                final Color profitColor = isProfit ? AppColors.green : AppColors.red;

                return InkWell(
                  onTap: () => _showTradeChartModal(trade),
                  borderRadius: BorderRadius.circular(10.0),
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10.0),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isBuy ? AppColors.green : AppColors.red).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    type,
                                    style: TextStyle(
                                      color: isBuy ? AppColors.green : AppColors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('#${trade['trade_id']} • ${trade['volume']} Lots', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  '${isProfit ? "+" : ""}\$${profit.toStringAsFixed(2)}',
                                  style: TextStyle(color: profitColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.show_chart, color: AppColors.green, size: 16),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Entry: \$${trade['entry_price']} → Exit: \$${trade['exit_price']}', style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                trade['exit_reason'] ?? 'EXIT',
                                style: const TextStyle(color: AppColors.mutedText, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('In: ${trade['entry_time']}', style: AppTextStyles.monoMuted.copyWith(fontSize: 9)),
                            Text('Out: ${trade['exit_time']}', style: AppTextStyles.monoMuted.copyWith(fontSize: 9)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// MT5 CANDLESTICK & TRADINGVIEW POSITION TOOL OVERLAY PAINTER
// =============================================================================
class Mt5CandlestickPainter extends CustomPainter {
  final List<Map<String, dynamic>> candleSlice;
  final int entrySliceIndex;
  final int exitSliceIndex;
  final double entryPrice;
  final double exitPrice;
  final double slPrice;
  final double tpPrice;
  final String direction;

  Mt5CandlestickPainter({
    required this.candleSlice,
    required this.entrySliceIndex,
    required this.exitSliceIndex,
    required this.entryPrice,
    required this.exitPrice,
    required this.slPrice,
    required this.tpPrice,
    required this.direction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candleSlice.isEmpty) return;

    final double chartWidth = size.width - 55.0;
    final double chartHeight = size.height - 20.0;

    double minPrice = double.infinity;
    double maxPrice = -double.infinity;

    for (final candle in candleSlice) {
      final h = (candle['high'] as num).toDouble();
      final l = (candle['low'] as num).toDouble();
      if (h > maxPrice) maxPrice = h;
      if (l < minPrice) minPrice = l;
    }

    if (slPrice > 0) {
      if (slPrice > maxPrice) maxPrice = slPrice;
      if (slPrice < minPrice) minPrice = slPrice;
    }
    if (tpPrice > 0) {
      if (tpPrice > maxPrice) maxPrice = tpPrice;
      if (tpPrice < minPrice) minPrice = tpPrice;
    }

    final double priceRange = (maxPrice - minPrice) == 0 ? 1.0 : (maxPrice - minPrice);
    final double priceMargin = priceRange * 0.05;
    final double scaledMin = minPrice - priceMargin;
    final double scaledMax = maxPrice + priceMargin;
    final double scaledRange = scaledMax - scaledMin;

    double priceToY(double p) {
      return chartHeight - ((p - scaledMin) / scaledRange * chartHeight);
    }

    final int candleCount = candleSlice.length;
    final double candleWidth = chartWidth / candleCount;
    final double bodyWidth = max(2.0, candleWidth * 0.65);

    final Paint gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 0.5;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    const int gridRows = 4;
    for (int r = 0; r <= gridRows; r++) {
      final double y = (chartHeight / gridRows) * r;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);

      final double pVal = scaledMax - (scaledRange / gridRows) * r;
      textPainter.text = TextSpan(
        text: pVal.toStringAsFixed(4),
        style: const TextStyle(color: AppColors.mutedText, fontSize: 9, fontFamily: 'monospace'),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(chartWidth + 4, y - 6));
    }

    if (entrySliceIndex >= 0 && entrySliceIndex < candleCount) {
      final double xStart = entrySliceIndex * candleWidth + (candleWidth / 2);
      final int validExitIndex = min(exitSliceIndex, candleCount - 1);
      final double xEnd = validExitIndex * candleWidth + (candleWidth / 2);

      final double yEntry = priceToY(entryPrice);
      final double ySl = priceToY(slPrice);
      final double yTp = priceToY(tpPrice);

      final bool isBuy = direction == 'BUY';

      final Rect tpRect = isBuy
          ? Rect.fromLTRB(xStart, yTp, xEnd, yEntry)
          : Rect.fromLTRB(xStart, yEntry, xEnd, yTp);

      final Paint tpBoxPaint = Paint()
        ..color = AppColors.green.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      final Paint tpBorderPaint = Paint()
        ..color = AppColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(tpRect, tpBoxPaint);
      canvas.drawRect(tpRect, tpBorderPaint);

      final Rect slRect = isBuy
          ? Rect.fromLTRB(xStart, yEntry, xEnd, ySl)
          : Rect.fromLTRB(xStart, ySl, xEnd, yEntry);

      final Paint slBoxPaint = Paint()
        ..color = AppColors.red.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      final Paint slBorderPaint = Paint()
        ..color = AppColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(slRect, slBoxPaint);
      canvas.drawRect(slRect, slBorderPaint);

      _drawDashedLine(canvas, Offset(xStart, yEntry), Offset(chartWidth, yEntry), Colors.white, 2.0);
      _drawDashedLine(canvas, Offset(xStart, yTp), Offset(chartWidth, yTp), AppColors.green, 1.5);
      _drawDashedLine(canvas, Offset(xStart, ySl), Offset(chartWidth, ySl), AppColors.red, 1.5);

      _drawPriceBadge(canvas, chartWidth + 2, yEntry, 'ENTRY', Colors.white);
      _drawPriceBadge(canvas, chartWidth + 2, yTp, 'TP', AppColors.green);
      _drawPriceBadge(canvas, chartWidth + 2, ySl, 'SL', AppColors.red);
    }

    for (int i = 0; i < candleCount; i++) {
      final candle = candleSlice[i];
      final double o = (candle['open'] as num).toDouble();
      final double h = (candle['high'] as num).toDouble();
      final double l = (candle['low'] as num).toDouble();
      final double c = (candle['close'] as num).toDouble();

      final double xCenter = i * candleWidth + (candleWidth / 2);
      final double xLeft = xCenter - (bodyWidth / 2);

      final double yO = priceToY(o);
      final double yH = priceToY(h);
      final double yL = priceToY(l);
      final double yC = priceToY(c);

      final bool isBullish = c >= o;
      final Color wickColor = isBullish ? AppColors.green : AppColors.red;
      final Color bodyColor = isBullish ? Colors.white : AppColors.background;
      final Color bodyBorderColor = isBullish ? AppColors.green : AppColors.red;

      final Paint wickPaint = Paint()
        ..color = wickColor
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(xCenter, yH), Offset(xCenter, yL), wickPaint);

      final double topY = min(yO, yC);
      final double botY = max(yO, yC);
      final double heightY = max(1.0, botY - topY);

      final Rect bodyRect = Rect.fromLTWH(xLeft, topY, bodyWidth, heightY);

      final Paint fillPaint = Paint()..color = bodyColor;
      final Paint borderPaint = Paint()
        ..color = bodyBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(bodyRect, fillPaint);
      canvas.drawRect(bodyRect, borderPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Color color, double strokeWidth) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const double dashWidth = 4.0;
    const double dashSpace = 3.0;

    double startX = p1.dx;
    while (startX < p2.dx) {
      canvas.drawLine(
        Offset(startX, p1.dy),
        Offset(min(startX + dashWidth, p2.dx), p1.dy),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  void _drawPriceBadge(Canvas canvas, double x, double y, String text, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    final Rect bgRect = Rect.fromLTWH(x, y - 6, tp.width + 6, 12);
    final Paint bgPaint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(2)), bgPaint);
    tp.paint(canvas, Offset(x + 3, y - 5));
  }

  @override
  bool shouldRepaint(covariant Mt5CandlestickPainter oldDelegate) {
    return oldDelegate.candleSlice != candleSlice ||
        oldDelegate.entrySliceIndex != entrySliceIndex ||
        oldDelegate.exitSliceIndex != exitSliceIndex ||
        oldDelegate.slPrice != slPrice ||
        oldDelegate.tpPrice != tpPrice;
  }
}
