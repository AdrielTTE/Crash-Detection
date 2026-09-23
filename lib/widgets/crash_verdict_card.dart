import 'package:flutter/material.dart';

import '../services/crash_detector.dart';
import '../theme/app_theme.dart';
import 'explain_scope.dart';

/// The detector's live answer: crash, or not, and why.
///
/// The verdict alone would be nearly useless while the thresholds are still
/// being tuned. What makes this usable is the condition checklist underneath
/// — every test the detector applied, its measured value against its
/// threshold, and whether it passed. When the verdict is wrong, the row that
/// was wrong is visible immediately, which is the number to change.
class CrashVerdictCard extends StatelessWidget {
  const CrashVerdictCard({
    super.key,
    required this.assessment,
    required this.thresholds,
  });

  final CrashAssessment assessment;
  final CrashThresholds thresholds;

  Color get _color => switch (assessment.verdict) {
    CrashVerdict.crash => AppColors.danger,
    CrashVerdict.possible => AppColors.warn,
    CrashVerdict.monitoring => AppColors.accel,
    CrashVerdict.rejected => AppColors.ok,
    CrashVerdict.noEvent => AppColors.textMuted,
  };

  IconData get _icon => switch (assessment.verdict) {
    CrashVerdict.crash => Icons.crisis_alert,
    CrashVerdict.possible => Icons.help_outline,
    CrashVerdict.monitoring => Icons.radar,
    CrashVerdict.rejected => Icons.shield_outlined,
    CrashVerdict.noEvent => Icons.visibility_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final explain = ExplainScope.of(context);
    final color = _color;
    final isAlert = assessment.verdict == CrashVerdict.crash;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isAlert ? 0.9 : 0.45),
          width: isAlert ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 20, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  assessment.verdict.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (assessment.verdict != CrashVerdict.noEvent &&
                  assessment.verdict != CrashVerdict.monitoring)
                _ScorePill(score: assessment.score, color: color),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            assessment.summary,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          if (assessment.conditions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'WHY',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 7),
            for (final condition in assessment.conditions)
              _ConditionRow(condition: condition),
          ],
          if (explain) ...[
            const SizedBox(height: 12),
            _ExplainBlock(thresholds: thresholds),
          ],
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, required this.color});

  final double score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${score.toStringAsFixed(0)}/100',
        style: AppTheme.numeric.copyWith(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One test, its measurement, and its outcome.
///
/// Three outcomes, not two. A condition whose inputs were missing — no GPS
/// fix, no barometer — is drawn as unknown rather than as failed, because
/// treating "could not tell" as "did not happen" is how a detector quietly
/// rejects a real crash in a tunnel.
class _ConditionRow extends StatelessWidget {
  const _ConditionRow({required this.condition});

  final CrashCondition condition;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = condition.unknown
        ? (Icons.remove_circle_outline, AppColors.textMuted)
        : condition.met
        ? (Icons.check_circle, AppColors.ok)
        : (Icons.cancel_outlined, AppColors.textMuted);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        condition.label,
                        style: TextStyle(
                          color: condition.met
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 11.5,
                          fontWeight: condition.met
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (condition.isGate) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'GATE',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  condition.detail,
                  style: AppTheme.numeric.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (!condition.isGate && condition.met)
            Text(
              '+${condition.weight.toStringAsFixed(0)}',
              style: AppTheme.numeric.copyWith(
                color: AppColors.ok,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _ExplainBlock extends StatelessWidget {
  const _ExplainBlock({required this.thresholds});

  final CrashThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final t = thresholds;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOW THE DECISION IS MADE',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '1. A spike above ${t.impactG.toStringAsFixed(1)} g opens an '
            'evidence window of ${t.eventWindow.inMilliseconds} ms. Crossing '
            'that alone is not a crash — a pothole clears it easily.\n\n'
            '2. Everything in that window is collected before judging. '
            'Corroborating signals arrive after the first spike, not with it.\n\n'
            '3. GATE rows can veto outright, whatever the score. Free-fall '
            'before the spike means a dropped phone. Under '
            '${t.minPreImpactSpeedKmh.toStringAsFixed(0)} km/h beforehand '
            'means there was no collision to have.\n\n'
            '4. The rest are scored and summed. '
            '≥ ${t.crashScore.toStringAsFixed(0)} is a crash, '
            '≥ ${t.possibleScore.toStringAsFixed(0)} is possible.\n\n'
            'A failed gate beats any score. The asymmetry is deliberate: a '
            'false positive means calling emergency services to a pothole.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warn.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '⚠ These thresholds are placeholders, not calibrated values. '
              'They have never been fitted to this phone or to a real drive. '
              'Measure normal driving first — your own peaks are the floor '
              'any threshold has to clear.',
              style: TextStyle(
                color: AppColors.warn,
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent verdicts. During a calibration drive the log is the point: you do a
/// run, then read back what the detector called and compare it with what
/// actually happened.
class CrashEventLog extends StatelessWidget {
  const CrashEventLog({super.key, required this.events});

  final List<CrashAssessment> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 7),
              Text(
                'EVENT LOG — ${events.length}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final event in events.take(8)) _EventRow(event: event),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CrashAssessment event;

  @override
  Widget build(BuildContext context) {
    final color = switch (event.verdict) {
      CrashVerdict.crash => AppColors.danger,
      CrashVerdict.possible => AppColors.warn,
      _ => AppColors.textMuted,
    };
    final at = event.at;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              at == null
                  ? '—'
                  : at.toLocal().toIso8601String().substring(11, 19),
              style: AppTheme.numeric.copyWith(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              event.verdict.label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${event.peakG.toStringAsFixed(1)} g · ${event.score.toStringAsFixed(0)}',
            style: AppTheme.numeric.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
