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

### Derived metrics

| Metric | Meaning |
|---|---|
| Linear acceleration (g) | Primary impact signal. Near **0** at rest, not near 1. |
| Total acceleration (g) | Near **1** at rest. Free-fall drives it toward 0 — this is what separates a dropped phone from a struck one. |
| Jerk (g/s) | Rate of change of linear g. Distinguishes an impact from hard braking: both reach a similar peak, only one gets there fast. |
| Rotation (°/s) | A rollover appears here before it appears in the accelerometer. |
| Δv over last 1 s | Rolling trapezoidal integral of the linear-acceleration **vector**. |
| Peak hold | Session maximum for linear g, jerk and rotation. Reset with the toolbar button. |

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
