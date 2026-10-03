import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_styles.dart';
import '../widgets/sparkline_chart.dart';
import '../widgets/worker_card.dart';

class DashboardScreen extends StatelessWidget {
  final bool isMt5Connected;
  final int loginAccount;
  final String serverName;
  final double accountBalance;
  final double accountEquity;
  final double accountProfit;
  final double accountFreeMargin;
  final int accountLeverage;
  final String currency;
  final List<Map<String, dynamic>> activeInstances;
  final List<Map<String, dynamic>> historyDeals;
  final VoidCallback onRefresh;
  final Function(String) onPauseInstance;
  final Function(String) onStopInstance;

  const DashboardScreen({
    super.key,
    required this.isMt5Connected,
    required this.loginAccount,
    required this.serverName,
    required this.accountBalance,
    required this.accountEquity,
    required this.accountProfit,
    required this.accountFreeMargin,
    required this.accountLeverage,
    required this.currency,
    required this.activeInstances,
    required this.historyDeals,
    required this.onRefresh,
    required this.onPauseInstance,
    required this.onStopInstance,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMt5Connected) ...[
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
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioCard() {
    // Filter out initial balance deposits / non-trade deals
    final tradingDeals = historyDeals.where((deal) {
      final typeStr = (deal['type'] ?? '').toString().toUpperCase();
      final commentStr = (deal['comment'] ?? '').toString().toLowerCase();
      if (typeStr.contains('DEPOSIT') || typeStr.contains('BALANCE')) return false;
      if (commentStr.contains('deposit') || commentStr.contains('balance')) return false;
      return true;
    }).toList();

    final List<double> equityPoints = [];
    double totalRealizedPnl = 0.0;

    if (tradingDeals.isNotEmpty) {
      final sortedDeals = List<Map<String, dynamic>>.from(tradingDeals.reversed);
      totalRealizedPnl = sortedDeals.fold(0.0, (sum, d) => sum + ((d['profit'] as num?)?.toDouble() ?? 0.0));

      double cumulativeBalance = accountBalance - totalRealizedPnl;
      equityPoints.add(cumulativeBalance);

      for (final deal in sortedDeals) {
        final pnl = (deal['profit'] as num?)?.toDouble() ?? 0.0;
        cumulativeBalance += pnl;
        equityPoints.add(cumulativeBalance);
      }
    }

    if (equityPoints.length < 2) {
      equityPoints.clear();
      equityPoints.addAll([accountBalance * 0.98, accountBalance * 0.99, accountBalance]);
    }

    final bool isRealizedProfitPositive = totalRealizedPnl >= 0;
    final String pnlSign = isRealizedProfitPositive ? '+' : '';
    final Color pnlColor = isRealizedProfitPositive ? AppColors.green : AppColors.red;

    final bool isOpenProfitPositive = accountProfit >= 0;
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
                isMt5Connected ? 'MT5 ACCOUNT #$loginAccount' : 'REAL MT5 TERMINAL',
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
                  color: (isMt5Connected ? AppColors.green : AppColors.amber).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isMt5Connected ? AppColors.green : AppColors.amber).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isMt5Connected ? AppColors.green : AppColors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMt5Connected ? 'CONNECTED' : 'OFFLINE',
                      style: TextStyle(
                        color: isMt5Connected ? AppColors.green : AppColors.amber,
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
                        '\$${accountBalance.toStringAsFixed(2)} $currency',
                        style: AppTextStyles.mono.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          '30D PnL: ',
                          style: TextStyle(color: AppColors.mutedText, fontSize: 11),
                        ),
                        Text(
                          '$pnlSign\$${totalRealizedPnl.toStringAsFixed(2)}',
                          style: TextStyle(color: pnlColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Small Compact Sparkline Chart inline with Equity Balance below CONNECTED badge
              SizedBox(
                width: 100,
                height: 36,
                child: SparklinePainterWidget(
                  data: equityPoints,
                  lineColor: pnlColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),

          // Account Parameters Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildAccountMetric('EQUITY', '\$${accountEquity.toStringAsFixed(2)}'),
              _buildAccountMetric('OPEN PnL', '$openProfitSign\$${accountProfit.toStringAsFixed(2)}', valueColor: openProfitColor),
              _buildAccountMetric('FREE MARGIN', '\$${accountFreeMargin.toStringAsFixed(2)}'),
              _buildAccountMetric('LEVERAGE', '1:$accountLeverage'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountMetric(String label, String value, {Color valueColor = AppColors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.mutedText, fontSize: 9, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveInstancesHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'ACTIVE ALGORITHM WORKERS',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${activeInstances.length}',
                style: const TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.mutedText, size: 20),
          onPressed: onRefresh,
        ),
      ],
    );
  }

  Widget _buildActiveInstancesList() {
    if (activeInstances.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: const [
            Icon(Icons.play_circle_outline, color: AppColors.mutedText, size: 40),
            SizedBox(height: 12),
            Text(
              'No Active Instances Running',
              style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Navigate to ALGORITHMS tab and tap "Deploy Worker" on any strategy to launch a background execution instance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedText, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: activeInstances.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final instance = activeInstances[index];
        final id = instance['instance_id'] ?? '0';

        return WorkerCardWidget(
          instance: instance,
          onPause: () => onPauseInstance(id),
          onStop: () => onStopInstance(id),
        );
      },
    );
  }
}

class SparklinePainterWidget extends StatelessWidget {
  final List<double> data;
  final Color lineColor;

  const SparklinePainterWidget({
    super.key,
    required this.data,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SparklinePainter(data: data, lineColor: lineColor),
    );
  }
}
