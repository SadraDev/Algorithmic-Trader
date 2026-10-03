import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class KpiCardWidget extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  const KpiCardWidget({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
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
          Text(
            title,
            style: const TextStyle(color: AppColors.mutedText, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.mutedText, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
