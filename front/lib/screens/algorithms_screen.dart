import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_styles.dart';
import '../services/api_service.dart';
import '../widgets/sparkline_chart.dart';
import 'backtest_screen.dart';
import 'builder_screen.dart';

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

class _AlgorithmsViewState extends State<AlgorithmsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _timeframeOptions = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'];

  double _simpleBuyInRisk = 1.0;
  double _simpleBuyInRatio = 2.0;
  int _simpleBuyInMaxPositions = 1;

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

  final Map<String, double> _indicatorValues = {};
  final Map<String, String> _indicatorBiases = {};
  final Map<String, List<double>> _indicatorSeries = {};

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
              child: SingleChildScrollView(
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
                            riskPercentage: (config['risk_percentage'] as num?)?.toDouble() ?? _simpleBuyInRisk,
                            slTpRatio: (config['sl_tp_ratio'] as num?)?.toDouble() ?? _simpleBuyInRatio,
                            operator: config['operator'] ?? 'WEIGHTED',
                            signalThreshold: (config['signal_threshold'] as num?)?.toDouble() ?? 0.5,
                            maxActivePositions: (config['max_active_positions'] as num?)?.toInt() ?? _simpleBuyInMaxPositions,
                            indicators: payloadIndicators,
                          );

                          if (context.mounted) {
                            widget.onStartInstance();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Worker started on $finalSymbol (M$tfMinutes)!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('START BACKGROUND WORKER', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _navigateToAlgorithmBuilderScreen({Map<String, dynamic>? existingConfig}) async {
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => AlgorithmBuilderScreen(existingConfig: existingConfig),
      ),
    );

    if (refreshed == true) {
      widget.onRefreshConfigs();
    }
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
              Tab(text: 'Algorithms'),
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
                'YOUR ALGORITHMS',
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
                onPressed: () => _navigateToAlgorithmBuilderScreen(),
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
      onTap: () => _navigateToAlgorithmBuilderScreen(existingConfig: config),
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
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Signal Bias: $bias', style: TextStyle(color: scoreColor, fontSize: 11, fontWeight: FontWeight.bold)),
                Text('Score: ${score.toStringAsFixed(4)}', style: AppTextStyles.monoMuted.copyWith(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 12),

            // Real-Time Signal Score Chart
            SizedBox(
              height: 40,
              width: double.infinity,
              child: CustomPaint(
                painter: SparklinePainter(
                  data: series,
                  lineColor: scoreColor,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action Buttons Bar
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _openSymbolSelectionModal(config),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Deploy Worker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.green,
                      side: const BorderSide(color: AppColors.green),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => BacktestScreen(algorithmConfig: config),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history_toggle_off, size: 16),
                    label: const Text('BACKTEST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorsSection() {
    final List<Map<String, dynamic>> catalog = [
      {'id': 'rsi', 'title': 'RSI Indicator (Normalized)', 'desc': 'Wilder\'s Relative Strength Index squashed to [-1.0, 1.0].', 'color': AppColors.blue},
      {'id': 'macd', 'title': 'MACD Z-Score (Squashed)', 'desc': 'Moving Average Convergence Divergence normalized via rolling Z-score.', 'color': AppColors.amber},
      {'id': 'bollinger', 'title': 'Bollinger Bands Deviation', 'desc': '%B percentile position normalized across standard deviation envelopes.', 'color': AppColors.green},
      {'id': 'stochastic', 'title': 'Stochastic Oscillator', 'desc': '%K and %D momentum oscillator scaled to [-1.0, 1.0].', 'color': AppColors.red},
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AVAILABLE TECHNICAL INDICATORS',
            style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: catalog.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = catalog[index];
              final id = item['id'] as String;
              final tf = _indicatorTimeframes[id] ?? 'M5';
              final val = _indicatorValues[id] ?? 0.0;
              final series = _indicatorSeries[id] ?? [0.0, 0.1, 0.2, 0.1, 0.3];

              final bool isBullish = val > 0.2;
              final bool isBearish = val < -0.2;
              final Color scoreColor = isBullish ? AppColors.green : (isBearish ? AppColors.red : AppColors.amber);

              return Container(
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
                              Text(item['title']!, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(item['desc']!, style: const TextStyle(color: AppColors.mutedText, fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.tune, color: AppColors.green, size: 20),
                          onPressed: () => _openIndicatorConfigModal(id, item['title']!),
                          tooltip: 'Configure Parameters',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Timeframe: $tf', style: AppTextStyles.mono.copyWith(fontSize: 11)),
                        Text('Signal Output: ${val >= 0 ? "+" : ""}${val.toStringAsFixed(4)}', style: TextStyle(color: scoreColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 35,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: SparklinePainter(
                          data: series,
                          lineColor: scoreColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: _evaluating ? null : () => _testIndicator(id),
                        icon: const Icon(Icons.analytics, size: 14),
                        label: const Text('EVALUATE SIGNAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBuyInMethodsSection() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BUY-IN STRATEGY EXECUTORS',
            style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),

          Container(
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
                  children: const [
                    Text('Simple Buy-in (Extrema SL & Risk Sizing)', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Icon(Icons.check_circle, color: AppColors.green, size: 20),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Dynamically calculates Stop Loss from local swing extrema (minimum low for BUY, maximum high for SELL) and projects Take Profit via sl_tp_ratio.',
                  style: TextStyle(color: AppColors.mutedText, fontSize: 11),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _simpleBuyInRisk.toStringAsFixed(1)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'RISK %', filled: true, fillColor: AppColors.surfaceLight),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed > 0) _simpleBuyInRisk = parsed;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _simpleBuyInRatio.toStringAsFixed(1)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'SL/TP RATIO', filled: true, fillColor: AppColors.surfaceLight),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed > 0) _simpleBuyInRatio = parsed;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _simpleBuyInMaxPositions.toString()),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'MAX POS', filled: true, fillColor: AppColors.surfaceLight),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed >= 1) _simpleBuyInMaxPositions = parsed;
                        },
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Simple Buy-in defaults saved (Risk: $_simpleBuyInRisk%, Ratio: 1:$_simpleBuyInRatio)!')),
                      );
                    },
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('SAVE BUY-IN DEFAULTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
