import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/config/feature_flags.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'bmw_flash_options.dart';

/// Represents a single 8-byte BMW SGBM-ID entry inside the UDS SVK (DID 0xF101) block
/// (`UNI_Flash.Program_UDS.GetXweString` / `FxxSpecificHelper.DetectCafdFromSwe`).
class SvkRecord {
  final int processClass;
  final String processClassName;
  final int sgbmId;
  final int mainVersion;
  final int subVersion;
  final int patchVersion;

  const SvkRecord({
    required this.processClass,
    required this.processClassName,
    required this.sgbmId,
    required this.mainVersion,
    required this.subVersion,
    required this.patchVersion,
  });

  String get sgbmIdHex => sgbmId.toRadixString(16).toUpperCase().padLeft(8, '0');

  /// Formatted E-Sys / ISTA SGBM identifier (e.g. `BTLD_000019DC_001_019_002`)
  String get formatted =>
      '${processClassName}_${sgbmIdHex}_'
      '${mainVersion.toString().padLeft(3, '0')}_'
      '${subVersion.toString().padLeft(3, '0')}_'
      '${patchVersion.toString().padLeft(3, '0')}';

  static String? processClassToName(int cls) {
    switch (cls) {
      case 0x01:
        return 'HWEL';
      case 0x02:
        return 'BTLD';
      case 0x03:
        return 'FLSL';
      case 0x05:
        return 'SWFL';
      case 0x06:
        return 'SWFF';
      case 0x07:
        return 'SWPF';
      case 0x08:
        return 'CAFD';
      case 0x09:
        return 'FAFP';
      case 0x0C:
        return 'GWTB';
      case 0x0D:
        return 'ENTD';
      case 0x10:
        return 'IBAD';
      default:
        return null;
    }
  }

  @override
  String toString() => formatted;
}

/// Complete ECU identification snapshot extracted via UDS DIDs
class EcuIdentity {
  final String vin;
  final String? dmeType;
  final String? hwel;
  final String? btld;
  final String? swfl;
  final String? cafd;
  final String? engineCode;
  final int? activeDiagnosticSession;
  final List<SvkRecord> svkRecords;

  const EcuIdentity({
    required this.vin,
    this.dmeType,
    this.hwel,
    this.btld,
    this.swfl,
    this.cafd,
    this.engineCode,
    this.activeDiagnosticSession,
    this.svkRecords = const [],
  });

  /// Parses raw BMW UDS SVK (DID 0xF101) payload into structured 8-byte [SvkRecord] entries.
  /// Supports:
  /// - Raw 8-byte SGBM-ID arrays (`[processClass, id0, id1, id2, id3, main, sub, patch]`)
  /// - 4-byte SVK header (`[version, progDep, countMsb, countLsb]`) + 8-byte entries
  /// - 17-byte SVK header (4-byte header + 13-byte Fingerprint) + 8-byte entries
  /// - UDS `0x62 0xF1 0x01` prefix if not yet stripped
  /// - Printable ASCII SGBM strings (`BTLD_000019DC_001_019_002`)
  static List<SvkRecord> parseSvkRecords(Uint8List svkPayload) {
    if (svkPayload.isEmpty) return const [];

    var data = svkPayload;
    if (data.length >= 3 && data[0] == 0x62 && data[1] == 0xF1 && data[2] == 0x01) {
      data = Uint8List.sublistView(data, 3);
    }

    // 1. Check if payload contains ASCII SGBM strings
    final asciiStr = String.fromCharCodes(data.where((b) => b >= 0x20 && b <= 0x7E));
    final asciiMatches = RegExp(
      r'(HWEL|BTLD|FLSL|SWFL|SWFF|CAFD|GWTB|ENTD)_([0-9A-Fa-f]{8})_(\d{3})_(\d{3})_(\d{3})',
    ).allMatches(asciiStr);
    if (asciiMatches.isNotEmpty) {
      final records = <SvkRecord>[];
      for (final m in asciiMatches) {
        final clsName = m.group(1)!.toUpperCase();
        final idVal = int.parse(m.group(2)!, radix: 16);
        final vMain = int.parse(m.group(3)!);
        final vSub = int.parse(m.group(4)!);
        final vPatch = int.parse(m.group(5)!);
        final clsCode = const {
              'HWEL': 0x01,
              'BTLD': 0x02,
              'FLSL': 0x03,
              'SWFL': 0x05,
              'SWFF': 0x06,
              'CAFD': 0x08,
              'GWTB': 0x0C,
              'ENTD': 0x0D,
            }[clsName] ??
            0x05;
        records.add(SvkRecord(
          processClass: clsCode,
          processClassName: clsName,
          sgbmId: idVal,
          mainVersion: vMain,
          subVersion: vSub,
          patchVersion: vPatch,
        ));
      }
      return records;
    }

    // 2. Binary 8-byte SGBM-ID table parsing
    // Determine exact header offset using modulo-8 alignment:
    // - 17-byte header (4B SVK header + 13B Fingerprint): (len - 17) % 8 == 0
    // - 4-byte header ([version, progDep, countMsb, countLsb]): (len - 4) % 8 == 0
    // - 0-byte header (raw 8-byte SGBM-ID entries): len % 8 == 0
    final candidateOffsets = <int>[
      if (data.length >= 25 && (data.length - 17) % 8 == 0) 17,
      if (data.length >= 12 && (data.length - 4) % 8 == 0) 4,
      if (data.length >= 8 && data.length % 8 == 0) 0,
      4,
      17,
      0,
    ];
    List<SvkRecord> bestRecords = const [];

    for (final startOffset in candidateOffsets) {
      if (startOffset >= data.length) continue;
      final current = <SvkRecord>[];
      for (int off = startOffset; off + 8 <= data.length; off += 8) {
        final cls = data[off];
        final clsName = SvkRecord.processClassToName(cls);
        if (clsName == null) continue;
        final id = (data[off + 1] << 24) |
            (data[off + 2] << 16) |
            (data[off + 3] << 8) |
            data[off + 4];
        if (id == 0 || id == 0xFFFFFFFF) continue;
        current.add(SvkRecord(
          processClass: cls,
          processClassName: clsName,
          sgbmId: id >>> 0,
          mainVersion: data[off + 5],
          subVersion: data[off + 6],
          patchVersion: data[off + 7],
        ));
      }
      if (current.length > bestRecords.length) {
        bestRecords = current;
      }
      if (bestRecords.isNotEmpty && (data.length - startOffset) % 8 == 0) {
        break;
      }
    }

    return bestRecords;
  }

  /// Parse SVK table from DID 0xF101 response and VIN
  static EcuIdentity parseFromUds({
    required String vin,
    Uint8List? svkPayload,
    int? activeSession,
  }) {
    String? dme;
    String? hwel;
    String? btld;
    String? swfl;
    String? cafd;
    String? engine;
    var records = const <SvkRecord>[];

    if (svkPayload != null && svkPayload.length >= 8) {
      dme = 'BMW-DME';
      records = parseSvkRecords(svkPayload);
      for (final rec in records) {
        switch (rec.processClassName) {
          case 'HWEL':
            hwel ??= rec.formatted;
            break;
          case 'BTLD':
            btld ??= rec.formatted;
            break;
          case 'SWFL':
            swfl ??= rec.formatted;
            break;
          case 'CAFD':
            cafd ??= rec.formatted;
            break;
        }
      }

      // Infer specific DME/TCU architecture from known BMW SGBM IDs if present
      if (btld != null) {
        if (btld.contains('000019DC') || btld.contains('000014E1')) {
          dme = 'MEVD172G';
        } else if (btld.contains('000030C1') || btld.contains('0000550F')) {
          dme = 'MG1CS003';
        } else if (btld.contains('00005D60')) {
          dme = 'MG1CS201';
        }
      }
    }

    if (vin.length >= 7) {
      final code = vin.substring(3, 7).toUpperCase();
      if (code.contains('3A5') || code.contains('1B5') || code.contains('3B5')) {
        engine = 'N55B30M0';
        dme = 'MEVD172G';
      } else if (code.contains('8B1') || code.contains('5R1') || code.contains('5U7')) {
        engine = 'B58B30O1';
        dme = 'MG1CS003';
      }
    }

    return EcuIdentity(
      vin: vin,
      dmeType: dme,
      hwel: hwel,
      btld: btld,
      swfl: swfl,
      cafd: cafd,
      engineCode: engine,
      activeDiagnosticSession: activeSession,
      svkRecords: records,
    );
  }
}

/// Pre-flight safety check result. Strict Fail-Closed implementation.
class PreFlightCheckResult {
  final bool passed;
  final double batteryVoltage;
  final bool isIgnitionOnEngineOff;
  final bool isDmeUnlocked;
  final bool isCustomRomBootloader;
  final String? vin;
  final EcuIdentity? ecuIdentity;
  final List<String> errorMessages;
  final List<String> warningMessages;

  PreFlightCheckResult({
    required this.passed,
    required this.batteryVoltage,
    required this.isIgnitionOnEngineOff,
    required this.isDmeUnlocked,
    this.isCustomRomBootloader = false,
    this.vin,
    this.ecuIdentity,
    required this.errorMessages,
    this.warningMessages = const [],
  });
}

/// Represents a validated flash memory segment with base address and binary payload
class FlashSegment {
  final int address;
  final Uint8List data;
  const FlashSegment(this.address, this.data);
}

/// Container for verified binary flash calibration images
class VerifiedFlashImage {
  final String licensedVin;
  final List<FlashSegment> segments;
  final String sha256Hex;
  final int securityLevel;

  const VerifiedFlashImage({
    required this.licensedVin,
    required this.segments,
    required this.sha256Hex,
    this.securityLevel = 0x01,
  });

  int get totalBytes => segments.fold(0, (sum, seg) => sum + seg.data.length);
}

/// Progress model for UDS Flash operations
class FlashProgress {
  final String stage;
  final double progress;
  final String message;
  final bool isError;
  final bool isComplete;

  const FlashProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.isError = false,
    this.isComplete = false,
  });
}

/// Orchestrates safe, authentic ECU Diagnostics and Calibration Management for BMW DME.
/// Strict ZERO-SIMULATION & FAIL-CLOSED vehicle safety architecture.
/// 
/// Under NO circumstances will unverified or simulated byte writes or dangerous
/// resets be sent to the DME to prevent any risk of bricking the vehicle computer.
class BmwFlashManager {
  final EnetHsfzProtocol? protocol;
  static const int dmeAddress = 0x12;

  BmwFlashManager({this.protocol});

  EnetHsfzProtocol _getActiveProto() {
    if (protocol != null && protocol!.isConnected) {
      return protocol!;
    }
    throw StateError('ENET/OBD ადაპტერი არ არის დაკავშირებული. ჯერ ჩართეთ კავშირი Connection Manager-იდან.');
  }

  /// Check if DME is already running Bootmod3 / MHD Custom ROM patched bootloader
  Future<bool> checkCustomRomInstalled() async {
    try {
      final proto = _getActiveProto();
      // Custom ROM DID 0xD400 or 0xD4FF
      final resp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0xD4, 0x00]);
      return resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x00;
    } catch (e) {
      debugPrint('[BmwFlashManager] Check custom ROM: $e');
      return false;
    }
  }

  /// Run critical pre-flight safety interlocks before any ECU programming operation.
  /// Strictly FAIL-CLOSED: Any failed read or unverified condition triggers a hard stop.
  Future<PreFlightCheckResult> runPreFlightChecks({String? requiredVin}) async {
    final errors = <String>[];
    final warnings = <String>[];
    double? batteryVoltage;
    double? engineRpm;
    double? vehicleSpeed;
    String? readVinStr;
    EcuIdentity? ecuIdentity;
    bool customRom = false;

    EnetHsfzProtocol proto;
    try {
      proto = _getActiveProto();
    } catch (e) {
      return PreFlightCheckResult(
        passed: false,
        batteryVoltage: 0.0,
        isIgnitionOnEngineOff: false,
        isDmeUnlocked: false,
        errorMessages: ['ავტომობილი არ არის დაკავშირებული ENET/OBD ადაპტერით: $e'],
      );
    }

    try {
      // 1. Read High-Precision Battery Voltage via KL30/Power supply DID 0x5815 or 0xF111
      final voltResp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0x58, 0x15], timeout: const Duration(seconds: 2));
      if (voltResp.length >= 5 && voltResp[0] == 0x62) {
        final rawVolt = (voltResp[3] << 8) | voltResp[4];
        batteryVoltage = rawVolt / 1000.0;
      } else {
        // Fallback to DID 0xF111
        final altVolt = await proto.sendUdsRequest(dmeAddress, const [0x22, 0xF1, 0x11], timeout: const Duration(seconds: 2));
        if (altVolt.length >= 5 && altVolt[0] == 0x62) {
          final rawVolt = (altVolt[3] << 8) | altVolt[4];
          batteryVoltage = rawVolt / 1000.0;
        }
      }

      // FAIL-CLOSED: Unreadable battery voltage is a hard stop
      if (batteryVoltage == null) {
        errors.add('აკუმულატორის ძაბვა ვერ წაიკითხა — ავტომობილის უსაფრთხოებისთვის ოპერაცია დაბლოკილია.');
      } else if (batteryVoltage < 12.50) {
        errors.add(
          'კრიტიკული: აკუმულატორის ძაბვაა ${batteryVoltage.toStringAsFixed(2)}V (< 12.50V). შეაერთეთ 50A+ სტაბილური დამტენი!',
        );
      } else if (batteryVoltage < 13.00) {
        warnings.add(
          'გაფრთხილება: აკუმულატორის ძაბვაა ${batteryVoltage.toStringAsFixed(2)}V. რეკომენდებულია ≥13.00V დამტენის მიერთება.',
        );
      }

      // 2. Read Engine RPM via UDS 0x22 0x20 0x00 or PID 0x5804
      final rpmResp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0x20, 0x00], timeout: const Duration(seconds: 2));
      if (rpmResp.length >= 5 && rpmResp[0] == 0x62) {
        final rawRpm = (rpmResp[3] << 8) | rpmResp[4];
        engineRpm = rawRpm / 4.0;
      } else {
        // Fallback to PID 0x5800
        final altRpm = await proto.sendUdsRequest(dmeAddress, const [0x22, 0x58, 0x00], timeout: const Duration(seconds: 2));
        if (altRpm.length >= 5 && altRpm[0] == 0x62) {
          final rawRpm = (altRpm[3] << 8) | altRpm[4];
          engineRpm = rawRpm / 4.0;
        }
      }

      // FAIL-CLOSED: Engine must be confirmed completely OFF
      if (engineRpm == null) {
        errors.add('ძრავის ბრუნვის (RPM) დადასტურება ვერ მოხერხდა. ძრავი უნდა იყოს გამორთული (ანთება KL15 ON).');
      } else if (engineRpm > 20.0) {
        errors.add('საფრთხე: ძრავი ამჟამად მუშაობს (${engineRpm.toInt()} RPM). გამორთეთ ძრავი და დატოვეთ მხოლოდ ანთება ჩართული!');
      }

      // 3. Read Vehicle Speed via UDS 0x22 0x58 0x0D
      final speedResp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0x58, 0x0D], timeout: const Duration(seconds: 2));
      if (speedResp.length >= 4 && speedResp[0] == 0x62) {
        vehicleSpeed = speedResp[3] * 1.25;
      }

      if (vehicleSpeed == null) {
        errors.add('ავტომობილის სიჩქარის (Speed) დადასტურება ვერ მოხერხდა. ავტომობილი აუცილებლად უნდა იდგეს.');
      } else if (vehicleSpeed > 0.0) {
        errors.add('საფრთხე: ავტომობილი მოძრაობს (${vehicleSpeed.toStringAsFixed(1)} კმ/სთ). ავტომობილი აუცილებლად უნდა იდგეს!');
      }

      // 4. Read Vehicle VIN via DID 0xF190
      readVinStr = await proto.readVin(dmeAddress);
      if (readVinStr == null || readVinStr.length < 17) {
        errors.add('VIN კოდი ვერ წაიკითხა DME-დან — კომუნიკაციის შეცდომა.');
      } else if (requiredVin != null && readVinStr != requiredVin) {
        errors.add('DME-ს VIN კოდი ($readVinStr) არ ემთხვევა მოთხოვნილ ლიცენზირებულ VIN-ს ($requiredVin).');
      }

      // 5. Read SVK (0x22 0xF1 0x01) and Active Diagnostic Session (0x22 0xF1 0x86)
      final svkResp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0xF1, 0x01], timeout: const Duration(seconds: 2));
      final sessResp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0xF1, 0x86], timeout: const Duration(seconds: 2));
      final activeSession = (sessResp.length >= 4 && sessResp[0] == 0x62) ? sessResp[3] : null;

      if (readVinStr != null && readVinStr.length >= 17) {
        ecuIdentity = EcuIdentity.parseFromUds(
          vin: readVinStr,
          svkPayload: svkResp.isNotEmpty ? svkResp : null,
          activeSession: activeSession,
        );
      }

      // 6. Check Custom ROM status
      customRom = await checkCustomRomInstalled();

    } catch (e) {
      debugPrint('[BmwFlashManager] Pre-flight exception: $e');
      errors.add('Pre-flight დიაგნოსტიკის შეცდომა: $e');
    }

    final isIgnitionOnEngineOff = (engineRpm != null && engineRpm <= 20.0);

    return PreFlightCheckResult(
      passed: errors.isEmpty,
      batteryVoltage: batteryVoltage ?? 0.0,
      isIgnitionOnEngineOff: isIgnitionOnEngineOff,
      isDmeUnlocked: customRom,
      isCustomRomBootloader: customRom,
      vin: readVinStr,
      ecuIdentity: ecuIdentity,
      errorMessages: errors,
      warningMessages: warnings,
    );
  }

  /// Emergency Recovery Session Management:
  /// Rescues DME communication safely WITHOUT issuing dangerous hard resets (0x11 0x01)
  /// or DTC erasures (0x14 FF FF FF) which could leave an erased or partially written
  /// ECU in a permanently bricked bootloader.
  Future<bool> recoverDmeSession() async {
    try {
      EnetHsfzProtocol proto;
      if (protocol != null) {
        proto = protocol!;
        if (!proto.isConnected &&
            EnetHsfzProtocol.lastConnectedHost != null &&
            EnetHsfzProtocol.lastConnectedPort != null) {
          await proto.connect(
            host: EnetHsfzProtocol.lastConnectedHost!,
            port: EnetHsfzProtocol.lastConnectedPort!,
          );
        }
      } else {
        proto = _getActiveProto();
      }

      if (!proto.isConnected) return false;
      debugPrint('[BmwFlashManager] Initiating safe DME Recovery Session...');

      // 1. TesterPresent 0x3E 0x00 to keep current session alive and check responsiveness
      await proto.sendUdsRequest(dmeAddress, const [0x3E, 0x00], timeout: const Duration(seconds: 2));

      // 2. Read ActiveDiagnosticSessionDataIdentifier (0x22 0xF1 0x86)
      final sessResp = await proto.sendUdsRequest(
        dmeAddress,
        const [0x22, 0xF1, 0x86],
        timeout: const Duration(seconds: 2),
      );
      final activeSession = (sessResp.length >= 4 && sessResp[0] == 0x62) ? sessResp[3] : null;
      debugPrint('[BmwFlashManager] Active ECU diagnostic session: ${activeSession != null ? "0x${activeSession.toRadixString(16)}" : "unknown"}');

      // 3. Restore normal bus communication via functional broadcast (0x28 0x00 0x01)
      await proto.sendFunctional(const [0x28, 0x00, 0x01]);

      // 4. Re-enable DTC recording via functional broadcast (0x85 0x01)
      await proto.sendFunctional(const [0x85, 0x01]);

      // 5. Verify DME is alive via Active Session or standard VIN read (0x22 0xF1 0x90)
      // NOTE: Never issue 0x14 FF FF FF or 0x11 0x01 here!
      if (activeSession != null) {
        return true;
      }
      final vinResp = await proto.sendUdsRequest(dmeAddress, const [0x22, 0xF1, 0x90], timeout: const Duration(seconds: 2));
      final isAlive = vinResp.isNotEmpty && vinResp[0] == 0x62;

      debugPrint('[BmwFlashManager] Safe Recovery Result: ${isAlive ? "COMMUNICATION RESTORED" : "ECU REQUIRES IGNITION CYCLE"}');
      return isAlive;
    } catch (e) {
      debugPrint('[BmwFlashManager] Error during safe recovery session: $e');
      return false;
    }
  }

  /// Safe execution of DME operations.
  ///
  /// Gated by [FeatureFlags.kFlashEnabled] until HIL/bench verification.
  Stream<Map<String, dynamic>> executeFlash({
    required BmwFlashOptions options,
    VerifiedFlashImage? flashImage,
    bool forceAllowWhenFlaggedForTest = false,
  }) async* {
    if (!FeatureFlags.kFlashEnabled && !forceAllowWhenFlaggedForTest) {
      yield {
        'step': 'SAFETY_LOCK',
        'progress': 0.0,
        'message':
            'ECU Flashing დროებით გამორთულია უსაფრთხოების რეჟიმით (HIL/bench ვერიფიკაციამდე). უსაფრთხოების ბლოკი აქტიურია.',
        'success': false,
      };
      return;
    }

    yield {
      'step': 'PRE_FLIGHT',
      'progress': 0.05,
      'message': 'ავტომობილის უსაფრთხოების interlock-ების შემოწმება (ძაბვა, ძრავი, VIN)...',
    };

    final preFlight = await runPreFlightChecks(requiredVin: flashImage?.licensedVin);
    if (!preFlight.passed) {
      yield {
        'step': 'FAILED',
        'progress': 0.0,
        'message': preFlight.errorMessages.join('\n'),
        'success': false,
      };
      return;
    }

    // Safety Interlock: If user requested full bootloader flash without a verified flash container
    if (flashImage == null) {
      // If DME has Custom ROM installed, we can safely write configuration vectors (0x2E 0xD4FE)
      if (preFlight.isCustomRomBootloader) {
        yield {
          'step': 'CUSTOM_ROM_SYNC',
          'progress': 0.30,
          'message': 'DME Custom ROM იდენტიფიცირებულია. პარამეტრების ვექტორის ჩაწერა (DID 0xD4FE)...',
        };

        try {
          final proto = _getActiveProto();
          // Enter Extended Session 0x10 0x03
          await proto.sendUdsRequest(dmeAddress, const [0x10, 0x03]);
          final tableBytes = options.serializeCustomRomBinaryTable();
          final writeResp = await proto.sendUdsRequest(dmeAddress, [0x2E, 0xD4, 0xFE, ...tableBytes]);

          if (writeResp.isNotEmpty && writeResp[0] == 0x6E) {
            yield {
              'step': 'COMPLETE',
              'progress': 1.0,
              'message': 'Custom ROM პარამეტრები წარმატებით განახლდა (DID 0xD4FE დადასტურდა DME-ს მიერ)!',
              'success': true,
            };
          } else {
            yield {
              'step': 'FAILED',
              'progress': 0.0,
              'message': 'DME-მ უარყო DID 0xD4FE ჩაწერა (NRC: ${writeResp.length >= 3 ? "0x${writeResp[2].toRadixString(16)}" : "უცნობი"}).',
              'success': false,
            };
          }
        } catch (e) {
          yield {
            'step': 'FAILED',
            'progress': 0.0,
            'message': 'Custom ROM პარამეტრების ჩაწერის შეცდომა: $e',
            'success': false,
          };
        }
        return;
      }

      // Hard stop to prevent bricking factory DME
      yield {
        'step': 'SAFETY_LOCK',
        'progress': 0.0,
        'message': 'უსაფრთხოების ბლოკი: ქარხნული DME-ს სრული Flash წერა მოითხოვს ავტორიზებულ HSM Seed-Key-სა და ვერიფიცირებულ Flash Image-ს.\n\nავტომობილის კომპიუტერის დაზიანების (Brick) თავიდან ასაცილებლად, არაავტორიზებული ან სიმულირებული ფლეში დაბლოკილია!\n\nდიაგნოსტიკა, სერვისული ფუნქციები, აქტუატორების ტესტები და FDL კოდირება სრულად მუშაა და უსაფრთხოა.',
        'success': false,
      };
      return;
    }

    // Authentic UDS Flash Session with verified container
    yield* _executeAuthenticFlashSession(flashImage);
  }

  /// Authentic ISO 14229-1 Flash Transfer Session using verified image segments
  Stream<Map<String, dynamic>> _executeAuthenticFlashSession(VerifiedFlashImage image) async* {
    Timer? testerPresentTimer;
    final proto = _getActiveProto();

    try {
      yield {'step': 'SESSION_EXTENDED', 'progress': 0.08, 'message': 'Extended Diagnostic Session (0x10 0x03)...'};
      final sessResp = await proto.sendUdsRequest(dmeAddress, const [0x10, 0x03]);
      if (sessResp.isEmpty || sessResp[0] != 0x50) {
        throw Exception('Extended Session უარყოფილია ECU-ს მიერ');
      }

      // Functional bus silencing to prevent secondary ECUs from logging bus faults
      yield {'step': 'BUS_SILENCE', 'progress': 0.12, 'message': 'Functional Bus Silence (0x85 0x82 & 0x28 0x81)...'};
      await proto.sendFunctional(const [0x85, 0x82]);
      await proto.sendFunctional(const [0x28, 0x81, 0x01]);

      yield {'step': 'SESSION_PROG', 'progress': 0.16, 'message': 'Programming Session (0x10 0x02)...'};
      final progResp = await proto.sendUdsRequest(dmeAddress, const [0x10, 0x02], p2Star: const Duration(seconds: 5));
      if (progResp.isEmpty || progResp[0] != 0x50) {
        throw Exception('Programming Session (0x10 0x02) უარყოფილია ECU-ს მიერ');
      }

      // Start periodic TesterPresent (0x3E 0x80) keepalive
      testerPresentTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        proto.sendFireAndForget(dmeAddress, const [0x3E, 0x80]);
      });

      final totalBytes = image.totalBytes;
      var totalWritten = 0;

      for (int s = 0; s < image.segments.length; s++) {
        final seg = image.segments[s];

        // 1. Request Download (0x34)
        yield {
          'step': 'DOWNLOAD_REQ',
          'progress': 0.20 + (0.70 * (totalWritten / totalBytes)),
          'message': 'Request Download სექტორზე 0x${seg.address.toRadixString(16)}...',
        };

        final addrBytes = [
          (seg.address >> 24) & 0xFF,
          (seg.address >> 16) & 0xFF,
          (seg.address >> 8) & 0xFF,
          seg.address & 0xFF,
        ];
        final lenBytes = [
          (seg.data.length >> 24) & 0xFF,
          (seg.data.length >> 16) & 0xFF,
          (seg.data.length >> 8) & 0xFF,
          seg.data.length & 0xFF,
        ];

        final dlResp = await proto.sendUdsRequest(
          dmeAddress,
          [0x34, 0x00, 0x44, ...addrBytes, ...lenBytes],
          timeout: const Duration(seconds: 4),
        );

        if (dlResp.isEmpty || dlResp[0] != 0x74) {
          throw Exception('RequestDownload (0x34) უარყოფილია ECU-ს მიერ (სექტორი 0x${seg.address.toRadixString(16)})');
        }

        // Parse maxNumberOfBlockLength from ECU response
        final lenFmt = (dlResp[1] >> 4) & 0x0F;
        var maxBlock = 0;
        for (var i = 0; i < lenFmt; i++) {
          maxBlock = (maxBlock << 8) | dlResp[2 + i];
        }
        final chunkSize = (maxBlock > 2) ? maxBlock - 2 : 254;

        // 2. Transfer Data (0x36) block by block
        var bsc = 1;
        for (var offset = 0; offset < seg.data.length; offset += chunkSize) {
          final end = (offset + chunkSize).clamp(0, seg.data.length);
          final chunkData = seg.data.sublist(offset, end);
          final transferReq = [0x36, bsc, ...chunkData];

          final trResp = await proto.sendUdsRequest(dmeAddress, transferReq, timeout: const Duration(seconds: 3));
          if (trResp.isEmpty || trResp[0] != 0x76 || trResp[1] != bsc) {
            throw Exception('TransferData (0x36) ბლოკი $bsc უარყოფილია');
          }

          totalWritten += (end - offset);
          bsc = (bsc + 1) & 0xFF; // Wrap 0xFF -> 0x00 per ISO 14229

          yield {
            'step': 'TRANSFER_DATA',
            'progress': 0.20 + (0.70 * (totalWritten / totalBytes)),
            'message': 'მონაცემების ჩაწერა: ${(totalWritten * 100 ~/ totalBytes)}% ($totalWritten / $totalBytes ბაიტი)...',
          };
        }

        // 3. Request Transfer Exit (0x37)
        final exitResp = await proto.sendUdsRequest(dmeAddress, const [0x37], timeout: const Duration(seconds: 3));
        if (exitResp.isEmpty || exitResp[0] != 0x77) {
          throw Exception('RequestTransferExit (0x37) უარყოფილია');
        }
      }

      // 4. Verify Dependencies / Checksum (0x31 0x01 0xFF 0x01)
      yield {'step': 'CHECKSUM', 'progress': 0.94, 'message': 'ECU Checksum & Signature დადასტურება...'};
      final chkResp = await proto.sendUdsRequest(
        dmeAddress,
        const [0x31, 0x01, 0xFF, 0x01],
        p2Star: const Duration(seconds: 30),
      );
      if (chkResp.isEmpty || chkResp[0] != 0x71) {
        throw Exception('DME-მ CRC32/Signature უარყო');
      }

      testerPresentTimer.cancel();

      // 5. Hard Reset (0x11 0x01) — only executed AFTER checksum verified
      yield {'step': 'RESET', 'progress': 0.98, 'message': 'DME გადატვირთვა და კომუნიკაციის აღდგენა...'};
      await proto.sendUdsRequest(dmeAddress, const [0x11, 0x01]);
      await Future.delayed(const Duration(seconds: 3));

      await proto.sendFunctional(const [0x28, 0x80, 0x01]); // Restore communication
      await proto.sendFunctional(const [0x85, 0x81]);       // Enable DTCs

      yield {
        'step': 'COMPLETE',
        'progress': 1.0,
        'message': 'Flash სესია წარმატებით დასრულდა და დადასტურდა DME-ს მიერ!',
        'success': true,
      };

    } catch (e) {
      testerPresentTimer?.cancel();
      debugPrint('[BmwFlashManager] Authentic flash error: $e. Initiating safe recovery...');
      await recoverDmeSession();
      yield {
        'step': 'FAILED',
        'progress': 0.0,
        'message': 'Flash პროცესი შეწყდა უსაფრთხოების მიზნით: $e',
        'success': false,
      };
    } finally {
      testerPresentTimer?.cancel();
    }
  }
}
