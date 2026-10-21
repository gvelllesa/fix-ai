import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_fault_diagnostic_engine.dart';

void main() {
  late BmwFaultDiagnosticEngine engine;

  setUpAll(() {
    final f = File('assets/offline_db/bmw_fault_knowledge_base.json');
    expect(f.existsSync(), isTrue, reason: 'run scripts/offline_etl/build_bmw_fault_kb.py');
    engine = BmwFaultDiagnosticEngine.forTest()..loadFromJsonString(f.readAsStringSync());

    final stdFile = File('assets/offline_db/standard_dtc_ka.json');
    if (stdFile.existsSync()) {
      engine.loadStandardDtcFromJsonString(stdFile.readAsStringSync());
    }
  });

  group('DTC normalisation', () {
    test('extracts BMW hex from scanner string', () {
      expect(BmwFaultDiagnosticEngine.normalizeDtc('P2136 (213601) [Confirmed]'), '213601');
    });
    test('plain / 0x-prefixed 6 hex', () {
      expect(BmwFaultDiagnosticEngine.normalizeDtc('030215'), '030215');
      expect(BmwFaultDiagnosticEngine.normalizeDtc('0x030215'), '030215');
      expect(BmwFaultDiagnosticEngine.normalizeDtc('P0300'), 'P0300');
      expect(BmwFaultDiagnosticEngine.normalizeDtc('U0100'), 'U0100');
      expect(BmwFaultDiagnosticEngine.normalizeDtc('xyz'), isNull);
    });
  });

  group('Real X4 F26 codes resolve to OFFICIAL factory text (not guesses)', () {
    test('DME 0x12 / 213601 = Powermanagement: Ruhestromverletzung', () {
      final r = engine.explain(0x12, 'P2136 (213601) [Confirmed]');
      expect(r.isKnown, isTrue);
      expect(r.factoryTexts.any((t) => t.text.contains('Ruhestromverletzung')), isTrue);
      expect(r.factoryTexts.any((t) => t.variants.contains('mevd1724')), isTrue);
      expect(r.glossary.any((g) => g.term == 'Ruhestrom'), isTrue);
    });

    test('FZD 0x56 / 030215 = SHD: ungültige Kennlinie, keine Normierung vorhanden', () {
      final r = engine.explain(0x56, 'P0302 (030215) [Active]');
      expect(r.isKnown, isTrue);
      expect(r.factoryTexts.any((t) => t.text == 'SHD: ungültige Kennlinie, keine Normierung vorhanden'), isTrue);
      expect(r.factoryTexts.any((t) => t.variants.contains('fzd_f15')), isTrue);
    });

    test('FZD 0x56 / 801A4A = Diebstahlwarnanlage: Neigungsgeber und Innenraumschutz deaktiviert', () {
      final r = engine.explain(0x56, 'B001A (801A4A) [Confirmed]');
      expect(r.isKnown, isTrue);
      expect(r.factoryTexts.any((t) => t.text.contains('Neigungsgeber und Innenraumschutz deaktiviert')), isTrue);
      // The fzd3 variant words it differently -> engine must NOT claim agreement.
      expect(r.variantsAgree, isFalse);
    });

    test('0x78 is IHKA (KIS), E7144D = invalid received signal', () {
      final r = engine.explain(0x78, 'U2714 (E7144D) [Confirmed]');
      expect(r.isKnown, isTrue);
      expect(r.factoryTexts.every((t) => t.family == 'ihka'), isTrue);
      expect(r.factoryTexts.any((t) => t.text.contains('ungültig empfangen')), isTrue);
    });

    test('0x1C is ICM (KIS), 482793 = Höhenstandssensor vorn links außerhalb Spezifikation', () {
      final r = engine.explain(0x1C, 'C0827 (482793) [Confirmed]');
      expect(r.isKnown, isTrue);
      expect(r.factoryTexts.single.family, 'icm');
      expect(r.factoryTexts.single.text, contains('Höhenstandssensoren'));
    });

    test('0x6D is SMFA, 802A1E = Keine Sitzverstellung wegen Motorstartbedingung', () {
      final r = engine.explain(0x6D, 'B002A (802A1E) [Confirmed]');
      expect(r.isKnown, isTrue);
      expect(r.explanationKa, contains('სავარძლის'));
      expect(r.repairStepsKa.isNotEmpty, isTrue);
    });
  });

  group('Zero-hallucination behaviour', () {
    test('unknown code returns empty result, never a guess', () {
      final r = engine.explain(0x56, 'ZZ (FFFFFE) [Active]');
      expect(r.isKnown, isFalse);
      expect(r.factoryTexts, isEmpty);
      expect(r.unknownMessageKa, contains('არ იგონებს'));
    });

    test('same hex on a different ECU is not cross-matched', () {
      // E7144D exists for IHKA (0x78) only; must be unknown on FZD (0x56)
      expect(engine.explain(0x56, 'E7144D').isKnown, isFalse);
    });

    test('unknown ECU address returns unknown', () {
      expect(engine.explain(0xEE, '213601').isKnown, isFalse);
    });

    test('lookup is fast (<5 ms)', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        engine.explain(0x12, '213601');
      }
      sw.stop();
      expect(sw.elapsedMilliseconds / 100, lessThan(5));
    });
  });

  test('Standard SAE OBD-II DTC resolves to Georgian explanation and repair steps', () {
    final r = engine.explain(0x12, 'P0300');
    expect(r.isKnown, isTrue);
    expect(r.titleEn.contains('Misfire'), isTrue);
    expect(r.explanationKa.contains('აალება'), isTrue);
    expect(r.symptomsKa.isNotEmpty, isTrue);
    expect(r.repairStepsKa.isNotEmpty, isTrue);
    expect(r.severity, 'CRITICAL');
    expect(r.safeToDrive, isFalse);
  });

  test('knowledge base metadata sanity', () {
    expect(engine.metadata['prg_files_scanned'], 1420);
    expect(engine.metadata['family_code_entries'] as int, greaterThan(100000));
  });
}
