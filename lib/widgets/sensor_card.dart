import 'package:flutter/material.dart';

import '../models/sensor_models.dart';
import '../theme/app_theme.dart';

/// One sensor channel: header with achieved sample rate, then rows of values.
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.unit,
    required this.accent,
    required this.children,
    this.rate,
    this.unavailableReason,
    this.footer,
  });

  final String title;
  final String unit;
  final Color accent;
  final List<Widget> children;
  final ChannelRate? rate;
  final String? unavailableReason;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final missing = unavailableReason != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: missing ? AppColors.textMuted : accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                unit,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              if (rate != null) ...[
                const SizedBox(width: 8),
                _RateBadge(rate: rate!),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (missing)
            Text(
              'Not available on this device\n$unavailableReason',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            )
          else
            ...children,
          if (footer != null && !missing) ...[
            const SizedBox(height: 10),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// Achieved delivery rate. Amber when the stream has stalled — a sensor that
/// stopped reporting looks identical to a stationary one in the numbers alone.
class _RateBadge extends StatelessWidget {
  const _RateBadge({required this.rate});

  final ChannelRate rate;

  @override
  Widget build(BuildContext context) {
    final stalled = rate.isStalled;
    final color = !rate.hasData
        ? AppColors.textMuted
        : stalled
        ? AppColors.warn
        : AppColors.ok;
    final label = !rate.hasData
        ? 'waiting'
        : stalled
        ? 'stalled'
        : '${rate.hz.toStringAsFixed(0)} Hz';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: AppTheme.numeric.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A labelled value row. [emphasis] promotes the figure to the larger size
/// used for the numbers an operator reads while the vehicle is moving.
class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: emphasis ? 12 : 11.5,
              ),
            ),
          ),
          Text(
            value,
            style: AppTheme.numeric.copyWith(
              color: color ?? AppColors.textPrimary,
              fontSize: emphasis ? 17 : 13,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three axes on one line. Axis order is fixed and labelled — an unlabelled
/// triple is unreadable the moment the device is not flat on a table.
class AxisRow extends StatelessWidget {
  const AxisRow({super.key, required this.vector, required this.accent, this.decimals = 3});

  final Vector3 vector;
  final Color accent;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Axis(label: 'X', value: vector.x, accent: accent, decimals: decimals),
        _Axis(label: 'Y', value: vector.y, accent: accent, decimals: decimals),
        _Axis(label: 'Z', value: vector.z, accent: accent, decimals: decimals),
      ],
    );
  }
}

class _Axis extends StatelessWidget {
  const _Axis({
    required this.label,
    required this.value,
    required this.accent,
    required this.decimals,
  });

  final String label;
  final double value;
  final Color accent;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.toStringAsFixed(decimals),
                style: AppTheme.numeric.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
