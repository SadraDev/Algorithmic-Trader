import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_styles.dart';

class WorkerCardWidget extends StatelessWidget {
  final Map<String, dynamic> instance;
  final VoidCallback onPause;
  final VoidCallback onStop;

  const WorkerCardWidget({
    super.key,
    required this.instance,
    required this.onPause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final String instanceId = instance['instance_id'] ?? 'N/A';
    final String name = instance['name'] ?? 'Worker Instance';
    final String symbol = instance['symbol'] ?? 'EURUSD';
    final int timeframe = (instance['timeframe'] as num?)?.toInt() ?? 5;
    final double latestScore = (instance['latest_score'] as num?)?.toDouble() ?? 0.0;
    final double risk = (instance['risk_percentage'] as num?)?.toDouble() ?? 1.0;
    final double ratio = (instance['sl_tp_ratio'] as num?)?.toDouble() ?? 2.0;

    final bool isBullish = latestScore > 0.2;
    final bool isBearish = latestScore < -0.2;
    final Color scoreColor = isBullish ? AppColors.green : (isBearish ? AppColors.red : AppColors.amber);

    final double normalizedPointerX = ((latestScore.clamp(-1.0, 1.0) + 1.0) / 2.0);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: AppColors.border, width: 1.0),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '$symbol • M$timeframe',
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Worker ID: #$instanceId • Risk: ${risk.toStringAsFixed(1)}% • Ratio: 1:${ratio.toStringAsFixed(1)}',
                      style: AppTextStyles.monoMuted.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.pause_circle_outline, color: AppColors.amber, size: 22),
                    tooltip: 'Pause Instance',
                    onPressed: onPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, color: AppColors.red, size: 22),
                    tooltip: 'Stop Instance',
                    onPressed: onStop,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('LIVE SIGNAL COMPOSITE SCORE', style: TextStyle(color: AppColors.mutedText, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(
                '${latestScore >= 0 ? "+" : ""}${latestScore.toStringAsFixed(4)}',
                style: TextStyle(color: scoreColor, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Signal Gauge Visualizer
          LayoutBuilder(
            builder: (ctx, constraints) {
              final double gaugeWidth = constraints.maxWidth;
              final double pointerX = (normalizedPointerX * gaugeWidth).clamp(0.0, gaugeWidth);

              return Column(
                children: [
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 6,
                        width: gaugeWidth,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: const LinearGradient(
                            colors: [AppColors.red, AppColors.amber, AppColors.green],
                          ),
                        ),
                      ),
                      Positioned(
                        left: pointerX - 5,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: scoreColor.withValues(alpha: 0.8),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('-1.0 (SHORT)', style: TextStyle(color: AppColors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text('0.0 (NEUTRAL)', style: TextStyle(color: AppColors.mutedText, fontSize: 9)),
                      Text('+1.0 (LONG)', style: TextStyle(color: AppColors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
