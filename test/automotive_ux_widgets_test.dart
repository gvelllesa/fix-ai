import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/widgets/slide_to_confirm.dart';
import 'package:ai_car_diagnostics/modules/obd/widgets/link_status_bar.dart';
import 'package:ai_car_diagnostics/modules/obd/services/connection_manager.dart';

void main() {
  group('P3.4 & P3.6: Automotive UX Widgets Tests', () {
    testWidgets('SlideToConfirm displays label and blocks action when engine is running (RPM > 0)', (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlideToConfirm(
              label: 'SLIDE TO FLASH DME',
              currentRpm: 850.0, // Engine is running
              onConfirmed: () {
                confirmed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('SLIDE TO FLASH DME'), findsOneWidget);
      expect(find.textContaining('ENGINE RUNNING (850 RPM)'), findsOneWidget);

      // Attempt to drag across the track
      final gesture = await tester.startGesture(tester.getCenter(find.byType(SlideToConfirm)));
      await gesture.moveBy(const Offset(300, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(confirmed, isFalse, reason: 'Action must be blocked by RPM motion interlock');
    });

    testWidgets('SlideToConfirm blocks action when vehicle is moving (Speed > 0)', (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlideToConfirm(
              label: 'SLIDE TO WRITE VO',
              currentRpm: 0.0,
              currentSpeed: 15.0, // Vehicle moving at 15 km/h
              onConfirmed: () {
                confirmed = true;
              },
            ),
          ),
        ),
      );

      expect(find.textContaining('VEHICLE IN MOTION (15 km/h)'), findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(find.byType(SlideToConfirm)));
      await gesture.moveBy(const Offset(300, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(confirmed, isFalse, reason: 'Action must be blocked by Speed motion interlock');
    });

    testWidgets('SlideToConfirm triggers onConfirmed when slid to the end while vehicle is stationary', (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: SlideToConfirm(
                label: 'SLIDE TO FLASH DME',
                currentRpm: 0.0,
                currentSpeed: 0.0,
                onConfirmed: () {
                  confirmed = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('SLIDE TO FLASH DME'), findsOneWidget);
      expect(find.byIcon(Icons.double_arrow_rounded), findsOneWidget);

      // Drag the thumb from left to right (from thumb center ~28px to right > 240px)
      final thumbCenter = tester.getCenter(find.byIcon(Icons.double_arrow_rounded));
      final gesture = await tester.startGesture(thumbCenter);
      await gesture.moveBy(const Offset(260, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(confirmed, isTrue, reason: 'Full slide while stationary must confirm');
    });

    testWidgets('LinkStatusBar displays disconnected, adapter, and ECU states correctly', (tester) async {
      // 1. Disconnected
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkStatusBar(
              customSnapshot: ConnectionSnapshot(
                linkState: LinkState.disconnected,
              ),
            ),
          ),
        ),
      );

      expect(find.text('DISCONNECTED'), findsOneWidget);
      expect(find.text('No adapter connection detected'), findsOneWidget);

      // 2. Adapter Connected (Ignition OFF)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkStatusBar(
              customSnapshot: ConnectionSnapshot(
                linkState: LinkState.adapterOnly,
                host: '192.168.16.101',
                port: 35000,
              ),
            ),
          ),
        ),
      );

      expect(find.text('ADAPTER LINKED'), findsOneWidget);
      expect(find.textContaining('192.168.16.101:35000'), findsOneWidget);

      // 3. DME Online with Battery Voltage and VIN
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkStatusBar(
              customSnapshot: ConnectionSnapshot(
                linkState: LinkState.ecuResponding,
                activeVin: 'WBA3A5C50DF123456',
                batteryVoltage: 13.4,
                latencyMs: 12,
              ),
              flashProgress: 0.65,
              flashStage: 'Writing Blocks (0x36)',
            ),
          ),
        ),
      );

      expect(find.text('DME ONLINE • 13.4V'), findsOneWidget);
      expect(find.textContaining('WBA3A5C50DF123456'), findsOneWidget);
      expect(find.text('Writing Blocks (0x36)'), findsOneWidget);
      expect(find.text('65.0%'), findsOneWidget);
    });
  });
}
