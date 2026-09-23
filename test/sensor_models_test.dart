import 'package:crash_detection/models/sensor_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Vector3', () {
    test('magnitude is the euclidean norm', () {
      expect(const Vector3(3, 4, 0).magnitude, closeTo(5, 1e-9));
      expect(const Vector3.zero().magnitude, 0);
    });

    test('a device at rest reads about 1 g on the accelerometer', () {
      const atRest = Vector3(0, 0, kStandardGravity);
      expect(atRest.magnitude / kStandardGravity, closeTo(1.0, 1e-9));
    });

    test('subtraction is componentwise', () {
      final d = const Vector3(5, 5, 5) - const Vector3(1, 2, 3);
      expect([d.x, d.y, d.z], [4, 3, 2]);
    });
  });

  group('RingBuffer', () {
    test('keeps insertion order before wrapping', () {
      final buffer = RingBuffer(4)
        ..add(1)
        ..add(2)
        ..add(3);
      expect(buffer.toList(), [1, 2, 3]);
      expect(buffer.length, 3);
    });

    test('drops the oldest sample once full, never growing past capacity', () {
      final buffer = RingBuffer(3);
      for (var i = 1; i <= 6; i++) {
        buffer.add(i.toDouble());
      }
      // This is the leak guard: at 50 Hz an unbounded list would be 3,000
      // entries a minute on a screen meant to be left running.
      expect(buffer.length, 3);
      expect(buffer.toList(), [4, 5, 6]);
    });

    test('clear empties it', () {
      final buffer = RingBuffer(2)..add(9);
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.toList(), isEmpty);
    });
  });

  group('ChannelRate', () {
    test('reports no data before the first tick', () {
      final rate = ChannelRate();
      expect(rate.hasData, isFalse);
      expect(rate.isStalled, isFalse, reason: 'idle is not stalled');
      expect(rate.lastEvent, isNull);
    });

    test('a fresh tick is neither stalled nor dataless', () {
      final rate = ChannelRate()..tick();
      expect(rate.hasData, isTrue);
      expect(rate.isStalled, isFalse);
    });
  });

  group('LocationState', () {
    test('every state carries a distinct human label', () {
      final labels = LocationState.values.map((s) => s.label).toSet();
      expect(labels.length, LocationState.values.length);
    });
  });
}
