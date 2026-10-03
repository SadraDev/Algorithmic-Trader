import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const TextStyle headerTitle = TextStyle(
    color: AppColors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  static const TextStyle cardTitle = TextStyle(
    color: AppColors.white,
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle mono = TextStyle(
    color: AppColors.white,
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
  );

  static const TextStyle monoGreen = TextStyle(
    color: AppColors.green,
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
  );

  static const TextStyle monoRed = TextStyle(
    color: AppColors.red,
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
  );

  static const TextStyle monoMuted = TextStyle(
    color: AppColors.mutedText,
    fontFamily: 'monospace',
    fontSize: 11,
  );
}
