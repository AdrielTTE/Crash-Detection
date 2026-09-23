import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/sensor_models.dart';

/// One timestamped acceleration sample, kept only long enough to integrate.
class _TimedVector {
  _TimedVector(this.at, this.value);

  final DateTime at;
  final Vector3 value;
}

/// Aggregates every motion sensor and the GPS into a single snapshot the UI
/// can read.
///
/// ⚠️ TWO CLOCKS, DELIBERATELY SEPARATED
/// Sensors are subscribed at [SensorInterval.gameInterval] (~50 Hz) because a
/// collision pulse lasts 100–150 ms and is simply not visible at the 5 Hz
/// default. The UI is a different matter: rebuilding a tree 50 times a second
/// drops frames and tells the reader nothing a 20 Hz redraw does not. So
/// sensor events mutate fields, and a separate [Timer] calls
/// [notifyListeners]. Never call notifyListeners from a sensor callback.
class SensorService extends ChangeNotifier {
  // ── Raw channels ────────────────────────────────────────────────────────
  Vector3 accelerometer = const Vector3.zero();
  Vector3 linearAcceleration = const Vector3.zero();
  Vector3 gyroscope = const Vector3.zero();
  Vector3 magnetometer = const Vector3.zero();
  double? pressureHpa;

  final accelRate = ChannelRate();
  final linearRate = ChannelRate();
  final gyroRate = ChannelRate();
  final magnetRate = ChannelRate();
  final baroRate = ChannelRate();
  final locationRate = ChannelRate();

  /// Set when a stream reports an error — typically a sensor the device does
  /// not physically have. A missing barometer is common and not a fault.
  final Map<String, String> unavailable = {};

  // ── Derived, crash-relevant ─────────────────────────────────────────────
  /// Magnitude of linear (gravity-removed) acceleration, in g. This is the
  /// primary impact signal: at rest it sits near 0, not near 1.
  double get linearG => linearAcceleration.magnitude / kStandardGravity;

  /// Magnitude of total acceleration including gravity, in g. Sits near 1 at
  /// rest; free-fall drives it to 0, which is how a drop is told from a hit.
  double get totalG => accelerometer.magnitude / kStandardGravity;

  /// Angular rate magnitude in degrees/second. A rollover shows here long
  /// before it shows in the accelerometer.
  double get rotationDegPerSec => gyroscope.magnitude * 180 / math.pi;

  double peakLinearG = 0;
  double peakRotationDegPerSec = 0;
  double peakJerkGPerSec = 0;

  /// Rate of change of [linearG], in g per second. Distinguishes an impact
  /// from hard braking: both reach a similar peak, only one gets there fast.
  double jerkGPerSec = 0;

  /// Speed change integrated over the last second, in m/s.
  ///
  /// ⚠️ ESTIMATE ONLY. This is a short rolling integral of a noisy MEMS
  /// signal; bias makes it drift and it is not a calibrated delta-V. It is
  /// here because the 1-second window is the standard comparison for impact
  /// severity, not because the number is trustworthy in absolute terms.
  double deltaVEstimate = 0;

  /// Recent [linearG] samples for the live trace.
  final trace = RingBuffer(180);

  DateTime? sessionStart;
  bool _running = false;
  bool get isRunning => _running;

  // ── Location ────────────────────────────────────────────────────────────
  Position? position;
  LocationState locationState = LocationState.unknown;
  String? locationError;

  double? get speedKmh {
    final p = position;
    if (p == null) return null;
    // Android reports a negative speed when it has no fix-derived velocity.
    return p.speed < 0 ? null : p.speed * 3.6;
  }

  // ── Internals ───────────────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subs = [];
  final List<_TimedVector> _window = [];
  Timer? _uiTimer;
  double _lastLinearG = 0;
  DateTime? _lastJerkAt;

  static const _uiRefresh = Duration(milliseconds: 50);
  static const _integrationWindow = Duration(seconds: 1);

  Future<void> start() async {
    if (_running) return;
    _running = true;
    sessionStart = DateTime.now();

    _listen<AccelerometerEvent>(
      accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval),
      'Accelerometer',
      (e) {
        accelerometer = Vector3(e.x, e.y, e.z);
        accelRate.tick();
      },
    );

    _listen<UserAccelerometerEvent>(
      userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval),
      'Linear acceleration',
      (e) {
        linearAcceleration = Vector3(e.x, e.y, e.z);
        linearRate.tick();
        _onLinearSample(linearAcceleration);
      },
    );

    _listen<GyroscopeEvent>(
      gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval),
      'Gyroscope',
      (e) {
        gyroscope = Vector3(e.x, e.y, e.z);
        gyroRate.tick();
        peakRotationDegPerSec =
            math.max(peakRotationDegPerSec, rotationDegPerSec);
      },
    );

    _listen<MagnetometerEvent>(
      magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval),
      'Magnetometer',
      (e) {
        magnetometer = Vector3(e.x, e.y, e.z);
        magnetRate.tick();
      },
    );

    _listen<BarometerEvent>(
      barometerEventStream(samplingPeriod: SensorInterval.uiInterval),
      'Barometer',
      (e) {
        pressureHpa = e.pressure;
        baroRate.tick();
      },
    );

    await _startLocation();

    _uiTimer = Timer.periodic(_uiRefresh, (_) => notifyListeners());
    notifyListeners();
  }

  /// Subscribes with an error handler, so one absent sensor degrades its own
  /// card instead of taking down the screen.
  void _listen<T>(Stream<T> stream, String label, void Function(T) onData) {
    _subs.add(
      stream.listen(
        onData,
        onError: (Object error) {
          unavailable[label] = error.toString();
        },
        cancelOnError: false,
      ),
    );
  }

  void _onLinearSample(Vector3 sample) {
    final now = DateTime.now();
    final g = sample.magnitude / kStandardGravity;

    peakLinearG = math.max(peakLinearG, g);
    trace.add(g);

    final lastAt = _lastJerkAt;
    if (lastAt != null) {
      final dt = now.difference(lastAt).inMicroseconds / 1e6;
      if (dt > 0) {
        jerkGPerSec = (g - _lastLinearG) / dt;
        peakJerkGPerSec = math.max(peakJerkGPerSec, jerkGPerSec.abs());
      }
    }
    _lastLinearG = g;
    _lastJerkAt = now;

    _window.add(_TimedVector(now, sample));
    final cutoff = now.subtract(_integrationWindow);
    _window.removeWhere((s) => s.at.isBefore(cutoff));
    _recomputeDeltaV();
  }

  /// Trapezoidal integration of the acceleration vector over the window, then
  /// the magnitude of the result. Integrating the vector rather than the
  /// scalar magnitude matters: magnitude is always positive, so integrating it
  /// would accumulate steadily even when the device is merely vibrating in
  /// place.
  void _recomputeDeltaV() {
    if (_window.length < 2) {
      deltaVEstimate = 0;
      return;
    }
    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (var i = 1; i < _window.length; i++) {
      final prev = _window[i - 1];
      final curr = _window[i];
      final dt = curr.at.difference(prev.at).inMicroseconds / 1e6;
      if (dt <= 0) continue;
      sx += (prev.value.x + curr.value.x) / 2 * dt;
      sy += (prev.value.y + curr.value.y) / 2 * dt;
      sz += (prev.value.z + curr.value.z) / 2 * dt;
    }
    deltaVEstimate = Vector3(sx, sy, sz).magnitude;
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationState = LocationState.servicesDisabled;
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        locationState = LocationState.permissionDeniedForever;
        return;
      }
      if (permission == LocationPermission.denied) {
        locationState = LocationState.permissionDenied;
        return;
      }

      locationState = LocationState.active;
      _subs.add(
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            // bestForNavigation, not best: it keeps the GPS chip in its
            // high-rate mode, which is what produces a usable per-second
            // speed instead of one updated when the fix drifts.
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen(
          (p) {
            position = p;
            locationRate.tick();
          },
          onError: (Object error) {
            locationState = LocationState.error;
            locationError = error.toString();
          },
          cancelOnError: false,
        ),
      );
    } catch (error) {
      locationState = LocationState.error;
      locationError = error.toString();
    }
  }

  Future<void> stop() async {
    _uiTimer?.cancel();
    _uiTimer = null;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _window.clear();
    _running = false;
    notifyListeners();
  }

  /// Clears the held peaks and the trace without dropping the subscriptions —
  /// the button the operator presses between test runs.
  void resetPeaks() {
    peakLinearG = 0;
    peakRotationDegPerSec = 0;
    peakJerkGPerSec = 0;
    deltaVEstimate = 0;
    jerkGPerSec = 0;
    trace.clear();
    _window.clear();
    sessionStart = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    super.dispose();
  }
}
