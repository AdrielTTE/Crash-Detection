import 'package:crash_detection/services/crash_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scenario tests for the detector.
///
/// These are the only tests in this project that assert something about
/// crash detection itself. Everything else checks plumbing. The scenarios
/// below are hand-built rather than recorded, so passing them proves the
/// decision LOGIC is coherent — it does not prove the THRESHOLDS are right.
/// Only a real calibration drive can do that.
///
/// Every sample carries an explicit timestamp, so no test depends on the
/// wall clock or on how fast the machine runs them.
const _tick = Duration(milliseconds: 20); // 50 Hz, the real sensor rate
final _t0 = DateTime.utc(2026, 1, 1, 12);

class _Feed {
  _Feed(this.detector);

  final CrashDetector detector;
  int _n = 0;

  /// Feeds [count] samples holding the given values steady.
  void steady({
    required int count,
    double linearG = 0.05,
    double totalG = 1.0,
    double jerk = 0,
    double rotation = 2,
    double? speedKmh,
    double? pressureHpa,
  }) {
    for (var i = 0; i < count; i++) {
      detector.ingest(
        CrashSample(
          at: _t0.add(_tick * _n++),
          linearG: linearG,
          totalG: totalG,
          jerkGPerSec: jerk,
          rotationDegPerSec: rotation,
          speedKmh: speedKmh,
          pressureHpa: pressureHpa,
        ),
      );
    }
  }
}

void main() {
  group('no event', () {
    test('normal driving never opens a window', () {
      final d = CrashDetector();
      _Feed(d).steady(count: 300, linearG: 0.22, speedKmh: 60);

      expect(d.latest.verdict, CrashVerdict.noEvent);
      expect(d.events, isEmpty);
    });

    test('hard braking stays below the trigger entirely', () {
      // Braking reaches a real 0.75 g. It must not even open a window —
      // rejecting it later would still cost the evidence-collection window.
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 150, linearG: 0.1, speedKmh: 70);
      f.steady(count: 50, linearG: 0.75, jerk: 3, speedKmh: 30);
      f.steady(count: 50, linearG: 0.1, speedKmh: 0);

      expect(d.latest.verdict, CrashVerdict.noEvent);
      expect(d.events, isEmpty);
    });
  });

  group('rejections — the cases that matter', () {
    test('a pothole is rejected: big spike, fast onset, speed unchanged', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2, speedKmh: 55);
      f.steady(count: 4, linearG: 4.5, jerk: 120, rotation: 30, speedKmh: 55);
      f.steady(count: 120, linearG: 0.2, rotation: 5, speedKmh: 55);

      final event = d.events.single;
      expect(event.verdict, CrashVerdict.rejected);
      // Impact and jerk both scored, but a usable fix showing no speed change
      // is evidence against a collision and pulls it under the band.
      expect(event.score, lessThan(45));
    });

    test('a dropped phone is rejected by the free-fall gate', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.1, speedKmh: 50);
      // Free-fall: total g collapses toward zero while the phone falls.
      f.steady(count: 15, linearG: 0.9, totalG: 0.04, speedKmh: 50);
      // Landing: a large spike with everything else a crash would show.
      f.steady(
        count: 5,
        linearG: 12,
        totalG: 12,
        jerk: 400,
        rotation: 300,
        speedKmh: 50,
      );
      f.steady(count: 120, linearG: 0.1, speedKmh: 50);

      final event = d.events.single;
      expect(event.verdict, CrashVerdict.rejected);
      expect(event.score, 0, reason: 'a failed gate scores nothing');
      expect(event.summary, contains('free-fall'));

      final gate = event.conditions.firstWhere((c) => c.isGate && !c.met);
      expect(gate.label, 'Not a dropped phone');
    });

    test('free-fall vetoes even a perfect score on every other channel', () {
      // The drop above also lacked a speed change. This one has everything:
      // severe impact, extreme jerk, rollover-grade rotation, speed to zero.
      // The gate must still win.
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.1, speedKmh: 60);
      f.steady(count: 10, linearG: 0.5, totalG: 0.02, speedKmh: 60);
      f.steady(
        count: 5,
        linearG: 20,
        totalG: 20,
        jerk: 900,
        rotation: 400,
        speedKmh: 0,
      );
      f.steady(count: 120, linearG: 0.1, rotation: 350, speedKmh: 0);

      expect(d.events.single.verdict, CrashVerdict.rejected);
      expect(d.events.single.score, 0);
    });

    test('a jolt in a parked car is rejected — nothing was moving', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.02, speedKmh: 0);
      f.steady(count: 5, linearG: 9, jerk: 300, rotation: 200, speedKmh: 0);
      f.steady(count: 120, linearG: 0.02, speedKmh: 0);

      final event = d.events.single;
      expect(event.verdict, CrashVerdict.rejected);
      expect(event.summary, contains('km/h beforehand'));
    });
  });

  group('detections', () {
    test('a collision at speed is detected', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2, speedKmh: 65);
      f.steady(
        count: 6,
        linearG: 11,
        totalG: 11,
        jerk: 500,
        rotation: 180,
        speedKmh: 65,
      );
      f.steady(count: 120, linearG: 0.4, rotation: 60, speedKmh: 2);

      final event = d.events.single;
      expect(event.verdict, CrashVerdict.crash);
      expect(event.score, greaterThanOrEqualTo(70));
      expect(event.peakG, closeTo(11, 0.001));

      // The gates must be reported as passed, not merely absent.
      for (final gate in event.conditions.where((c) => c.isGate)) {
        expect(gate.met, isTrue, reason: gate.label);
      }
    });

    test('a crash with no GPS fix still detects on motion alone', () {
      // A tunnel. Speed is unknown, not zero. Treating unknown as "did not
      // stop" would discard a real crash.
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2);
      f.steady(count: 6, linearG: 14, totalG: 14, jerk: 600, rotation: 300);
      f.steady(count: 120, linearG: 0.3, rotation: 120);

      final event = d.events.single;
      expect(event.verdict, CrashVerdict.crash);
      expect(event.summary, contains('No GPS fix'));

      final speedCondition = event.conditions.firstWhere(
        (c) => c.label == 'Speed collapsed',
      );
      expect(speedCondition.unknown, isTrue);
      expect(speedCondition.met, isFalse);
    });

    test('a rollover is detected mainly on rotation', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2, speedKmh: 55);
      f.steady(
        count: 40,
        linearG: 4.2,
        totalG: 4.2,
        jerk: 90,
        rotation: 320,
        speedKmh: 20,
      );
      f.steady(count: 80, linearG: 1.0, rotation: 280, speedKmh: 0);

      expect(d.events.single.verdict, CrashVerdict.crash);
    });
  });

  group('mechanics', () {
    test('reports collecting while the window is open, then resolves', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2, speedKmh: 60);

      f.steady(count: 3, linearG: 9, jerk: 400, rotation: 200, speedKmh: 60);
      expect(d.latest.verdict, CrashVerdict.monitoring);
      expect(d.isCollecting, isTrue);
      expect(d.events, isEmpty, reason: 'not logged until the window closes');

      f.steady(count: 120, linearG: 0.2, speedKmh: 0);
      expect(d.isCollecting, isFalse);
      expect(d.events, hasLength(1));
      expect(d.latest.verdict, isNot(CrashVerdict.monitoring));
    });

    test('every condition carries a measured detail for display', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2, speedKmh: 60);
      f.steady(count: 6, linearG: 9, jerk: 400, rotation: 200, speedKmh: 60);
      f.steady(count: 120, linearG: 0.2, speedKmh: 0);

      final event = d.events.single;
      expect(event.conditions, isNotEmpty);
      for (final c in event.conditions) {
        expect(c.detail, isNotEmpty, reason: c.label);
        expect(c.label, isNotEmpty);
      }
    });

    test('the log keeps newest first and is bounded', () {
      final d = CrashDetector();
      final f = _Feed(d);
      for (var i = 0; i < 25; i++) {
        f.steady(count: 160, linearG: 0.2, speedKmh: 60);
        f.steady(count: 6, linearG: 5, jerk: 200, speedKmh: 60);
        f.steady(count: 90, linearG: 0.2, speedKmh: 60);
      }

      expect(d.events.length, lessThanOrEqualTo(20));
      final times = d.events.map((e) => e.at!).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i - 1].isAfter(times[i]), isTrue);
      }
    });

    test('reset clears the log and returns to idle', () {
      final d = CrashDetector();
      final f = _Feed(d)..steady(count: 200, linearG: 0.2, speedKmh: 60);
      f.steady(count: 6, linearG: 9, jerk: 400, speedKmh: 60);
      f.steady(count: 120, linearG: 0.2, speedKmh: 0);
      expect(d.events, isNotEmpty);

      d.reset();

      expect(d.events, isEmpty);
      expect(d.latest.verdict, CrashVerdict.noEvent);
      expect(d.isCollecting, isFalse);
    });

    test('thresholds are injectable, so tuning does not need a code change',
        () {
      // A 1 g bump is nothing by default but everything at a 0.5 g trigger.
      const sensitive = CrashThresholds(impactG: 0.5);
      final d = CrashDetector(thresholds: sensitive);
      final f = _Feed(d)..steady(count: 200, linearG: 0.1, speedKmh: 60);
      f.steady(count: 5, linearG: 1.0, jerk: 60, speedKmh: 60);
      f.steady(count: 120, linearG: 0.1, speedKmh: 60);

      expect(d.events, hasLength(1));

      final blunt = CrashDetector();
      final f2 = _Feed(blunt)..steady(count: 200, linearG: 0.1, speedKmh: 60);
      f2.steady(count: 5, linearG: 1.0, jerk: 60, speedKmh: 60);
      expect(blunt.events, isEmpty);
    });
  });
}
