import 'dart:math' as math;

/// Standard gravity. Every acceleration on this screen is reported in g as
/// well as m/s^2 — crash-detection thresholds in the literature are quoted in
/// g, but the sensor APIs hand back m/s^2.
const double kStandardGravity = 9.80665;

/// A three-axis sample. Immutable so a snapshot handed to the UI cannot be
/// mutated underneath it by the next sensor event.
class Vector3 {
  const Vector3(this.x, this.y, this.z);

  const Vector3.zero() : x = 0, y = 0, z = 0;

  final double x;
  final double y;
  final double z;

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);

  Vector3 scaled(double factor) => Vector3(x * factor, y * factor, z * factor);
}

/// Tracks the delivery rate of one sensor stream.
///
/// The rate a platform actually delivers is not the rate requested:
/// [SensorInterval] is a hint, Android rounds it to what the hardware
/// supports, and a throttled or absent sensor is the single most common reason
/// an experimental detector misses an event. So the achieved Hz is shown on
/// every card rather than assumed.
class ChannelRate {
  int _count = 0;
  DateTime _windowStart = DateTime.now();
  double _hz = 0;
  DateTime? _lastEvent;

  double get hz => _hz;

  /// Null until the first event arrives.
  DateTime? get lastEvent => _lastEvent;

  /// True once a sample has been seen but none has arrived for a full second —
  /// on a real device this means the stream stalled, not that it is idle.
  bool get isStalled {
    final last = _lastEvent;
    if (last == null) return false;
    return DateTime.now().difference(last) > const Duration(seconds: 1);
  }

  bool get hasData => _lastEvent != null;

  void tick() {
    _count++;
    _lastEvent = DateTime.now();
    final elapsed = _lastEvent!.difference(_windowStart);
    if (elapsed >= const Duration(seconds: 1)) {
      _hz = _count * 1000 / elapsed.inMilliseconds;
      _count = 0;
      _windowStart = _lastEvent!;
    }
  }
}

/// Fixed-capacity ring of recent scalar samples, for the live traces.
///
/// A plain growing List would be an unbounded leak: at 50 Hz this screen
/// produces 3,000 samples a minute and is expected to be left running.
class RingBuffer {
  RingBuffer(this.capacity) : _data = List<double>.filled(capacity, 0);

  final int capacity;
  final List<double> _data;
  int _length = 0;
  int _next = 0;

  int get length => _length;
  bool get isEmpty => _length == 0;

  void add(double value) {
    _data[_next] = value;
    _next = (_next + 1) % capacity;
    if (_length < capacity) _length++;
  }

  /// Oldest-first view of the samples held.
  List<double> toList() {
    if (_length < capacity) return _data.sublist(0, _length);
    return [..._data.sublist(_next), ..._data.sublist(0, _next)];
  }

  void clear() {
    _length = 0;
    _next = 0;
  }
}

/// How the location subsystem is currently placed. Distinguishes the two
/// failure modes users conflate: permission refused (app-level, recoverable in
/// app settings) versus location services switched off (device-level).
enum LocationState {
  unknown,
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  active,
  error,
}

extension LocationStateLabel on LocationState {
  String get label => switch (this) {
    LocationState.unknown => 'Checking…',
    LocationState.servicesDisabled => 'Location services off',
    LocationState.permissionDenied => 'Permission denied',
    LocationState.permissionDeniedForever => 'Permission permanently denied',
    LocationState.active => 'Active',
    LocationState.error => 'Error',
  };
}
