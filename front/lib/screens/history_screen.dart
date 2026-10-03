import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_styles.dart';

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
    // Exclude balance deposits / initial funding deals
    final filteredDeals = historyDeals.where((deal) {
      final typeStr = (deal['type'] ?? '').toString().toUpperCase();
      final commentStr = (deal['comment'] ?? '').toString().toLowerCase();
      if (typeStr.contains('DEPOSIT') || typeStr.contains('BALANCE')) return false;
      if (commentStr.contains('deposit') || commentStr.contains('balance')) return false;
      return true;
    }).toList();

    double totalPnl = 0.0;
    int winningTrades = 0;
    int losingTrades = 0;

    for (final deal in filteredDeals) {
      final pnl = (deal['profit'] as num?)?.toDouble() ?? 0.0;
      totalPnl += pnl;
      if (pnl > 0) winningTrades++;
      if (pnl < 0) losingTrades++;
    }

    final bool isPositive = totalPnl >= 0;
    final String pnlSign = isPositive ? '+' : '';
    final Color pnlColor = isPositive ? AppColors.green : AppColors.red;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('30-DAY MT5 TRADE HISTORY', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.mutedText, size: 20),
                      onPressed: onRefreshLogs,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TOTAL REALIZED PnL', style: TextStyle(color: AppColors.mutedText, fontSize: 10)),
                        const SizedBox(height: 2),
                        Text('$pnlSign\$${totalPnl.toStringAsFixed(2)}', style: TextStyle(color: pnlColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('RECORDED TRADES', style: TextStyle(color: AppColors.mutedText, fontSize: 10)),
                        const SizedBox(height: 2),
                        Text('${filteredDeals.length} Trades ($winningTrades Win / $losingTrades Loss)', style: AppTextStyles.mono.copyWith(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (filteredDeals.isEmpty)
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
                  Icon(Icons.history_toggle_off, color: AppColors.mutedText, size: 36),
                  SizedBox(height: 10),
                  Text('No MT5 Executed Trades Found', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredDeals.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final deal = filteredDeals[index];
                final String type = deal['type'] ?? 'BUY';
                final bool isBuy = type == 'BUY';
                final double profit = (deal['profit'] as num?)?.toDouble() ?? 0.0;
                final bool isProfit = profit >= 0;
                final Color profitColor = isProfit ? AppColors.green : AppColors.red;

                final double entryPrice = (deal['entry_price'] as num?)?.toDouble() ?? (deal['price'] as num?)?.toDouble() ?? 0.0;
                final double exitPrice = (deal['exit_price'] as num?)?.toDouble() ?? entryPrice;
                final bool hasExit = deal.containsKey('exit_price') && (deal['exit_price'] as num).toDouble() != entryPrice;

                final String priceText = hasExit
                    ? '${deal['volume']} Lots • \$${entryPrice.toStringAsFixed(5)} → \$${exitPrice.toStringAsFixed(5)}'
                    : 'Vol: ${deal['volume']} Lots @ \$${entryPrice.toStringAsFixed(5)}';

                return Container(
                  padding: const EdgeInsets.all(12.0),
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
                          Flexible(
                            child: Row(
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
                                Expanded(
                                  child: Text(
                                    '${deal['symbol']} • #${deal['ticket']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${isProfit ? "+" : ""}\$${profit.toStringAsFixed(2)}',
                            style: TextStyle(color: profitColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              priceText,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.monoMuted.copyWith(fontSize: 11),
                            ),
                          ),
                          Text(deal['time'] ?? '', style: AppTextStyles.monoMuted.copyWith(fontSize: 10)),
                        ],
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
}
