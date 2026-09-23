import 'dart:math' as math;

/// One fused sample: everything the detector sees at a single instant.
class CrashSample {
  const CrashSample({
    required this.at,
    required this.linearG,
    required this.totalG,
    required this.jerkGPerSec,
    required this.rotationDegPerSec,
    this.speedKmh,
    this.pressureHpa,
  });

  final DateTime at;
  final double linearG;
  final double totalG;
  final double jerkGPerSec;
  final double rotationDegPerSec;

  /// Null when there is no usable GPS fix. Null is not zero — a missing fix
  /// must never be read as "the vehicle stopped".
  final double? speedKmh;
  final double? pressureHpa;
}

/// Every tunable number in one place.
///
/// ⚠️ THESE ARE PLACEHOLDERS, NOT CALIBRATED VALUES. They are starting points
/// from published phone-telematics work, chosen to be roughly right for a
/// rigidly mounted phone. They have not been fitted to this hardware or to
/// any real drive. Replacing them with figures measured on the target phone
/// is the entire purpose of the readout screen.
class CrashThresholds {
  const CrashThresholds({
    this.impactG = 3.5,
    this.severeImpactG = 8.0,
    this.jerkGPerSec = 40,
    this.rotationDegPerSec = 100,
    this.severeRotationDegPerSec = 250,
    this.speedDropKmh = 20,
    this.minPreImpactSpeedKmh = 15,
    this.stoppedSpeedKmh = 8,
    this.freeFallG = 0.35,
    this.pressureJumpHpa = 0.8,
    this.noSpeedDropPenalty = 30,
    this.eventWindow = const Duration(milliseconds: 1500),
    this.preImpactWindow = const Duration(seconds: 3),
    this.crashScore = 70,
    this.possibleScore = 45,
  });

  /// Linear acceleration that opens an event window. Not a crash by itself —
  /// a pothole clears this easily.
  final double impactG;

  /// Above this, the impact alone carries most of the score.
  final double severeImpactG;

  /// Rate of change separating an impact from braking. Both reach a similar
  /// peak; only an impact gets there this fast.
  final double jerkGPerSec;

  final double rotationDegPerSec;
  final double severeRotationDegPerSec;

  /// Speed lost across the event window that counts as a collision.
  final double speedDropKmh;

  /// Below this pre-impact speed nothing is treated as a vehicle crash. A
  /// phone jolted in a parked car is not a collision.
  final double minPreImpactSpeedKmh;

  /// At or below this, the vehicle counts as stopped.
  final double stoppedSpeedKmh;

  /// Total acceleration under this means free-fall. A phone in free-fall
  /// immediately before a spike was dropped, not crashed.
  final double freeFallG;

  final double pressureJumpHpa;

  /// Subtracted when the GPS fix is usable and shows no speed drop. Evidence
  /// against a collision, not merely absent evidence for one — see the note
  /// where it is applied.
  final double noSpeedDropPenalty;

  /// How long to collect evidence after the first threshold crossing.
  final Duration eventWindow;

  /// How far back to look for pre-impact speed and free-fall.
  final Duration preImpactWindow;

  final double crashScore;
  final double possibleScore;
}

/// One test the detector applied, and what it found.
class CrashCondition {
  const CrashCondition({
    required this.label,
    required this.met,
    required this.detail,
    required this.weight,
    this.isGate = false,
    this.unknown = false,
  });

  final String label;
  final bool met;

  /// Measured value against its threshold, for display.
  final String detail;

  /// Contribution to the score when met. Gates score nothing — they veto.
  final double weight;

  /// A gate that failed rejects the event outright, whatever else scored.
  final bool isGate;

  /// The inputs for this test were missing (usually no GPS fix). Neither met
  /// nor failed — it must not be silently counted as either.
  final bool unknown;
}

enum CrashVerdict { noEvent, monitoring, rejected, possible, crash }

extension CrashVerdictLabel on CrashVerdict {
  String get label => switch (this) {
    CrashVerdict.noEvent => 'NO EVENT',
    CrashVerdict.monitoring => 'COLLECTING…',
    CrashVerdict.rejected => 'NOT A CRASH',
    CrashVerdict.possible => 'POSSIBLE CRASH',
    CrashVerdict.crash => 'CRASH DETECTED',
  };
}

/// The detector's output for one event.
class CrashAssessment {
  const CrashAssessment({
    required this.verdict,
    required this.score,
    required this.conditions,
    required this.summary,
    this.at,
    this.peakG = 0,
  });

  const CrashAssessment.idle()
    : verdict = CrashVerdict.noEvent,
      score = 0,
      conditions = const [],
      summary = 'Watching. No impact above threshold.',
      at = null,
      peakG = 0;

  final CrashVerdict verdict;

  /// 0–100. Only meaningful alongside [verdict] — a high score with a failed
  /// gate is still not a crash.
  final double score;
  final List<CrashCondition> conditions;

  /// Plain sentence saying why this verdict was reached.
  final String summary;
  final DateTime? at;
  final double peakG;

  bool get isEvent => verdict != CrashVerdict.noEvent;
}

/// Decides whether a burst of sensor activity was a vehicle crash.
///
/// ⚠️ EXPERIMENTAL. Untuned heuristic, not a safety device.
///
/// The shape of the problem is not "detect a large acceleration" — that is
/// trivial. It is "do not fire on the thousand potholes, dropped phones and
/// hard stops that produce a similar spike". So the design is:
///
///   1. A spike above [CrashThresholds.impactG] opens an evidence window.
///   2. Everything that happens for [CrashThresholds.eventWindow] is
///      collected rather than judged immediately — a crash is a cluster of
///      extremes across channels, and the corroborating ones arrive after the
///      first spike, not with it.
///   3. Gates run first and can veto outright. A free-fall immediately before
///      the spike means a dropped phone; too little speed beforehand means
///      there was no vehicle collision to have.
///   4. The remaining indicators are scored and summed.
///
/// A gate failing beats any score. That asymmetry is deliberate: a false
/// positive here means calling emergency services to a pothole.
class CrashDetector {
  CrashDetector({this.thresholds = const CrashThresholds()});

  final CrashThresholds thresholds;

  final List<CrashSample> _history = [];
  final List<CrashAssessment> events = [];

  DateTime? _windowOpenedAt;
  final List<CrashSample> _window = [];

  CrashAssessment _latest = const CrashAssessment.idle();
  CrashAssessment get latest => _latest;

  bool get isCollecting => _windowOpenedAt != null;

  /// Feed one fused sample. Returns the current assessment.
  CrashAssessment ingest(CrashSample sample) {
    _history.add(sample);
    final cutoff = sample.at.subtract(
      thresholds.preImpactWindow + thresholds.eventWindow,
    );
    _history.removeWhere((s) => s.at.isBefore(cutoff));

    if (_windowOpenedAt != null) {
      _window.add(sample);
      if (sample.at.difference(_windowOpenedAt!) >= thresholds.eventWindow) {
        _latest = _evaluate();
        events.insert(0, _latest);
        if (events.length > 20) events.removeLast();
        _windowOpenedAt = null;
        _window.clear();
      } else {
        _latest = CrashAssessment(
          verdict: CrashVerdict.monitoring,
          score: 0,
          conditions: const [],
          summary: 'Impact detected. Collecting corroborating evidence…',
          at: _windowOpenedAt,
          peakG: _window.fold<double>(0, (m, s) => math.max(m, s.linearG)),
        );
      }
      return _latest;
    }

    if (sample.linearG >= thresholds.impactG) {
      _windowOpenedAt = sample.at;
      _window
        ..clear()
        ..add(sample);
      _latest = CrashAssessment(
        verdict: CrashVerdict.monitoring,
        score: 0,
        conditions: const [],
        summary: 'Impact detected. Collecting corroborating evidence…',
        at: sample.at,
        peakG: sample.linearG,
      );
    }
    return _latest;
  }

  /// Samples from before the window opened, used for pre-impact context.
  List<CrashSample> get _preImpact {
    final opened = _windowOpenedAt;
    if (opened == null) return const [];
    final from = opened.subtract(thresholds.preImpactWindow);
    return _history
        .where((s) => !s.at.isBefore(from) && s.at.isBefore(opened))
        .toList();
  }

  CrashAssessment _evaluate() {
    final t = thresholds;
    final before = _preImpact;

    final peakG = _window.fold<double>(0, (m, s) => math.max(m, s.linearG));
    final peakJerk = _window.fold<double>(
      0,
      (m, s) => math.max(m, s.jerkGPerSec.abs()),
    );
    final peakRotation = _window.fold<double>(
      0,
      (m, s) => math.max(m, s.rotationDegPerSec),
    );

    // ── Gate 1: free-fall before the spike means the phone was dropped ────
    final minTotalGBefore = before.isEmpty
        ? null
        : before.fold<double>(
            double.infinity,
            (m, s) => math.min(m, s.totalG),
          );
    final wasFreeFalling =
        minTotalGBefore != null && minTotalGBefore < t.freeFallG;
    final notFreeFall = CrashCondition(
      label: 'Not a dropped phone',
      met: !wasFreeFalling,
      unknown: minTotalGBefore == null,
      detail: minTotalGBefore == null
          ? 'no prior samples'
          : 'min total ${minTotalGBefore.toStringAsFixed(2)} g '
                '(free-fall < ${t.freeFallG})',
      weight: 0,
      isGate: true,
    );

    // ── Gate 2: the vehicle has to have been moving ───────────────────────
    final speedsBefore = before
        .map((s) => s.speedKmh)
        .whereType<double>()
        .toList();
    final preSpeed = speedsBefore.isEmpty
        ? null
        : speedsBefore.reduce(math.max);
    final wasMoving = preSpeed != null && preSpeed >= t.minPreImpactSpeedKmh;
    final movingGate = CrashCondition(
      label: 'Vehicle was moving',
      met: wasMoving,
      // No fix is not the same as stationary. Marking it unknown keeps the
      // event scoreable on motion alone instead of rejecting a real crash in
      // a tunnel.
      unknown: preSpeed == null,
      detail: preSpeed == null
          ? 'no GPS fix before impact'
          : '${preSpeed.toStringAsFixed(0)} km/h before '
                '(need ≥ ${t.minPreImpactSpeedKmh.toStringAsFixed(0)})',
      weight: 0,
      isGate: true,
    );

    // ── Scored indicators ─────────────────────────────────────────────────
    final impact = CrashCondition(
      label: 'Impact force',
      met: peakG >= t.impactG,
      detail:
          '${peakG.toStringAsFixed(2)} g '
          '(threshold ${t.impactG.toStringAsFixed(1)})',
      weight: peakG >= t.severeImpactG ? 40 : 25,
    );

    final jerk = CrashCondition(
      label: 'Onset too fast for braking',
      met: peakJerk >= t.jerkGPerSec,
      detail:
          '${peakJerk.toStringAsFixed(0)} g/s '
          '(threshold ${t.jerkGPerSec.toStringAsFixed(0)})',
      weight: 25,
    );

    final rotation = CrashCondition(
      label: 'Rotation (spin or rollover)',
      met: peakRotation >= t.rotationDegPerSec,
      detail:
          '${peakRotation.toStringAsFixed(0)} °/s '
          '(threshold ${t.rotationDegPerSec.toStringAsFixed(0)})',
      weight: peakRotation >= t.severeRotationDegPerSec ? 25 : 15,
    );

    final speedsAfter = _window
        .map((s) => s.speedKmh)
        .whereType<double>()
        .toList();
    final postSpeed = speedsAfter.isEmpty ? null : speedsAfter.reduce(math.min);
    final drop = (preSpeed != null && postSpeed != null)
        ? preSpeed - postSpeed
        : null;
    final speedDrop = CrashCondition(
      label: 'Speed collapsed',
      met: drop != null && drop >= t.speedDropKmh,
      unknown: drop == null,
      detail: drop == null
          ? 'no GPS fix across the event'
          : '−${drop.toStringAsFixed(0)} km/h, now '
                '${postSpeed!.toStringAsFixed(0)} km/h '
                '(need −${t.speedDropKmh.toStringAsFixed(0)})',
      weight: 25,
    );

    final pressures = [
      ...before.map((s) => s.pressureHpa),
      ..._window.map((s) => s.pressureHpa),
    ].whereType<double>().toList();
    final pressureJump = pressures.length < 2
        ? null
        : pressures.reduce(math.max) - pressures.reduce(math.min);
    final pressure = CrashCondition(
      label: 'Cabin pressure spike (airbag)',
      met: pressureJump != null && pressureJump >= t.pressureJumpHpa,
      unknown: pressureJump == null,
      detail: pressureJump == null
          ? 'no barometer on this device'
          : '${pressureJump.toStringAsFixed(2)} hPa '
                '(threshold ${t.pressureJumpHpa.toStringAsFixed(1)})',
      weight: 10,
    );

    final conditions = [
      notFreeFall,
      movingGate,
      impact,
      jerk,
      rotation,
      speedDrop,
      pressure,
    ];

    // ── Verdict ───────────────────────────────────────────────────────────
    // A failed gate vetoes outright. The asymmetry is the point: a false
    // positive means calling emergency services to a pothole.
    if (wasFreeFalling) {
      return CrashAssessment(
        verdict: CrashVerdict.rejected,
        score: 0,
        conditions: conditions,
        at: _windowOpenedAt,
        peakG: peakG,
        summary:
            'Rejected — the device was in free-fall immediately before the '
            'impact (${minTotalGBefore.toStringAsFixed(2)} g). That is a '
            'dropped phone, not a vehicle collision.',
      );
    }

    if (preSpeed != null && !wasMoving) {
      return CrashAssessment(
        verdict: CrashVerdict.rejected,
        score: 0,
        conditions: conditions,
        at: _windowOpenedAt,
        peakG: peakG,
        summary:
            'Rejected — the vehicle was doing only '
            '${preSpeed.toStringAsFixed(0)} km/h beforehand. Below '
            '${t.minPreImpactSpeedKmh.toStringAsFixed(0)} km/h there is no '
            'collision to detect.',
      );
    }

    var raw = conditions
        .where((c) => c.met && !c.isGate)
        .fold<double>(0, (sum, c) => sum + c.weight);

    // A working GPS fix that shows no speed change is evidence AGAINST a
    // collision, not merely an absence of evidence for one. A vehicle that
    // hits something hard enough to register several g does not carry on at
    // the same speed. This is what separates a pothole — big spike, fast
    // onset, speed unchanged — from a crash, and a pothole is the single
    // most common false positive there is.
    //
    // Applied only when the fix is usable. When speed is unknown the event
    // still stands on motion alone, so a crash in a tunnel is not discarded.
    if (!speedDrop.unknown && !speedDrop.met) {
      raw -= t.noSpeedDropPenalty;
    }

    final score = raw.clamp(0, 100).toDouble();

    final gpsUnknown = movingGate.unknown;
    if (score >= t.crashScore) {
      return CrashAssessment(
        verdict: CrashVerdict.crash,
        score: score,
        conditions: conditions,
        at: _windowOpenedAt,
        peakG: peakG,
        summary:
            'Peak ${peakG.toStringAsFixed(1)} g with corroboration across '
            '${conditions.where((c) => c.met && !c.isGate).length} channels.'
            '${gpsUnknown ? ' No GPS fix, so this rests on motion alone.' : ''}',
      );
    }

    if (score >= t.possibleScore) {
      return CrashAssessment(
        verdict: CrashVerdict.possible,
        score: score,
        conditions: conditions,
        at: _windowOpenedAt,
        peakG: peakG,
        summary:
            'Peak ${peakG.toStringAsFixed(1)} g, but too few channels agree '
            'to call it. This is the band to inspect when tuning — record '
            'what actually happened.',
      );
    }

    return CrashAssessment(
      verdict: CrashVerdict.rejected,
      score: score,
      conditions: conditions,
      at: _windowOpenedAt,
      peakG: peakG,
      summary:
          'Peak ${peakG.toStringAsFixed(1)} g crossed the trigger, but nothing '
          'else agreed — the signature of a pothole or a hard stop rather '
          'than a collision.',
    );
  }

  void reset() {
    _history.clear();
    _window.clear();
    _windowOpenedAt = null;
    events.clear();
    _latest = const CrashAssessment.idle();
  }
}
