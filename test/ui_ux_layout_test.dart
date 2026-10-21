import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/auth/screens/sign_in_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/screens/ecu_scan_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/screens/service_functions_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/screens/coding_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/screens/flash_tuning_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/screens/live_telemetry_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/screens/xdrive_control_screen.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_fault_diagnostic_engine.dart';

/// Test in-memory protocol harness for UI widget rendering
class UiTestProtocol extends EnetHsfzProtocol {
  @override
  bool get isConnected => true;

  @override
  Future<bool> connect({
    String host = '127.0.0.1',
    int port = 6801,
    bool? useDoip,
    Duration timeout = const Duration(seconds: 4),
  }) async => true;

  @override
  Future<Uint8List?> sendUdsAndAwait(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(seconds: 2),
    Duration p2Star = const Duration(seconds: 10),
    int maxPending = 60,
  }) async {
    // Return standard positive session response
    if (udsPayload.isNotEmpty && udsPayload[0] == 0x10) {
      return Uint8List.fromList([0x50, udsPayload.length > 1 ? udsPayload[1] : 0x01, 0x00, 0x32, 0x01, 0xF4]);
    }
    return Uint8List.fromList([0x62, 0xF1, 0x90, 0x57, 0x42, 0x41]);
  }
}

Widget buildTestableScreen(Widget screen, {required Size size, double textScale = 1.0}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: screen,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    BmwFaultDiagnosticEngine.instance.loadFromJsonString(
      '{"metadata": {}, "texts": [], "families": {}, "address_index": {}}',
    );
  });
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };
  final protocol = UiTestProtocol();

  group('UI/UX Layout & Overflow Testing across Screen Sizes', () {
    const screenSizes = [
      Size(360, 640), // Compact mobile (e.g., small Android)
      Size(390, 844), // Standard mobile (e.g., iPhone 13/14/15, Pixel 7)
      Size(412, 915), // Large mobile (e.g., Galaxy S23 Ultra, Pixel 8 Pro)
    ];

    for (final size in screenSizes) {
      testWidgets('SignInScreen renders cleanly at ${size.width}x${size.height} (1.0x & 1.25x scale)', (tester) async {
        // Test standard 1.0x
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(const SignInScreen(), size: size, textScale: 1.0));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'SignInScreen should not overflow at ${size.width}x${size.height}');

        // Test with 1.25x accessibility text scale
        await tester.pumpWidget(buildTestableScreen(const SignInScreen(), size: size, textScale: 1.25));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'SignInScreen should not overflow with 1.25x text scaling');
      });

      testWidgets('EcuScanScreen renders cleanly at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(EcuScanScreen(activeProtocol: protocol), size: size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'EcuScanScreen should not overflow at ${size.width}x${size.height}');
      });

      testWidgets('ServiceFunctionsScreen renders cleanly at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(ServiceFunctionsScreen(activeProtocol: protocol), size: size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'ServiceFunctionsScreen should not overflow at ${size.width}x${size.height}');
      });

      testWidgets('CodingScreen renders cleanly at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(CodingScreen(activeProtocol: protocol), size: size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'CodingScreen should not overflow at ${size.width}x${size.height}');
      });

      testWidgets('FlashTuningScreen renders cleanly at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(FlashTuningScreen(activeProtocol: protocol), size: size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'FlashTuningScreen should not overflow at ${size.width}x${size.height}');
      });

      testWidgets('LiveTelemetryScreen renders cleanly at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(LiveTelemetryScreen(activeProtocol: protocol), size: size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'LiveTelemetryScreen should not overflow at ${size.width}x${size.height}');
      });

      testWidgets('XDriveControlScreen renders cleanly at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableScreen(XDriveControlScreen(activeProtocol: protocol), size: size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'XDriveControlScreen should not overflow at ${size.width}x${size.height}');
      });
    }
  });
}
