import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/datalog_writer.dart';

void main() {
  late Directory tempDir;
  late File logFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('datalog_test_');
    logFile = File('${tempDir.path}/test_datalog.csv');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P3.3: DatalogWriter Tests', () {
    test('writes CSV header upon open and buffers rows before threshold', () async {
      final writer = DatalogWriter(
        logFile,
        bufferThreshold: 5,
        flushInterval: const Duration(seconds: 10), // long timer so no auto-flush
      );

      await writer.open();
      expect(writer.isOpen, isTrue);

      writer.addRow(const DatalogRow(
        timestampMs: 1000,
        rpm: 3200,
        boostPsi: 18.5,
        targetBoostPsi: 19.0,
        timingCyl1: 12.0,
        knockFlag: false,
        lambdaBank1: 0.85,
        stftPct: 1.5,
        iatC: 35.0,
        coolantC: 92.0,
      ));

      expect(writer.totalWrittenRows, equals(1));
      expect(writer.bufferedRows, equals(1));

      // Close should flush buffered row and close file
      await writer.close();
      expect(writer.isOpen, isFalse);

      final lines = await logFile.readAsLines();
      expect(lines.length, equals(2)); // header + 1 row
      expect(lines[0], equals(DatalogWriter.csvHeader));
      expect(lines[1], contains('1000,3200.0,18.50,19.00,12.00,0,0.850,1.50,35.0,92.0'));
    });

    test('automatically flushes when bufferThreshold is reached', () async {
      final writer = DatalogWriter(
        logFile,
        bufferThreshold: 3,
        flushInterval: const Duration(seconds: 10),
      );

      await writer.open();

      for (int i = 0; i < 2; i++) {
        writer.addRow(DatalogRow(
          timestampMs: 1000 + i * 20,
          rpm: 3000.0 + i * 100,
          boostPsi: 15.0,
          targetBoostPsi: 15.0,
          timingCyl1: 10.0,
          knockFlag: false,
          lambdaBank1: 0.88,
          stftPct: 0.0,
          iatC: 30.0,
          coolantC: 90.0,
        ));
      }
      expect(writer.bufferedRows, equals(2));

      // Adding the 3rd row triggers flush
      writer.addRow(const DatalogRow(
        timestampMs: 1040,
        rpm: 3200.0,
        boostPsi: 15.0,
        targetBoostPsi: 15.0,
        timingCyl1: 10.0,
        knockFlag: false,
        lambdaBank1: 0.88,
        stftPct: 0.0,
        iatC: 30.0,
        coolantC: 90.0,
      ));

      expect(writer.bufferedRows, equals(0));
      await writer.close();

      final lines = await logFile.readAsLines();
      expect(lines.length, equals(4)); // header + 3 rows
    });

    test('high frequency stress test: 10,000 rows buffered and flushed', () async {
      final writer = DatalogWriter(
        logFile,
        bufferThreshold: 100,
        flushInterval: const Duration(milliseconds: 200),
      );

      await writer.open();

      for (int i = 0; i < 10000; i++) {
        writer.addRow(DatalogRow(
          timestampMs: i * 10,
          rpm: 2000.0 + (i % 5000),
          boostPsi: 10.0 + (i % 15),
          targetBoostPsi: 20.0,
          timingCyl1: 8.0,
          knockFlag: i % 1000 == 0,
          lambdaBank1: 0.82,
          stftPct: 2.0,
          iatC: 40.0,
          coolantC: 95.0,
        ));
      }

      await writer.close();

      expect(writer.totalWrittenRows, equals(10000));
      final lines = await logFile.readAsLines();
      expect(lines.length, equals(10001)); // header + 10,000 rows
      expect(lines.first, equals(DatalogWriter.csvHeader));
      expect(lines.last, contains('99990,'));
    });
  });
}
