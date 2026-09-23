import 'package:flutter/material.dart';

import '../models/sensor_models.dart';
import '../services/sensor_service.dart';
import '../theme/app_theme.dart';
import '../widgets/explain_scope.dart';
import '../widgets/sensor_card.dart';
import '../widgets/trace_painter.dart';

/// Live readout of every motion sensor plus the GPS.
///
/// This is the instrumentation step of a crash-detection system, not the
/// detector: nothing here classifies a crash. It exists so the thresholds a
/// later detector will use can be measured off real hardware instead of
/// guessed, and so it is visible which channels this phone can actually
/// deliver at the rate an impact needs.
///
/// Every reading carries an explanation of what it contributes to detection,
/// shown behind the toolbar's explain toggle.
class SensorDashboard extends StatefulWidget {
  const SensorDashboard({super.key});

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> {
  final _service = SensorService();
  bool _explain = true;

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
    return ExplainScope(
      explain: _explain,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Crash Detection',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: _explain ? 'Hide explanations' : 'What is each reading for?',
              onPressed: () => setState(() => _explain = !_explain),
              icon: Icon(
                _explain ? Icons.info : Icons.info_outline,
                size: 20,
                color: _explain ? AppColors.location : AppColors.textSecondary,
              ),
            ),
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
                if (_explain) const _HowDetectionWorks(),
                _derivedCard(),
                _linearCard(),
                _accelerometerCard(),
                _gyroscopeCard(),
                _locationCard(),
                _barometerCard(),
                _magnetometerCard(),
                const _Disclaimer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Cards, ordered by how much each contributes to detection ────────────

  Widget _derivedCard() => SensorCard(
    title: 'DERIVED — IMPACT METRICS',
    unit: 'computed',
    accent: AppColors.linear,
    purpose:
        'These are the candidate detector inputs. A crash is not one number '
        'crossing one threshold — it is a fast, large acceleration together '
        'with rotation and a speed drop, all within a few hundred '
        'milliseconds. Each figure below isolates one of those conditions so '
        'they can be combined into a rule later.',
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
        description:
            'Highest impact force seen since the last reset. The primary '
            'severity proxy. Drive a normal route and this number is your '
            'false-positive floor — any threshold below it will fire on '
            'ordinary driving.',
      ),
      ValueRow(
        label: 'Jerk (d|a|/dt)',
        value: '${_service.jerkGPerSec.toStringAsFixed(1)} g/s',
        description:
            'How fast the force is changing. This is what separates a crash '
            'from hard braking: both can reach 0.8 g, but braking climbs over '
            'a second while an impact arrives in under 50 ms.',
      ),
      ValueRow(
        label: 'Peak jerk',
        value: '${_service.peakJerkGPerSec.toStringAsFixed(1)} g/s',
        description:
            'Highest rate of change since reset. Expected to be the strongest '
            'discriminator between impacts and aggressive-but-normal driving.',
      ),
      ValueRow(
        label: 'Peak rotation',
        value: '${_service.peakRotationDegPerSec.toStringAsFixed(1)} °/s',
        description:
            'Highest angular rate since reset. Sustained high rotation after '
            'an acceleration spike indicates a spin or rollover rather than a '
            'single struck-and-stopped impact.',
      ),
      ValueRow(
        label: 'Δv over last 1 s (estimate)',
        value: '${_service.deltaVEstimate.toStringAsFixed(2)} m/s',
        description:
            'Speed change over the last second. Delta-V is the standard crash '
            'severity measure in accident research — occupant injury risk '
            'tracks it better than peak g. This version is integrated from '
            'the phone, so use it to compare runs, not as an absolute.',
      ),
    ],
  );

  Widget _linearCard() => SensorCard(
    title: 'LINEAR ACCELERATION (GRAVITY REMOVED)',
    unit: 'm/s²',
    accent: AppColors.linear,
    rate: _service.linearRate,
    unavailableReason: _service.unavailable['Linear acceleration'],
    purpose:
        'THE PRIMARY IMPACT SIGNAL — the detector\'s main input. Gravity is '
        'removed, so this reads near zero whenever the vehicle is not '
        'changing speed, whatever angle the phone sits at. Everything a '
        'collision does mechanically shows up here first.',
    children: [
      AxisRow(
        vector: _service.linearAcceleration,
        accent: AppColors.linear,
        description:
            'Direction of the force, which tells you where the vehicle was '
            'struck — front, rear or side. Only meaningful once you know how '
            'the phone is mounted, since the axes are the phone\'s, not the '
            'vehicle\'s. Establishing that mapping is a prerequisite for '
            'classifying impact direction.',
      ),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Magnitude',
        value:
            '${_service.linearAcceleration.magnitude.toStringAsFixed(3)} m/s²',
        description:
            'Total force regardless of direction, in SI units. Direction-'
            'independent, so it works before the mount orientation is known.',
      ),
      ValueRow(
        label: 'Magnitude',
        value: '${_service.linearG.toStringAsFixed(3)} g',
        color: AppColors.linear,
        description:
            'The headline detection number. Rough bands to calibrate against: '
            'normal driving under 0.3 g, hard braking 0.5–0.8 g, a pothole a '
            'brief 2–4 g, a real collision well above that. Your own '
            'measurements override these — that is the point of this screen.',
      ),
    ],
  );

  Widget _accelerometerCard() => SensorCard(
    title: 'ACCELEROMETER (WITH GRAVITY)',
    unit: 'm/s²',
    accent: AppColors.accel,
    rate: _service.accelRate,
    unavailableReason: _service.unavailable['Accelerometer'],
    purpose:
        'The same sensor with gravity left in. Its job in a detector is '
        'orientation and sanity-checking: the gravity vector says which way '
        'is down, which is how you tell an upright vehicle from a rolled one, '
        'and how you confirm the sensor is alive when linear acceleration '
        'correctly reads zero.',
    footer: const Text(
      'Rests near 1 g. Free-fall drives it toward 0 — that is what separates a '
      'dropped phone from a struck one.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
    ),
    children: [
      AxisRow(
        vector: _service.accelerometer,
        accent: AppColors.accel,
        description:
            'Per-axis, gravity included. At rest the ~9.81 sits entirely on '
            'whichever axis points down — read it to work out how the phone '
            'is currently oriented in the vehicle.',
      ),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Magnitude',
        value: '${_service.accelerometer.magnitude.toStringAsFixed(3)} m/s²',
        description: 'Total proper acceleration in SI units.',
      ),
      ValueRow(
        label: 'Magnitude',
        value: '${_service.totalG.toStringAsFixed(3)} g',
        color: AppColors.accel,
        description:
            'Sits at 1.000 at rest. A drop toward 0 means free-fall — the '
            'phone is falling, not the vehicle crashing. This is the single '
            'cheapest false-positive filter you have: a dropped phone shows '
            'near-zero total g immediately before its impact spike, a vehicle '
            'collision does not.',
      ),
    ],
  );

  Widget _gyroscopeCard() => SensorCard(
    title: 'GYROSCOPE',
    unit: 'rad/s',
    accent: AppColors.gyro,
    rate: _service.gyroRate,
    unavailableReason: _service.unavailable['Gyroscope'],
    purpose:
        'Rollover and spin-out detection. A vehicle that rolls or spins may '
        'never register an extreme acceleration peak, so an accelerometer-'
        'only detector misses exactly the crashes most likely to injure '
        'someone. This channel is what catches them.',
    footer: const Text(
      'A rollover shows here before it shows in the accelerometer.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
    ),
    children: [
      AxisRow(
        vector: _service.gyroscope,
        accent: AppColors.gyro,
        description:
            'Roll, pitch and yaw rates about the phone\'s own axes. Sustained '
            'rotation on the vertical axis is a spin-out; sustained rotation '
            'on a horizontal axis is a rollover.',
      ),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Angular rate',
        value: '${_service.gyroscope.magnitude.toStringAsFixed(3)} rad/s',
        description: 'Combined rotation speed in SI units.',
      ),
      ValueRow(
        label: 'Angular rate',
        value: '${_service.rotationDegPerSec.toStringAsFixed(1)} °/s',
        color: AppColors.gyro,
        description:
            'Same figure in degrees per second, which is easier to reason '
            'about: 90 °/s is a quarter-turn each second. Normal cornering '
            'stays low; a spin is both large and sustained, where a pothole '
            'jolt is large and gone within a few samples.',
      ),
    ],
  );

  Widget _locationCard() {
    final p = _service.position;
    final state = _service.locationState;

    if (state != LocationState.active) {
      return SensorCard(
        title: 'LOCATION',
        unit: 'GPS',
        accent: AppColors.location,
        purpose:
            'Without location there is no speed context and nowhere to send '
            'help. A detector can still fire on motion alone, but it cannot '
            'confirm the vehicle stopped, and it cannot report where.',
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
      purpose:
          'The strongest corroborating signal there is. Motion sensors say '
          'something hit the phone; GPS says whether the vehicle was moving '
          'and then stopped. A crash is a large speed drop to near zero that '
          'stays there — a dropped phone in a moving car is not. It also '
          'supplies the coordinates any alert has to carry.',
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
          description:
              'Speed before impact sets severity; speed after impact confirms '
              'it happened. A phone dropped in a cupholder produces a big '
              'acceleration spike while speed carries on unchanged — that '
              'mismatch is how you reject it.',
        ),
        ValueRow(
          label: 'Latitude',
          value: p == null ? '—' : p.latitude.toStringAsFixed(6),
          description:
              'Where to send help. Six decimals is roughly 0.1 m of '
              'resolution — far finer than the fix itself, so trust the '
              'accuracy figure below, not the digit count.',
        ),
        ValueRow(
          label: 'Longitude',
          value: p == null ? '—' : p.longitude.toStringAsFixed(6),
          description: 'Paired with latitude for the alert position.',
        ),
        ValueRow(
          label: 'Horizontal accuracy',
          value: p == null ? '—' : '±${p.accuracy.toStringAsFixed(1)} m',
          description:
              'How much to trust the position and speed. A poor fix — in a '
              'tunnel, under trees, between tall buildings — produces '
              'invented speed changes. Gate any speed-based rule on this '
              'figure or the detector will fire whenever the sky is blocked.',
        ),
        ValueRow(
          label: 'Altitude',
          value: p == null
              ? '—'
              : '${p.altitude.toStringAsFixed(1)} m ±${p.altitudeAccuracy.toStringAsFixed(1)}',
          description:
              'Height above sea level. Marginal for detection, but it can '
              'distinguish a fall from a road from ordinary travel.',
        ),
        ValueRow(
          label: 'Heading',
          value: p == null || p.heading < 0
              ? '—'
              : '${p.heading.toStringAsFixed(1)}°',
          description:
              'Direction of travel from the GPS. A sudden large change '
              'corroborates a spin without relying on the gyroscope, which '
              'drifts over time.',
        ),
        ValueRow(
          label: 'Speed accuracy',
          value: p == null ? '—' : '±${p.speedAccuracy.toStringAsFixed(2)} m/s',
          description:
              'Uncertainty on the speed figure. Needed before treating a '
              'speed drop as real rather than as fix noise.',
        ),
        ValueRow(
          label: 'Fix timestamp',
          value: p == null
              ? '—'
              : p.timestamp.toLocal().toIso8601String().substring(11, 23),
          description:
              'When this fix was taken. GPS lags the motion sensors by '
              'hundreds of milliseconds, so any rule combining the two has to '
              'align them by time rather than assume they arrived together.',
        ),
        if (p != null && p.isMocked)
          const ValueRow(
            label: 'Mock location',
            value: 'YES',
            color: AppColors.danger,
            description:
                'This position is being injected by another app, not measured. '
                'Any data recorded now is invalid for calibration — and a '
                'shipped detector should refuse to act on it.',
          ),
      ],
    );
  }

  Widget _barometerCard() {
    final pressure = _service.pressureHpa;
    return SensorCard(
      title: 'BAROMETER',
      unit: 'hPa',
      accent: AppColors.baro,
      rate: _service.baroRate,
      unavailableReason: _service.unavailable['Barometer'],
      purpose:
          'A secondary, corroborating cue. Airbag deployment inside a closed '
          'cabin causes a brief pressure spike, as does a window or windscreen '
          'breaking. Neither is reliable enough to detect a crash alone, but '
          'either raises confidence in a detection made from the motion '
          'channels.',
      footer: const Text(
        'Many devices have no barometer; an empty card here is normal. A cabin '
        'pressure spike is a secondary airbag-deployment cue.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
      ),
      children: [
        ValueRow(
          label: 'Pressure',
          value: pressure == null ? '—' : '${pressure.toStringAsFixed(2)} hPa',
          color: AppColors.baro,
          emphasis: true,
          description:
              'Ambient air pressure. Around 1013 hPa at sea level, drifting '
              'slowly with weather and altitude. What matters for detection is '
              'not the value but a sharp step in it at the moment of impact.',
        ),
      ],
    );
  }

  Widget _magnetometerCard() => SensorCard(
    title: 'MAGNETOMETER',
    unit: 'µT',
    accent: AppColors.magnet,
    rate: _service.magnetRate,
    unavailableReason: _service.unavailable['Magnetometer'],
    purpose:
        'The weakest contributor here, kept for orientation. It gives an '
        'absolute compass heading that does not drift, which can correct the '
        'gyroscope over a long drive. It is easily disturbed by the vehicle\'s '
        'own metal and electronics, so it is a reference, not a trigger.',
    children: [
      AxisRow(
        vector: _service.magnetometer,
        accent: AppColors.magnet,
        decimals: 2,
        description:
            'Magnetic field per axis. Combined with gravity from the '
            'accelerometer, these give the phone\'s absolute orientation — '
            'the mapping needed to convert phone-frame forces into '
            'vehicle-frame ones.',
      ),
      const SizedBox(height: 8),
      ValueRow(
        label: 'Field strength',
        value: '${_service.magnetometer.magnitude.toStringAsFixed(2)} µT',
        color: AppColors.magnet,
        description:
            'Earth\'s field is roughly 25–65 µT depending on latitude. A '
            'reading far outside that means local interference, and any '
            'heading derived from it is unreliable.',
      ),
    ],
  );
}

/// How the channels combine. Shown above the cards when explanations are on,
/// because the individual descriptions only make sense against the whole.
class _HowDetectionWorks extends StatelessWidget {
  const _HowDetectionWorks();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.location.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 16, color: AppColors.location),
              const SizedBox(width: 7),
              Text(
                'WHAT THESE READINGS ARE FOR',
                style: TextStyle(
                  color: AppColors.location,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'No single sensor detects a crash. Each of the readings below '
            'rules out something the others cannot:\n',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const _Bullet(
            'Linear acceleration says something hit hard.',
            AppColors.linear,
          ),
          const _Bullet(
            'Jerk says it arrived too fast to be braking.',
            AppColors.linear,
          ),
          const _Bullet(
            'Gyroscope catches rolls and spins that never peak in g.',
            AppColors.gyro,
          ),
          const _Bullet(
            'Total g near zero beforehand exposes a dropped phone.',
            AppColors.accel,
          ),
          const _Bullet(
            'GPS speed confirms the vehicle was moving and then stopped.',
            AppColors.location,
          ),
          const _Bullet(
            'Barometer corroborates airbag deployment.',
            AppColors.baro,
          ),
          const SizedBox(height: 8),
          const Text(
            'The hard part is not detecting a 20 g impact — it is not firing '
            'on the thousand potholes, dropped phones and hard stops that look '
            'similar. That is what this screen is for: measure normal driving '
            'first, and let the numbers set the thresholds.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
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
    final explain = ExplainScope.of(context);

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
          if (explain) ...[
            const SizedBox(height: 10),
            const Text(
              'The candidate trigger. Impact force with gravity removed, so it '
              'sits near zero whenever the vehicle is not changing speed. The '
              'trace shows the last few seconds — watch its shape over a '
              'pothole versus a hard stop: both spike, only one spikes and '
              'returns within a couple of samples.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
                height: 1.5,
              ),
            ),
          ],
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
