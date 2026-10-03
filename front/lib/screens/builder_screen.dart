import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../main.dart' show AppColors;

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

class AlgorithmBuilderScreen extends StatefulWidget {
  final Map<String, dynamic>? existingConfig;

  const AlgorithmBuilderScreen({super.key, this.existingConfig});

  @override
  State<AlgorithmBuilderScreen> createState() => _AlgorithmBuilderScreenState();
}

class _AlgorithmBuilderScreenState extends State<AlgorithmBuilderScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _thresholdCtrl;
  late TextEditingController _riskCtrl;
  late TextEditingController _ratioCtrl;
  late TextEditingController _maxPosCtrl;
  late TextEditingController _indicatorSearchCtrl;

  String _selectedOperator = 'WEIGHTED';
  String _selectedBuyInMethod = 'Simple Buy-in';
  String _indicatorSearchQuery = '';

  final List<String> _timeframeOptions = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'];

  // Indicator Catalog Library for Search & Selection
  final List<Map<String, String>> _availableIndicatorsCatalog = [
    {'id': 'rsi', 'name': 'RSI Indicator (Normalized)', 'category': 'Oscillators'},
    {'id': 'macd', 'name': 'MACD Z-Score (Squashed)', 'category': 'Momentum'},
    {'id': 'bollinger', 'name': 'Bollinger Bands Deviation', 'category': 'Volatility'},
    {'id': 'stochastic', 'name': 'Stochastic Oscillator', 'category': 'Oscillators'},
  ];

  List<ConfiguredIndicatorItem> _selectedIndicators = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final isEditing = widget.existingConfig != null;
    final cfg = widget.existingConfig ?? {};

    _nameCtrl = TextEditingController(
      text: isEditing ? cfg['name'] : 'Strategy ${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
    );
    _thresholdCtrl = TextEditingController(
      text: isEditing ? (cfg['signal_threshold'] ?? 0.5).toString() : '0.5',
    );

    final double initRisk = isEditing ? ((cfg['risk_percentage'] as num?)?.toDouble() ?? 1.0) : 1.0;
    final double initRatio = isEditing ? ((cfg['sl_tp_ratio'] as num?)?.toDouble() ?? 2.0) : 2.0;
    final int initMaxPos = isEditing ? ((cfg['max_active_positions'] as num?)?.toInt() ?? 1) : 1;

    _riskCtrl = TextEditingController(text: initRisk.toStringAsFixed(1));
    _ratioCtrl = TextEditingController(text: initRatio.toStringAsFixed(1));
    _maxPosCtrl = TextEditingController(text: initMaxPos.toString());
    _indicatorSearchCtrl = TextEditingController();

    if (isEditing) {
      _selectedOperator = cfg['operator'] ?? 'WEIGHTED';
      _selectedBuyInMethod = cfg['buy_in_method'] ?? cfg['buyInMethod'] ?? 'Simple Buy-in';

      final configJson = (cfg['config_json'] as Map<String, dynamic>?) ?? {};
      final List<dynamic> savedIndicators = configJson['indicators'] ?? [];
      for (final item in savedIndicators) {
        if (item is Map<String, dynamic>) {
          _selectedIndicators.add(ConfiguredIndicatorItem.fromJson(item));
        }
      }
    }

    if (_selectedIndicators.isEmpty) {
      _selectedIndicators = [
        ConfiguredIndicatorItem(id: 'rsi', name: 'RSI Indicator', timeframe: 'M5', params: {'period': 14}, weight: 0.40),
        ConfiguredIndicatorItem(id: 'macd', name: 'MACD Z-Score', timeframe: 'M5', params: {'fast': 12, 'slow': 26, 'signal': 9, 'z_window': 100}, weight: 0.60),
      ];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _thresholdCtrl.dispose();
    _riskCtrl.dispose();
    _ratioCtrl.dispose();
    _maxPosCtrl.dispose();
    _indicatorSearchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _getDefaultParamsForIndicator(String id) {
    switch (id) {
      case 'rsi':
        return {'period': 14};
      case 'stochastic':
        return {'k_period': 14, 'd_period': 3};
      case 'macd':
        return {'fast': 12, 'slow': 26, 'signal': 9, 'z_window': 100};
      case 'bollinger':
        return {'period': 20, 'std_dev': 2.0};
      default:
        return {};
    }
  }

  Future<void> _persistStrategy() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an algorithm name')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final threshold = double.tryParse(_thresholdCtrl.text) ?? 0.5;
    final risk = double.tryParse(_riskCtrl.text) ?? 1.0;
    final ratio = double.tryParse(_ratioCtrl.text) ?? 2.0;
    final maxPos = int.tryParse(_maxPosCtrl.text) ?? 1;

    final serializedIndicators = _selectedIndicators.map((e) => e.toJson()).toList();

    final success = await ApiService.createStrategyConfig(
      name: name,
      symbol: 'EURUSD',
      timeframe: 5,
      riskPercentage: risk,
      slTpRatio: ratio,
      maxActivePositions: maxPos,
      operator: _selectedOperator,
      signalThreshold: threshold,
      configJson: {
        'indicators': serializedIndicators,
        'operator': _selectedOperator,
        'threshold': threshold,
        'signal_threshold': threshold,
        'buyInMethod': _selectedBuyInMethod,
        'buy_in_method': _selectedBuyInMethod,
        'risk_percentage': risk,
        'sl_tp_ratio': ratio,
        'max_active_positions': maxPos,
      },
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Algorithm "$name" Persisted Successfully!')),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save algorithm config')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.existingConfig != null;
    final double totalWeight = _selectedIndicators.fold(0.0, (sum, ind) => sum + ind.weight);

    final filteredCatalog = _availableIndicatorsCatalog.where((ind) {
      if (_indicatorSearchQuery.isEmpty) return true;
      final q = _indicatorSearchQuery.toLowerCase();
      final name = ind['name']!.toLowerCase();
      final cat = ind['category']!.toLowerCase();
      final id = ind['id']!.toLowerCase();
      return name.contains(q) || cat.contains(q) || id.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'EDIT ALGORITHM' : 'BUILD ASSET-AGNOSTIC ALGORITHM',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: AppColors.green),
            onPressed: _isSaving ? null : _persistStrategy,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. General Strategy Identification Card
            _buildGeneralSettingsCard(),
            const SizedBox(height: 16),

            // 2. Dynamic Buy-In Method Settings Card
            _buildBuyInSettingsCard(),
            const SizedBox(height: 16),

            // 3. Search & Append Indicators Section
            _buildSearchAndAddIndicatorsSection(filteredCatalog),
            const SizedBox(height: 16),

            // 4. Included Indicators List & Pipeline Weights
            _buildIncludedIndicatorsSection(totalWeight),
            const SizedBox(height: 24),

            // 5. Persist Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isSaving ? null : _persistStrategy,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                    : const Icon(Icons.save),
                label: Text(
                  _isSaving ? 'SAVING TO DATABASE...' : 'PERSIST ALGORITHM TO DATABASE',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettingsCard() {
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
              Icon(Icons.memory, color: AppColors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'STRATEGY PIPELINE IDENTIFICATION',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'ALGORITHM NAME',
              filled: true,
              fillColor: AppColors.surfaceLight,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedOperator,
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
                    DropdownMenuItem(value: 'XOR', child: Text('XOR (Conflict Gate)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedOperator = val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _thresholdCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'SIGNAL THRESHOLD (n)',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBuyInSettingsCard() {
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
              Icon(Icons.calculate, color: AppColors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'BUY-IN METHOD & EXECUTION MODEL',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            initialValue: _selectedBuyInMethod,
            isExpanded: true,
            dropdownColor: AppColors.surfaceLight,
            decoration: const InputDecoration(
              labelText: 'ASSIGN BUY-IN METHOD',
              filled: true,
              fillColor: AppColors.surfaceLight,
            ),
            items: const [
              DropdownMenuItem(value: 'Simple Buy-in', child: Text('Simple Buy-in (Dynamic Extrema SL & Risk Sizing)')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedBuyInMethod = val);
            },
          ),
          const SizedBox(height: 12),

          // Dynamic Buy-In Parameters Inline Card
          if (_selectedBuyInMethod == 'Simple Buy-in')
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SIMPLE BUY-IN PARAMETERS',
                    style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _riskCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'RISK PERCENTAGE (%)',
                            filled: true,
                            fillColor: AppColors.surface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ratioCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'SL / TP RATIO',
                            filled: true,
                            fillColor: AppColors.surface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _maxPosCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'MAX POSITIONS CAP',
                            filled: true,
                            fillColor: AppColors.surface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchAndAddIndicatorsSection(List<Map<String, String>> filteredCatalog) {
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
              Icon(Icons.search, color: AppColors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'SEARCH & APPEND INDICATORS',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _indicatorSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Search indicator by name or category (e.g., RSI, MACD)...',
              hintStyle: const TextStyle(color: AppColors.mutedText, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: AppColors.mutedText, size: 18),
              suffixIcon: _indicatorSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.mutedText, size: 18),
                      onPressed: () {
                        setState(() {
                          _indicatorSearchCtrl.clear();
                          _indicatorSearchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onChanged: (val) {
              setState(() {
                _indicatorSearchQuery = val.trim();
              });
            },
          ),
          const SizedBox(height: 12),

          if (filteredCatalog.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: Text('No indicators matching your search query.', style: TextStyle(color: AppColors.mutedText, fontSize: 12)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredCatalog.map((ind) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedIndicators.add(
                        ConfiguredIndicatorItem(
                          id: ind['id']!,
                          name: ind['name']!,
                          timeframe: 'M5',
                          params: _getDefaultParamsForIndicator(ind['id']!),
                          weight: 0.30,
                        ),
                      );
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Appended ${ind['name']} to pipeline!'), duration: const Duration(seconds: 1)),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_circle_outline, color: AppColors.green, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          ind['name']!,
                          style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildIncludedIndicatorsSection(double totalWeight) {
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
              Text(
                'PIPELINE INDICATORS (${_selectedIndicators.length})',
                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ((totalWeight - 1.0).abs() < 0.05 ? AppColors.green : AppColors.amber).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Total Weight: ${totalWeight.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: (totalWeight - 1.0).abs() < 0.05 ? AppColors.green : AppColors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          ..._selectedIndicators.asMap().entries.map((entry) {
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
                          if (_selectedIndicators.length > 1) {
                            setState(() {
                              _selectedIndicators.removeAt(idx);
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
                            if (val != null) setState(() => ind.timeframe = val);
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
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Indicator-specific parameters
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
                            decoration: const InputDecoration(labelText: 'K PERIOD', filled: true, fillColor: AppColors.surface),
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
                            decoration: const InputDecoration(labelText: 'D PERIOD', filled: true, fillColor: AppColors.surface),
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
        ],
      ),
    );
  }
}
