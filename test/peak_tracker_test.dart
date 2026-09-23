import 'package:crash_detection/models/sensor_models.dart';
import 'package:crash_detection/services/sensor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeakTracker', () {
    test('reports no data before the first sample', () {
      final t = PeakTracker();
      expect(t.hasData, isFalse);
      expect(t.max, isNull);
      expect(t.min, isNull);
      expect(t.range, isNull);
      expect(t.maxAt, isNull);
    });

    test('a single sample is both the high and the low', () {
      final t = PeakTracker()..record(1.0);
      expect(t.max, 1.0);
      expect(t.min, 1.0);
      expect(t.range, 0.0);
    });

    test('holds the extremes across a run', () {
      final t = PeakTracker();
      for (final v in [1.0, 4.2, 0.3, 2.0, -1.5, 3.9]) {
        t.record(v);
      }
      expect(t.max, 4.2);
      expect(t.min, -1.5);
      expect(t.range, closeTo(5.7, 1e-9));
    });

    test('tracks the low, which is what exposes free-fall', () {
      // Total g sits near 1 at rest and collapses toward 0 in free-fall. A
      // max-only tracker would record the landing spike and miss the fall
      // that identifies it as a dropped phone rather than a vehicle impact.
      final totalG = PeakTracker();
      for (final v in [1.00, 0.99, 0.04, 0.02, 14.7, 1.01]) {
        totalG.record(v);
      }
      expect(totalG.max, 14.7, reason: 'the landing spike');
      expect(totalG.min, 0.02, reason: 'the free-fall that precedes it');
    });

    test('keeps signed extremes rather than collapsing to magnitude', () {
      // A front and a rear impact drive the same axis in opposite directions.
      final axis = PeakTracker();
      for (final v in [0.0, -9.4, 0.2, 7.1]) {
        axis.record(v);
      }
      expect(axis.max, 7.1);
      expect(axis.min, -9.4);
    });

    test('a new low leaves the high and its timestamp untouched', () {
      final t = PeakTracker()..record(5.0);
      expect(t.maxAt, isNotNull);
      expect(t.minAt, isNotNull);

      final firstMaxAt = t.maxAt!;
      t.record(1.0);

      expect(t.max, 5.0);
      expect(t.maxAt, firstMaxAt);
      expect(t.min, 1.0);
      // Not asserted: that minAt differs from maxAt. On Windows successive
      // DateTime.now() calls routinely land in the same clock tick, so the
      // two can legitimately be identical. Ordering is the real invariant.
      expect(t.minAt!.isBefore(firstMaxAt), isFalse);
    });

    test('a new high moves only the high', () {
      final t = PeakTracker()
        ..record(2.0)
        ..record(-3.0);
      final lowAt = t.minAt!;

      t.record(9.0);

      expect(t.max, 9.0);
      expect(t.min, -3.0);
      expect(t.minAt, lowAt);
    });

    test('reset clears everything', () {
      final t = PeakTracker()
        ..record(3.0)
        ..record(-1.0);
      t.reset();
      expect(t.hasData, isFalse);
      expect(t.max, isNull);
      expect(t.min, isNull);
      expect(t.maxAt, isNull);
    });
  });

  group('SensorService peaks', () {
    test('exposes a tracker for every metric, each uniquely labelled', () {
      final service = SensorService();
      addTearDown(service.dispose);

      final peaks = service.allPeaks;
      expect(peaks, isNotEmpty);
      expect(peaks.keys.toSet().length, peaks.length,
          reason: 'duplicate labels would collide in the peaks table');
      expect(peaks.values.toSet().length, peaks.length,
          reason: 'two labels must not point at the same tracker');
    });

    test('covers the channels the detector will read', () {
      final service = SensorService();
      addTearDown(service.dispose);

      final labels = service.allPeaks.keys.join(' | ');
      for (final expected in [
        'Linear acceleration',
        'Total acceleration',
        'Jerk',
        'Rotation',
        'Δv',
        'Speed',
        'Pressure',
        'Field strength',
      ]) {
        expect(labels, contains(expected));
      }
    });

    test('resetPeaks clears every tracker, not just the headline ones', () {
      final service = SensorService();
      addTearDown(service.dispose);

      for (final tracker in service.allPeaks.values) {
        tracker.record(42.0);
      }
      expect(service.allPeaks.values.every((t) => t.hasData), isTrue);

      service.resetPeaks();

      // A peak surviving a reset reads as if it happened in the run being
      // measured, which would silently corrupt a calibration drive.
      expect(service.allPeaks.values.any((t) => t.hasData), isFalse);
      expect(service.peakLinearG, 0);
      expect(service.peakRotationDegPerSec, 0);
      expect(service.peakJerkGPerSec, 0);
    });
  });
}
