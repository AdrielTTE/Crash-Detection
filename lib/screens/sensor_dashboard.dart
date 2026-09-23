import 'package:flutter/material.dart';

import '../models/sensor_models.dart';
import '../services/sensor_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sensor_card.dart';
import '../widgets/trace_painter.dart';

/// Live readout of every motion sensor plus the GPS.
///
/// This is the instrumentation step, not a detector: nothing here classifies a
/// crash. It exists so the thresholds a later detector will use can be read
/// off real hardware instead of guessed.
class SensorDashboard extends StatefulWidget {
  const SensorDashboard({super.key});

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> {
  final _service = SensorService();

  @override
  void initState() {
    super.initState();
    _service.start();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Crash Detection',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset peaks',
            onPressed: _service.resetPeaks,
            icon: const Icon(Icons.restart_alt, size: 20),
          ),
          ListenableBuilder(
            listenable: _service,
            builder: (context, _) => IconButton(
              tooltip: _service.isRunning ? 'Stop' : 'Start',
              onPressed: () =>
                  _service.isRunning ? _service.stop() : _service.start(),
              icon: Icon(
                _service.isRunning ? Icons.pause_circle : Icons.play_circle,
                size: 22,
                color: _service.isRunning ? AppColors.ok : AppColors.warn,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _ImpactHero(service: _service),
              const SizedBox(height: 16),
              _derivedCard(),
              _accelerometerCard(),
              _linearCard(),
              _gyroscopeCard(),
              _magnetometerCard(),
              _barometerCard(),
              _locationCard(),
              const _Disclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cards ───────────────────────────────────────────────────────────────

  Widget _derivedCard() => SensorCard(
    title: 'DERIVED — IMPACT METRICS',
    unit: 'computed',
    accent: AppColors.linear,
    footer: const Text(
      'Δv is a rolling integral of a noisy MEMS signal — it drifts and is not '
      'a calibrated delta-V. Treat it as a relative indicator only.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
    ),
    children: [
      ValueRow(
        label: 'Peak linear acceleration',
        value: '${_service.peakLinearG.toStringAsFixed(3)} g',
        color: AppColors.linear,
        emphasis: true,
      ),
      ValueRow(
        label: 'Jerk (d|a|/dt)',
        value: '${_service.jerkGPerSec.toStringAsFixed(1)} g/s',
      ),
      ValueRow(
        label: 'Peak jerk',
        value: '${_service.peakJerkGPerSec.toStringAsFixed(1)} g/s',
      ),
      ValueRow(
        label: 'Peak rotation',
        value: '${_service.peakRotationDegPerSec.toStringAsFixed(1)} °/s',
      ),
      ValueRow(
        label: 'Δv over last 1 s (estimate)',
        value: '${_service.deltaVEstimate.toStringAsFixed(2)} m/s',
      ),
    ],
  );

  Widget _accelerometerCard() => SensorCard(
    title: 'ACCELEROMETER (WITH GRAVITY)',
    unit: 'm/s²',
    accent: AppColors.accel,
    rate: _service.accelRate,
    unavailableReason: _service.unavailable['Accelerometer'],
    footer: const Text(
      'Rests near 1 g. Free-fall drives it toward 0 — that is what separates a '
      'dropped phone from a struck one.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
    ),
    children: [
      AxisRow(vector: _service.accelerometer, accent: AppColors.accel),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Magnitude',
        value: '${_service.accelerometer.magnitude.toStringAsFixed(3)} m/s²',
      ),
      ValueRow(
        label: 'Magnitude',
        value: '${_service.totalG.toStringAsFixed(3)} g',
        color: AppColors.accel,
      ),
    ],
  );

  Widget _linearCard() => SensorCard(
    title: 'LINEAR ACCELERATION (GRAVITY REMOVED)',
    unit: 'm/s²',
    accent: AppColors.linear,
    rate: _service.linearRate,
    unavailableReason: _service.unavailable['Linear acceleration'],
    children: [
      AxisRow(vector: _service.linearAcceleration, accent: AppColors.linear),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Magnitude',
        value:
            '${_service.linearAcceleration.magnitude.toStringAsFixed(3)} m/s²',
      ),
      ValueRow(
        label: 'Magnitude',
        value: '${_service.linearG.toStringAsFixed(3)} g',
        color: AppColors.linear,
      ),
    ],
  );

  Widget _gyroscopeCard() => SensorCard(
    title: 'GYROSCOPE',
    unit: 'rad/s',
    accent: AppColors.gyro,
    rate: _service.gyroRate,
    unavailableReason: _service.unavailable['Gyroscope'],
    footer: const Text(
      'A rollover shows here before it shows in the accelerometer.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
    ),
    children: [
      AxisRow(vector: _service.gyroscope, accent: AppColors.gyro),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Angular rate',
        value: '${_service.gyroscope.magnitude.toStringAsFixed(3)} rad/s',
      ),
      ValueRow(
        label: 'Angular rate',
        value: '${_service.rotationDegPerSec.toStringAsFixed(1)} °/s',
        color: AppColors.gyro,
      ),
    ],
  );

  Widget _magnetometerCard() => SensorCard(
    title: 'MAGNETOMETER',
    unit: 'µT',
    accent: AppColors.magnet,
    rate: _service.magnetRate,
    unavailableReason: _service.unavailable['Magnetometer'],
    children: [
      AxisRow(vector: _service.magnetometer, accent: AppColors.magnet, decimals: 2),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Field strength',
        value: '${_service.magnetometer.magnitude.toStringAsFixed(2)} µT',
        color: AppColors.magnet,
      ),
    ],
  );

  Widget _barometerCard() {
    final pressure = _service.pressureHpa;
    return SensorCard(
      title: 'BAROMETER',
      unit: 'hPa',
      accent: AppColors.baro,
      rate: _service.baroRate,
      unavailableReason: _service.unavailable['Barometer'],
      footer: const Text(
        'Many devices have no barometer; an empty card here is normal. A cabin '
        'pressure spike is a secondary airbag-deployment cue.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
      ),
      children: [
        ValueRow(
          label: 'Pressure',
          value: pressure == null
              ? '—'
              : '${pressure.toStringAsFixed(2)} hPa',
          color: AppColors.baro,
          emphasis: true,
        ),
      ],
    );
  }

  Widget _locationCard() {
    final p = _service.position;
    final state = _service.locationState;

    if (state != LocationState.active) {
      return SensorCard(
        title: 'LOCATION',
        unit: 'GPS',
        accent: AppColors.location,
        children: [
          ValueRow(
            label: 'Status',
            value: state.label,
            color: AppColors.warn,
          ),
          if (_service.locationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _service.locationError!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
        ],
      );
    }

    return SensorCard(
      title: 'LOCATION',
      unit: 'GPS',
      accent: AppColors.location,
      rate: _service.locationRate,
      footer: const Text(
        'Requested at bestForNavigation so speed updates every fix rather than '
        'only on meaningful movement.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
      ),
      children: [
        ValueRow(
          label: 'Speed',
          value: _service.speedKmh == null
              ? '—'
              : '${_service.speedKmh!.toStringAsFixed(1)} km/h',
          color: AppColors.location,
          emphasis: true,
        ),
        ValueRow(
          label: 'Latitude',
          value: p == null ? '—' : p.latitude.toStringAsFixed(6),
        ),
        ValueRow(
          label: 'Longitude',
          value: p == null ? '—' : p.longitude.toStringAsFixed(6),
        ),
        ValueRow(
          label: 'Horizontal accuracy',
          value: p == null ? '—' : '±${p.accuracy.toStringAsFixed(1)} m',
        ),
        ValueRow(
          label: 'Altitude',
          value: p == null
              ? '—'
              : '${p.altitude.toStringAsFixed(1)} m ±${p.altitudeAccuracy.toStringAsFixed(1)}',
        ),
        ValueRow(
          label: 'Heading',
          value: p == null || p.heading < 0
              ? '—'
              : '${p.heading.toStringAsFixed(1)}°',
        ),
        ValueRow(
          label: 'Speed accuracy',
          value: p == null ? '—' : '±${p.speedAccuracy.toStringAsFixed(2)} m/s',
        ),
        ValueRow(
          label: 'Fix timestamp',
          value: p == null
              ? '—'
              : p.timestamp.toLocal().toIso8601String().substring(11, 23),
        ),
        if (p != null && p.isMocked)
          const ValueRow(
            label: 'Mock location',
            value: 'YES',
            color: AppColors.danger,
          ),
      ],
    );
  }
}

/// The one number worth reading mid-drive, with its recent history.
class _ImpactHero extends StatelessWidget {
  const _ImpactHero({required this.service});

  final SensorService service;

  @override
  Widget build(BuildContext context) {
    final g = service.linearG;
    // Advisory bands only — not a calibrated detector. Real airbag thresholds
    // are measured at the chassis, not by a phone loose in a cupholder.
    final color = g >= 4
        ? AppColors.danger
        : g >= 2
        ? AppColors.warn
        : AppColors.linear;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LINEAR ACCELERATION',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                g.toStringAsFixed(3),
                style: AppTheme.numeric.copyWith(
                  color: color,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'g',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'PEAK',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    service.peakLinearG.toStringAsFixed(3),
                    style: AppTheme.numeric.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 70,
            width: double.infinity,
            child: CustomPaint(
              painter: TracePainter(
                samples: service.trace.toList(),
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'last ${(service.trace.length * 0.02).toStringAsFixed(1)} s · '
            '${service.linearRate.hz.toStringAsFixed(0)} Hz',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'EXPERIMENTAL INSTRUMENTATION ONLY\n\n'
        'This build reads sensors and reports them. It does not detect a '
        'crash, does not alert anyone, and must not be relied on for safety. '
        'Phone-based sensing is affected by how the device is mounted: a phone '
        'loose in a cupholder records its own flight, not the vehicle\'s.',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 10.5,
          height: 1.5,
        ),
      ),
    );
  }
}
