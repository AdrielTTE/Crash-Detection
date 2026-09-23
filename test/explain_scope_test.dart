import 'package:crash_detection/theme/app_theme.dart';
import 'package:crash_detection/widgets/explain_scope.dart';
import 'package:crash_detection/widgets/sensor_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The explain toggle is the whole point of the descriptions: it has to hide
/// them without hiding the readings, and show them without the readings
/// moving. These tests pin both halves.
Widget _host({required bool explain, required Widget child}) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: ExplainScope(
      explain: explain,
      child: SingleChildScrollView(child: child),
    ),
  ),
);

void main() {
  group('ExplainScope', () {
    testWidgets('defaults to false with no scope above it', (tester) async {
      late bool seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = ExplainScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, isFalse);
    });
  });

  group('ValueRow', () {
    testWidgets('hides its description when explanations are off',
        (tester) async {
      await tester.pumpWidget(
        _host(
          explain: false,
          child: const ValueRow(
            label: 'Peak linear acceleration',
            value: '1.234 g',
            description: 'Highest impact force seen since the last reset.',
          ),
        ),
      );

      expect(find.text('1.234 g'), findsOneWidget);
      expect(find.text('Peak linear acceleration'), findsOneWidget);
      expect(
        find.text('Highest impact force seen since the last reset.'),
        findsNothing,
      );
    });

    testWidgets('shows its description when explanations are on',
        (tester) async {
      await tester.pumpWidget(
        _host(
          explain: true,
          child: const ValueRow(
            label: 'Peak linear acceleration',
            value: '1.234 g',
            description: 'Highest impact force seen since the last reset.',
          ),
        ),
      );

      // The reading must survive the toggle - explanations add to the row,
      // they never replace it.
      expect(find.text('1.234 g'), findsOneWidget);
      expect(
        find.text('Highest impact force seen since the last reset.'),
        findsOneWidget,
      );
    });

    testWidgets('a row with no description renders identically either way',
        (tester) async {
      for (final explain in [true, false]) {
        await tester.pumpWidget(
          _host(
            explain: explain,
            child: const ValueRow(label: 'Longitude', value: '101.687000'),
          ),
        );
        expect(find.text('101.687000'), findsOneWidget);
      }
    });
  });

  group('SensorCard', () {
    testWidgets('purpose follows the toggle, title and unit do not',
        (tester) async {
      const purpose = 'THE PRIMARY IMPACT SIGNAL for the detector.';

      await tester.pumpWidget(
        _host(
          explain: false,
          child: const SensorCard(
            title: 'LINEAR ACCELERATION',
            unit: 'm/s²',
            accent: AppColors.linear,
            purpose: purpose,
            children: [ValueRow(label: 'Magnitude', value: '0.012 g')],
          ),
        ),
      );
      expect(find.text('LINEAR ACCELERATION'), findsOneWidget);
      expect(find.text(purpose), findsNothing);

      await tester.pumpWidget(
        _host(
          explain: true,
          child: const SensorCard(
            title: 'LINEAR ACCELERATION',
            unit: 'm/s²',
            accent: AppColors.linear,
            purpose: purpose,
            children: [ValueRow(label: 'Magnitude', value: '0.012 g')],
          ),
        ),
      );
      expect(find.text('LINEAR ACCELERATION'), findsOneWidget);
      expect(find.text(purpose), findsOneWidget);
    });

    testWidgets('an unavailable sensor shows the reason instead of readings',
        (tester) async {
      await tester.pumpWidget(
        _host(
          explain: true,
          child: const SensorCard(
            title: 'BAROMETER',
            unit: 'hPa',
            accent: AppColors.baro,
            unavailableReason: 'No barometer on this device',
            children: [ValueRow(label: 'Pressure', value: '1013.25 hPa')],
          ),
        ),
      );

      // A missing sensor must not print a stale or invented reading.
      expect(find.text('1013.25 hPa'), findsNothing);
      expect(
        find.textContaining('Not available on this device'),
        findsOneWidget,
      );
    });
  });
}
