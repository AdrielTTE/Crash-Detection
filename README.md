# Crash Detection

Experimental Flutter app for vehicle crash detection research. Android + iOS.

**Step 1 of the project — instrumentation.** This build reads every motion sensor and the
GPS and displays them live. It does **not** classify a crash, does not alert anyone, and
must not be relied on for safety. It exists so the thresholds a later detector will use can
be measured on real hardware instead of guessed.

---

## What it reads

| Channel | Source | Rate requested | Reported |
|---|---|---|---|
| Accelerometer (with gravity) | `sensors_plus` | 50 Hz (`gameInterval`) | X/Y/Z m/s², magnitude in m/s² and g |
| Linear acceleration (gravity removed) | `sensors_plus` | 50 Hz | X/Y/Z m/s², magnitude in m/s² and g |
| Gyroscope | `sensors_plus` | 50 Hz | X/Y/Z rad/s, magnitude in rad/s and °/s |
| Magnetometer | `sensors_plus` | 15 Hz (`uiInterval`) | X/Y/Z µT, field strength |
| Barometer | `sensors_plus` | 15 Hz | Pressure in hPa |
| Location | `geolocator` | every fix (`bestForNavigation`) | lat, lon, accuracy, altitude, heading, speed, speed accuracy, fix time, mock flag |

### What each channel contributes to detection

No single sensor detects a crash. Each channel rules out something the others cannot — the
hard problem is not spotting a 20 g impact, it's *not* firing on the thousand potholes,
dropped phones and hard stops that look similar.

| Channel | What it's for | What it rules out |
|---|---|---|
| **Linear acceleration** | Primary trigger. Impact force with gravity removed, so it reads ~0 whenever the vehicle isn't changing speed, at any phone angle. | Nothing on its own — this is the signal the rest qualify. |
| **Jerk** | Says the force arrived *too fast* to be braking. | Hard braking. Both reach ~0.8 g; braking takes a second, an impact under 50 ms. |
| **Gyroscope** | Rollover and spin-out. | Misses. A vehicle that rolls may never peak in g — an accelerometer-only detector misses exactly the crashes most likely to injure someone. |
| **Total g (with gravity)** | Orientation reference, and free-fall detection. | A dropped phone. Total g collapses toward 0 during the fall, immediately before its impact spike. A vehicle collision never does that. |
| **GPS speed** | Confirms the vehicle was moving and then stopped. | A phone dropped inside a moving car — big spike, speed unchanged. That mismatch is the rejection. |
| **GPS accuracy** | Gates trust in speed. | Tunnel/urban-canyon fixes that invent speed changes. Without this gate the detector fires whenever the sky is blocked. |
| **Barometer** | Corroborates airbag deployment via cabin pressure spike. | Nothing alone — it raises confidence in a detection already made. |
| **Magnetometer** | Non-drifting compass reference; with gravity, gives absolute orientation. | Gyroscope drift over a long drive. Needed to map phone-frame forces to vehicle-frame. |
| **Lat/lon** | Where to send help. | — |

**Calibration order:** drive a normal route first. Your peak linear g over ordinary driving
*is* the false-positive floor — any threshold below it fires on normal use. Then record
potholes, hard stops and phone drops deliberately, and set thresholds above all of them.

Tap the **ⓘ** in the toolbar to see all of this inline against the live numbers.

### Derived metrics

| Metric | Meaning |
|---|---|
| Linear acceleration (g) | Primary impact signal. Near **0** at rest, not near 1. |
| Total acceleration (g) | Near **1** at rest. Free-fall drives it toward 0 — this is what separates a dropped phone from a struck one. |
| Jerk (g/s) | Rate of change of linear g. Distinguishes an impact from hard braking: both reach a similar peak, only one gets there fast. |
| Rotation (°/s) | A rollover appears here before it appears in the accelerometer. |
| Δv over last 1 s | Rolling trapezoidal integral of the linear-acceleration **vector**. |
| Peak hold | Session **high and low** for every metric — see below. Reset with the ↻ toolbar button. |

### Session peaks

Every metric carries extremes, not just the headline ones: until the detector exists, any
channel may turn out to be the discriminator, and an extreme that was never recorded cannot
be recovered after the drive.

Both directions are kept, because for several channels the **low** is the informative one:

- **Total acceleration** collapsing toward 0 g means free-fall — a dropped phone, not a
  struck vehicle. A max-only tracker records the landing spike and misses the fall that
  identifies it.
- **Per-axis** peaks are signed, not absolute. A front and a rear impact drive the same axis
  in opposite directions; collapsing to a magnitude discards which one happened.
- **Pressure** drifts slowly with weather, so the absolute value says little — the range
  between extremes is the airbag cue.

Tracked: linear g, linear X/Y/Z, total g, jerk, rotation, gyro X/Y/Z, Δv, GPS speed,
pressure, field strength.

Each appears as `▲ high` / `▼ low` chips under its live reading, and all of them together in
the **SESSION PEAKS** table at the top, with the time each high was reached. Timestamps
matter: a crash is a cluster of extremes within a few hundred milliseconds, so several
channels peaking at the same instant is itself evidence — peaks scattered across a half-hour
drive are just rough road.

⚠️ **Δv is an estimate, not a calibrated delta-V.** It integrates a noisy MEMS signal, so
bias makes it drift. Use it as a relative indicator between runs, never as an absolute
figure. It integrates the vector rather than the scalar magnitude on purpose — magnitude is
always positive, so integrating it would accumulate steadily even when the device is merely
vibrating in place.

---

## Reading the screen

Every card shows the **achieved** sample rate, not the requested one. `SensorInterval` is a
hint; Android rounds it to what the hardware supports, and a throttled or absent sensor is
the most common reason an experimental detector misses an event. The badge turns amber and
reads `stalled` when a stream has gone quiet for over a second — a sensor that stopped
reporting looks identical to a stationary one in the numbers alone.

A sensor the device does not physically have degrades its own card and leaves the rest of
the screen working. **Many phones have no barometer; an empty barometer card is normal.**

The live trace autoscales to its own window maximum (floor 0.25 g). Interesting ranges
differ by two orders of magnitude between rest (~0.05 g of hand tremor) and impact (>10 g),
so a fixed axis would render one of them as a flat line. The current ceiling is printed in
the trace's top-left corner.

---

## Architecture

```
lib/
  main.dart                     app entry, theme wiring
  models/sensor_models.dart     Vector3, RingBuffer, ChannelRate, LocationState
  services/sensor_service.dart  all stream subscriptions + derived metrics
  screens/sensor_dashboard.dart the readout
  widgets/sensor_card.dart      card, rate badge, value and axis rows
  widgets/trace_painter.dart    autoscaling live trace
  theme/app_theme.dart          palette, tabular-figure text style
```

### Two clocks, deliberately separated

Sensors are subscribed at ~50 Hz because a collision pulse lasts 100–150 ms and is simply
not visible at the 5 Hz default. The UI is a different matter: rebuilding the tree 50 times
a second drops frames and tells the reader nothing a 20 Hz redraw does not.

So **sensor events mutate fields, and a separate `Timer` calls `notifyListeners()`**. Never
call `notifyListeners` from a sensor callback.

### Bounded history

`RingBuffer` has fixed capacity. At 50 Hz a growing list would be 3,000 entries a minute on
a screen meant to be left running for a whole drive.

---

## Permissions

**Android** — `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`. COARSE is declared
alongside FINE because Android 12+ lets the user grant only the approximate tier; without
COARSE that choice denies location outright instead of degrading it. Sensor hardware is
declared `required="false"` throughout so a device without a gyroscope or barometer can
still install and run the readout.

**iOS** — `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`,
`NSMotionUsageDescription`.

The app distinguishes the two failure modes users conflate: permission refused (app-level,
fixable in app settings) versus location services switched off (device-level).

---

## Running

```bash
flutter pub get
flutter run                 # debug, on a connected device
flutter build apk --release
```

**Use a real device.** Emulators synthesise sensor data or report none at all, and the
numbers this screen exists to collect are meaningless there.

---

## Known limits

- **Mounting dominates everything.** A phone loose in a cupholder records its own flight,
  not the vehicle's. Fix the device rigidly before trusting any reading.
- No recording or export yet — readings are live only.
- No background capture; the app must be foregrounded.
- Phone-measured g is not chassis-measured g. Published airbag thresholds are measured at
  the chassis and do not transfer directly.

## Next steps

1. Session recording to CSV so runs can be compared offline.
2. Threshold calibration from recorded drives (normal driving, potholes, hard braking,
   phone drops) to establish the false-positive floor.
3. Detection logic, once the data says what the thresholds should be.
4. Alerting.
