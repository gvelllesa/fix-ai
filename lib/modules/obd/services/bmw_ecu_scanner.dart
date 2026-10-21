import 'dart:async';
import 'package:flutter/foundation.dart';
import 'protocols/enet_hsfz_protocol.dart';

/// ISTA ECU Reset Control Sub-functions (ISO 14229 UDS Service 0x11 Reset Steuergerät)
enum EcuResetType {
  hardReset(0x01, label: 'Hard Reset', description: 'Simulates complete power interruption (cold boot)'),
  keyOffOnReset(0x02, label: 'Key Off/On Reset', description: 'Simulates ignition key cycle (KL15 toggle)'),
  softReset(0x03, label: 'Soft Reset', description: 'Restarts ECU application software without hardware power cycle');

  final int subFunction;
  final String label;
  final String description;

  const EcuResetType(this.subFunction, {required this.label, required this.description});
}

/// Extended Freeze Frame Environmental Record (UDS 0x19 0x04)
/// Decodes live sensor parameters captured at the exact moment a DTC was registered.
class DtcFreezeFrame {
  final int? mileageKm;          // Vehicle Odometer at freeze moment (km)
  final int? engineRpm;          // Engine speed (RPM)
  final double? coolantTempC;    // Engine coolant temperature (°C)
  final double? railPressureBar; // Fuel rail / injection pressure (bar)
  final double? batteryVoltage;  // System supply voltage (V)
  final int? faultFrequency;     // Number of fault occurrences
  final Map<String, dynamic> rawDids;
  final Uint8List rawSnapshotBytes;

  const DtcFreezeFrame({
    this.mileageKm,
    this.engineRpm,
    this.coolantTempC,
    this.railPressureBar,
    this.batteryVoltage,
    this.faultFrequency,
    this.rawDids = const {},
    required this.rawSnapshotBytes,
  });

  String get summary {
    final parts = <String>[];
    if (mileageKm != null) parts.add('$mileageKm km');
    if (engineRpm != null) parts.add('$engineRpm RPM');
    if (coolantTempC != null) parts.add('${coolantTempC!.toStringAsFixed(1)}°C');
    if (railPressureBar != null) parts.add('${railPressureBar!.toStringAsFixed(1)} bar');
    if (batteryVoltage != null) parts.add('${batteryVoltage!.toStringAsFixed(2)}V');
    return parts.isEmpty ? 'Snapshot data recorded' : parts.join(' | ');
  }
}

/// BMW Shadow Memory DTC (Infospeicher)
/// Captures silent shadow faults (tuner flags, flap disconnects, minor misfires)
/// that do NOT illuminate Check Engine Light (MIL).
class ShadowDtcRecord {
  final int ecuAddress;
  final String ecuName;
  final String hexCode;           // Raw 6-character hex (e.g. "138102")
  final String standardDtc;       // Standard OBD format (e.g. "P1381")
  final String description;       // EDIABAS/ISTA factory description
  final int statusByte;           // Raw UDS status byte
  final String statusDescription; // Human-readable status description
  final DtcFreezeFrame? freezeFrame;
  final DateTime timestamp;

  ShadowDtcRecord({
    required this.ecuAddress,
    required this.ecuName,
    required this.hexCode,
    required this.standardDtc,
    required this.description,
    required this.statusByte,
    required this.statusDescription,
    this.freezeFrame,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// BMW ECU Hardware / Software Identification (UDS ReadDataByIdentifier DIDs 0xF187..0xF190)
class EcuIdentification {
  final int ecuAddress;
  final String ecuName;
  final String partNumber;    // DID 0xF187 (7-digit factory Sachnummer)
  final String hwelVersion;   // DID 0xF188 (Hardware version)
  final String swflVersion;   // DID 0xF189 (Software Application version)
  final String codingIndex;   // DID 0xF18B (Coding Index)
  final String vin;           // DID 0xF190 (Vehicle Identification Number)
  final Map<String, dynamic> rawDids;

  const EcuIdentification({
    required this.ecuAddress,
    required this.ecuName,
    required this.partNumber,
    required this.hwelVersion,
    required this.swflVersion,
    required this.codingIndex,
    required this.vin,
    this.rawDids = const {},
  });

  Map<String, dynamic> toJson() => {
    'ecuAddress': '0x${ecuAddress.toRadixString(16).toUpperCase()}',
    'ecuName': ecuName,
    'partNumber': partNumber,
    'hwelVersion': hwelVersion,
    'swflVersion': swflVersion,
    'codingIndex': codingIndex,
    'vin': vin,
  };
}

/// I/M Emissions Inspection Readiness Monitor Status (SAE J1979 / ISO 15031-5 / CARB OBD-II)
enum MonitorStatus {
  passed,       // Ready / Completed inspection test
  failed,       // Test failed / Fault active
  incomplete,   // Not ready / Drive cycle test incomplete
  unsupported,  // Not supported by this engine / configuration
}

/// Single Emissions Readiness Subsystem Monitor
class EmissionsMonitor {
  final String id;
  final String name;
  final String description;
  final MonitorStatus status;
  final bool isSupported;
  final bool isComplete;

  const EmissionsMonitor({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.isSupported,
    required this.isComplete,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'status': status.name,
    'isSupported': isSupported,
    'isComplete': isComplete,
  };
}

/// Aggregated Emissions Readiness Test Result (OBD-II Mode 01 PID 01 & UDS DID 0xF401)
class EmissionsReadinessResult {
  final bool milOn;
  final int dtcCount;
  final List<EmissionsMonitor> monitors;
  final Uint8List rawBytes;
  final DateTime timestamp;

  const EmissionsReadinessResult({
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
    required this.rawBytes,
    required this.timestamp,
  });

  bool get isReady =>
      !milOn &&
      monitors
          .where((m) => m.isSupported)
          .every((m) => m.status == MonitorStatus.passed);

  int get passedCount =>
      monitors.where((m) => m.status == MonitorStatus.passed).length;

  int get incompleteCount =>
      monitors.where((m) => m.status == MonitorStatus.incomplete || m.status == MonitorStatus.failed).length;

  int get unsupportedCount =>
      monitors.where((m) => m.status == MonitorStatus.unsupported).length;

  EmissionsMonitor? getMonitor(String id) {
    try {
      return monitors.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'milOn': milOn,
    'dtcCount': dtcCount,
    'isReady': isReady,
    'passedCount': passedCount,
    'incompleteCount': incompleteCount,
    'unsupportedCount': unsupportedCount,
    'monitors': monitors.map((m) => m.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
  };
}

class EcuInfo {
  final int address;
  final String name;
  final String description;
  bool isResponding = false;
  List<String> faultCodes = [];
  List<ShadowDtcRecord> shadowFaultCodes = [];
  Map<String, DtcFreezeFrame> freezeFrames = {};
  EcuIdentification? identification;

  EcuInfo({
    required this.address,
    required this.name,
    required this.description,
    this.isResponding = false,
    List<String>? faultCodes,
    List<ShadowDtcRecord>? shadowFaultCodes,
    Map<String, DtcFreezeFrame>? freezeFrames,
    this.identification,
  })  : faultCodes = faultCodes ?? [],
        shadowFaultCodes = shadowFaultCodes ?? [],
        freezeFrames = freezeFrames ?? {};

  int get totalFaultsCount => faultCodes.length + shadowFaultCodes.length;
}

class DiagnosticScanResult {
  final String vin;
  final String chassis;
  final List<EcuInfo> ecuTopology;
  final int totalFaults;
  final int totalShadowFaults;
  final List<ShadowDtcRecord> allShadowFaults;
  final DateTime timestamp;

  DiagnosticScanResult({
    required this.vin,
    required this.chassis,
    required this.ecuTopology,
    required this.totalFaults,
    this.totalShadowFaults = 0,
    this.allShadowFaults = const [],
    required this.timestamp,
  });

  List<String> getAllFaultCodes() {
    final list = <String>[];
    for (final ecu in ecuTopology) {
      if (ecu.isResponding && ecu.faultCodes.isNotEmpty) {
        list.addAll(ecu.faultCodes.map((fc) => '${ecu.name}: $fc'));
      }
    }
    return list;
  }

  List<ShadowDtcRecord> getAllShadowFaults() {
    final list = <ShadowDtcRecord>[];
    for (final ecu in ecuTopology) {
      if (ecu.isResponding && ecu.shadowFaultCodes.isNotEmpty) {
        list.addAll(ecu.shadowFaultCodes);
      }
    }
    return list;
  }
}

class BmwEcuScanner {
  final EnetHsfzProtocol protocol;

  BmwEcuScanner({required this.protocol});

  /// Factory 32-Module BMW F-Series / E-Series ECU Topology
  static List<EcuInfo> getDefaultFSeriesTopology() {
    return [
      EcuInfo(address: 0x12, name: 'DME', description: 'Digital Motor Electronics (N55/B58/S55 Engine ECU)'),
      EcuInfo(address: 0x18, name: 'EGS', description: 'Electronic Transmission Control (ZF 8HP / 7-DCT Gearbox)'),
      EcuInfo(address: 0x19, name: 'VTG', description: 'Transfer Box / xDrive All-Wheel Drive Module'),
      EcuInfo(address: 0x17, name: 'EKP', description: 'Electronic Fuel Pump Control Module'),
      EcuInfo(address: 0x10, name: 'ZGW', description: 'Central Gateway Module'),
      EcuInfo(address: 0x40, name: 'FEM/BDC', description: 'Front Electronic / Body Domain Controller'),
      EcuInfo(address: 0x29, name: 'DSC', description: 'Dynamic Stability Control / ABS / Traction'),
      EcuInfo(address: 0x30, name: 'EPS', description: 'Electronic Power Steering'),
      EcuInfo(address: 0x60, name: 'KOMBI', description: 'Instrument Cluster Display'),
      EcuInfo(address: 0x63, name: 'HU_NBT', description: 'Headunit NBT/EVO Navigation & Infotainment'),
      EcuInfo(address: 0x6D, name: 'SMFA', description: 'Seat Module Driver / Sitzmodul Fahrer (SM [6d])'),
      EcuInfo(address: 0x01, name: 'ACSM', description: 'Advanced Crash Safety Module / Airbag'),
      EcuInfo(address: 0x56, name: 'FZD', description: 'Function Zone Dome / Roof Function Center'),
      EcuInfo(address: 0x78, name: 'IHKA', description: 'Integrated Automatic Heating & Climate Control (BMW KIS: F025 0x78)'),
      EcuInfo(address: 0x3F, name: 'VDC/EDC', description: 'Variable / Electronic Damper Control (Adaptive M)'),
      EcuInfo(address: 0x6E, name: 'EHC', description: 'Electronic Height Control / Pneumatic Air Suspension'),
      EcuInfo(address: 0x5D, name: 'KAFAS', description: 'Camera-Based Driver Assistance Systems'),
      EcuInfo(address: 0x1C, name: 'ICM', description: 'Integrated Chassis Management (BMW KIS: F025 0x1C)'),
      EcuInfo(address: 0x2C, name: 'PMA', description: 'Parking Maneuvering Assistant (BMW KIS: F025 0x2C)'),
      EcuInfo(address: 0x43, name: 'FLEL', description: 'Front Light Electronics Left (Adaptive LED/Laser)'),
      EcuInfo(address: 0x44, name: 'FLER', description: 'Front Light Electronics Right (Adaptive LED/Laser)'),
      EcuInfo(address: 0x67, name: 'PMA', description: 'Parking Maneuvering Assistant'),
      EcuInfo(address: 0x64, name: 'PDC', description: 'Park Distance Control'),
      EcuInfo(address: 0x5E, name: 'TRSVC', description: 'Top / Rear / Side View Surround Camera System'),
      EcuInfo(address: 0x20, name: 'AMP', description: 'High-End Audio Amplifier (Harman Kardon / Bowers & Wilkins)'),
      EcuInfo(address: 0x38, name: 'TCB/ATM', description: 'Telematics Communication Box / ATM 4G LTE'),
      EcuInfo(address: 0x58, name: 'SMFA', description: 'Seat Module Driver / Sitzmodul Fahrer'),
      EcuInfo(address: 0x59, name: 'SMBF', description: 'Seat Module Passenger / Sitzmodul Beifahrer'),
      EcuInfo(address: 0x62, name: 'CID', description: 'Central Information Display (NBT Screen)'),
      EcuInfo(address: 0x72, name: 'CAS', description: 'Car Access System / Immobilizer'),
      EcuInfo(address: 0x70, name: 'FRM', description: 'Footwell Module / Exterior Lighting & Windows'),
      EcuInfo(address: 0x3B, name: 'JBBF', description: 'Junction Box Battery & Electronics Controller'),
    ];
  }

  /// Known BMW Infospeicher (Shadow DTC) factory descriptions reverse-engineered
  /// from EDIABAS, ISTA, and BimmerGeeks ProTool.
  static const Map<String, String> shadowDtcDatabase = {
    // DME Engine Shadow Codes
    '138102': 'Exhaust Flap Actuator: Line disconnection / open circuit (Active valve unplugged or fuse pulled)',
    '138104': 'Exhaust Flap Actuator: Short circuit to ground',
    '1B0A21': 'Rough Road Detection: No wheel speed signal received from DSC',
    '1B0A60': 'Tuner Detection Flag: Engine torque monitor threshold exceeded (ECU flash/tune indicator)',
    '1B0A61': 'Torque Monitoring: Anti-tuning monitor intervention logged in shadow memory',
    '104402': 'DME Internal Checksum: Flash counter mismatch / Software modification shadow trace',
    '101F01': 'Throttle Valve Angle - Intake Pipe Absolute Pressure Plausibility: Pressure too high',
    '101F02': 'Throttle Valve Angle - Intake Pipe Absolute Pressure Plausibility: Pressure too low',
    '120408': 'Charging Pressure Control: Switch-off as safety consequence (Temporary overboost shadow)',
    '133010': 'Valvetronic Servomotor: Position sensor intermittent line fault',
    '11A002': 'High Fuel Pressure System: Cold start rail pressure below target',
    '11A031': 'Low Fuel Pressure System: Electric fuel pump delivery plausibility warning',
    '108A01': 'Charge-Air Temperature Sensor: Signal short circuit to B+',
    '140010': 'Combustion Misfire (General): Several cylinders intermittent misfire history',
    '140110': 'Combustion Misfire Cylinder 1: Intermittent shadow flag (No MIL illuminated)',
    '140210': 'Combustion Misfire Cylinder 2: Intermittent shadow flag (No MIL illuminated)',
    '140310': 'Combustion Misfire Cylinder 3: Intermittent shadow flag (No MIL illuminated)',
    '140410': 'Combustion Misfire Cylinder 4: Intermittent shadow flag (No MIL illuminated)',
    '140510': 'Combustion Misfire Cylinder 5: Intermittent shadow flag (No MIL illuminated)',
    '140610': 'Combustion Misfire Cylinder 6: Intermittent shadow flag (No MIL illuminated)',
    '118001': 'Mixture Control: Fuel-air mixture too lean (Shadow adaptation trace)',
    '118002': 'Mixture Control: Fuel-air mixture too rich (Shadow adaptation trace)',

    // EGS Transmission Shadow Codes
    'CF1701': 'EGS: Message (engine torque, 0x0A5) missing from DME',
    'CF1801': 'EGS: Message (status dynamic drive, 0x1AC) missing from DSC',
    '420012': 'EGS: Neutral Idle Control (NIC) plausibility slip detected',
    '420641': 'EGS: Intermittent CAN bus timeout',
    '420101': 'EGS: Transmission fluid temperature exceeded threshold history',

    // DSC / Braking Shadow Codes
    'CDA904': 'DSC: Message (status dynamic drive, 0x1AC) missing',
    'D35444': 'DSC: Signal error (actual steering angle, ID: 0x301) invalid',
    '480682': 'VTG Transfer Case: Temporary clutch thermal shutdown history',
    '4809AB': 'DSC: Undervoltage in vehicle electrical system',

    // FEM / BDC Body Electronics Shadow Codes
    '804080': 'FEM/BDC: Terminal 30B under-voltage detected during sleep cycle',
    '8040B5': 'FEM/BDC: Deactivation of terminal 30B - upper starting capability limit reached',
    '8041B6': 'FEM/BDC: Ambient light output deactivated due to over-current',
    '8041A4': 'FEM/BDC: Interior lighting output deactivation',
    '80436E': 'FEM/BDC: A/C compressor clutch open circuit',
    '804415': 'FEM/BDC: Rain-light-solar sensor optical initialization shadow error',

    // ACSM Airbag & Safety Shadow Codes
    '93076A': 'ACSM: Driver seat belt buckle switch intermittent contact',
    '93076B': 'ACSM: Passenger seat belt buckle switch intermittent contact',

    // KOMBI & Infotainment Shadow Codes
    'B7F668': 'KOMBI: Instrument cluster software reset event logged',
    'B7F805': 'HU_NBT: Navigation hard disk / flash media read delay',
    'B7F880': 'HU_NBT: USB port over-current protection triggered',
  };

  /// Reads Shadow Fault Memory (Infospeicher) via UDS [0x19, 0x04, 0xFF].
  /// Extracts silent codes that do not trigger the Check Engine Light.
  Future<List<ShadowDtcRecord>> readShadowFaultCodes(
    int ecuAddress, {
    String? ecuName,
    bool fetchFreezeFrames = true,
  }) async {
    final name = ecuName ?? 'ECU_0x${ecuAddress.toRadixString(16).toUpperCase()}';
    try {
      // UDS 0x19 0x04 0xFF: Read Infospeicher / Shadow Memory
      final response = await protocol.sendUdsAndAwait(
        ecuAddress,
        [0x19, 0x04, 0xFF],
        timeout: const Duration(seconds: 2),
      );

      if (response == null || response.length < 3) {
        return [];
      }

      // Check positive response: 0x59 0x04
      if (response[0] != 0x59 || response[1] != 0x04) {
        return [];
      }

      final records = <ShadowDtcRecord>[];
      final payload = response.sublist(2);

      // In ISO 14229 / BMW UDS Infospeicher:
      // Entries are structured as 4 bytes: [DTC_High, DTC_Mid, DTC_Low, Status_Mask]
      // Or 3 bytes DTC when no status mask is appended
      int step = 4;
      if (payload.length % 4 != 0 && payload.length % 3 == 0) {
        step = 3;
      }

      for (int i = 0; i + 3 <= payload.length; i += step) {
        final b1 = payload[i];
        final b2 = payload[i + 1];
        final b3 = payload[i + 2];
        final status = (step == 4 && i + 3 < payload.length) ? payload[i + 3] : 0x04;

        // Skip blank / null zero DTCs
        if (b1 == 0 && b2 == 0 && b3 == 0) continue;

        final hexCode = ((b1 << 16) | (b2 << 8) | b3)
            .toRadixString(16)
            .toUpperCase()
            .padLeft(6, '0');
        final stdDtc = _formatStandardDtc(b1, b2, b3);

        // Lookup ISTA/EDIABAS description
        final desc = shadowDtcDatabase[hexCode] ??
            'Shadow Memory Fault: $stdDtc ($hexCode) logged in ECU Infospeicher.';

        // Decode status description
        final statusDesc = _decodeStatusByte(status);

        // Fetch freeze frame environmental record if requested
        DtcFreezeFrame? freezeFrame;
        if (fetchFreezeFrames) {
          freezeFrame = await readDtcFreezeFrame(ecuAddress, b1, b2, b3);
        }

        records.add(ShadowDtcRecord(
          ecuAddress: ecuAddress,
          ecuName: name,
          hexCode: hexCode,
          standardDtc: stdDtc,
          description: desc,
          statusByte: status,
          statusDescription: statusDesc,
          freezeFrame: freezeFrame,
        ));
      }

      return records;
    } catch (e) {
      debugPrint('[BmwEcuScanner] Error reading shadow codes on 0x${ecuAddress.toRadixString(16)}: $e');
      return [];
    }
  }

  /// Decodes Extended Freeze Frame Environmental Snapshot Records
  /// UDS Request: [0x19, 0x04, dtcHigh, dtcMid, dtcLow, 0xFF]
  /// Decodes exact vehicle mileage (km), engine RPM, coolant temperature (°C),
  /// and rail pressure (bar) at DTC freeze moment.
  Future<DtcFreezeFrame?> readDtcFreezeFrame(
    int ecuAddress,
    int dtcHigh,
    int dtcMid,
    int dtcLow,
  ) async {
    try {
      final response = await protocol.sendUdsAndAwait(
        ecuAddress,
        [0x19, 0x04, dtcHigh, dtcMid, dtcLow, 0xFF],
        timeout: const Duration(milliseconds: 1500),
      );

      if (response == null || response.length < 6) {
        return null;
      }

      // Positive response SID: 0x59 0x04
      if (response[0] != 0x59 || response[1] != 0x04) {
        return null;
      }

      // Snapshot header: [0x59, 0x04, dtcHigh, dtcMid, dtcLow, status, (recordNum optional), ...]
      final snapshotPayload = response.length > 6 ? response.sublist(6) : response.sublist(5);
      return parseFreezeFramePayload(snapshotPayload);
    } catch (e) {
      debugPrint('[BmwEcuScanner] Error fetching freeze frame: $e');
      return null;
    }
  }

  /// Intelligently parses raw freeze frame snapshot payload bytes.
  /// Handles both DID-tagged records (ISO 14229) and raw BMW DME sequential struct.
  static DtcFreezeFrame parseFreezeFramePayload(Uint8List payload) {
    if (payload.isEmpty) {
      return DtcFreezeFrame(rawSnapshotBytes: payload);
    }

    int? mileageKm;
    int? engineRpm;
    double? coolantTempC;
    double? railPressureBar;
    double? batteryVoltage;
    int? faultFrequency;
    final rawDids = <String, dynamic>{};

    // Strategy 1: Scan for standardized ISO / BMW DIDs
    int i = 0;
    bool foundAnyDid = false;
    while (i + 2 < payload.length) {
      final did = (payload[i] << 8) | payload[i + 1];

      // DID 0xF1A0: Vehicle Odometer (3 bytes km)
      if (did == 0xF1A0 && i + 5 <= payload.length) {
        mileageKm = (payload[i + 2] << 16) | (payload[i + 3] << 8) | payload[i + 4];
        rawDids['0xF1A0_ODOMETER'] = mileageKm;
        foundAnyDid = true;
        i += 5;
        continue;
      }
      // DID 0xD011: Total Vehicle Mileage (3 or 4 bytes km)
      if (did == 0xD011 && i + 5 <= payload.length) {
        mileageKm = (payload[i + 2] << 16) | (payload[i + 3] << 8) | payload[i + 4];
        rawDids['0xD011_MILEAGE'] = mileageKm;
        foundAnyDid = true;
        i += 5;
        continue;
      }
      // DID 0x0100: OBD Distance / Mileage (3 bytes km)
      if (did == 0x0100 && i + 5 <= payload.length) {
        mileageKm = (payload[i + 2] << 16) | (payload[i + 3] << 8) | payload[i + 4];
        rawDids['0x0100_ODOMETER'] = mileageKm;
        foundAnyDid = true;
        i += 5;
        continue;
      }
      // DID 0x010C: Engine Speed RPM (2 bytes, 1/4 RPM per ISO 15031-5)
      if (did == 0x010C && i + 4 <= payload.length) {
        final rawVal = (payload[i + 2] << 8) | payload[i + 3];
        engineRpm = rawVal ~/ 4;
        rawDids['0x010C_ENGINE_RPM'] = engineRpm;
        foundAnyDid = true;
        i += 4;
        continue;
      }
      // DID 0xF001: BMW DME Engine RPM (2 bytes)
      if (did == 0xF001 && i + 4 <= payload.length) {
        engineRpm = (payload[i + 2] << 8) | payload[i + 3];
        rawDids['0xF001_RPM'] = engineRpm;
        foundAnyDid = true;
        i += 4;
        continue;
      }
      // DID 0x0105: Coolant Temperature (1 byte, offset -40°C)
      if (did == 0x0105 && i + 3 <= payload.length) {
        coolantTempC = (payload[i + 2] - 40).toDouble();
        rawDids['0x0105_COOLANT_TEMP'] = coolantTempC;
        foundAnyDid = true;
        i += 3;
        continue;
      }
      // DID 0xF002: BMW DME Coolant Temp (1 byte, offset -40°C)
      if (did == 0xF002 && i + 3 <= payload.length) {
        coolantTempC = (payload[i + 2] - 40).toDouble();
        rawDids['0xF002_COOLANT'] = coolantTempC;
        foundAnyDid = true;
        i += 3;
        continue;
      }
      // DID 0x0123: Fuel Rail Pressure (2 bytes, 10 kPa = 0.1 bar)
      if (did == 0x0123 && i + 4 <= payload.length) {
        final rawVal = (payload[i + 2] << 8) | payload[i + 3];
        railPressureBar = (rawVal * 10) / 100.0;
        rawDids['0x0123_RAIL_PRESSURE'] = railPressureBar;
        foundAnyDid = true;
        i += 4;
        continue;
      }
      // DID 0xF003: BMW DME Rail Pressure (2 bytes, 0.1 bar per LSB)
      if (did == 0xF003 && i + 4 <= payload.length) {
        final rawVal = (payload[i + 2] << 8) | payload[i + 3];
        railPressureBar = rawVal / 10.0;
        rawDids['0xF003_RAIL_PRESSURE'] = railPressureBar;
        foundAnyDid = true;
        i += 4;
        continue;
      }
      // DID 0xF111: Battery Supply Voltage (2 bytes mV)
      if (did == 0xF111 && i + 4 <= payload.length) {
        final rawMv = (payload[i + 2] << 8) | payload[i + 3];
        batteryVoltage = rawMv / 1000.0;
        rawDids['0xF111_VOLTAGE'] = batteryVoltage;
        foundAnyDid = true;
        i += 4;
        continue;
      }
      // DID 0xF000: Fault Frequency Counter (1 byte)
      if (did == 0xF000 && i + 3 <= payload.length) {
        faultFrequency = payload[i + 2];
        rawDids['0xF000_FAULT_COUNTER'] = faultFrequency;
        foundAnyDid = true;
        i += 3;
        continue;
      }

      i++;
    }

    // Strategy 2: Fallback to BMW Bosch MEVD17 / MG1 DME fixed offset record
    if (!foundAnyDid && payload.length >= 8) {
      // Offset 0..2: Mileage in km (24-bit big endian)
      final rawKm = (payload[0] << 16) | (payload[1] << 8) | payload[2];
      if (rawKm > 0 && rawKm < 600000) {
        mileageKm = rawKm;
      }

      // Offset 3..4: RPM (16-bit big endian, 1/4 RPM in DME raw format)
      if (payload.length >= 5) {
        final rawRpm = (payload[3] << 8) | payload[4];
        if (rawRpm ~/ 4 > 0 && rawRpm ~/ 4 <= 8500) {
          engineRpm = rawRpm ~/ 4;
        } else if (rawRpm > 0 && rawRpm <= 8500) {
          engineRpm = rawRpm;
        }
      }

      // Offset 5: Coolant temperature (-40..130°C)
      if (payload.length >= 6) {
        final rawTemp = payload[5] - 40;
        if (rawTemp >= -40 && rawTemp <= 140) {
          coolantTempC = rawTemp.toDouble();
        }
      }

      // Offset 6..7: Rail pressure (bar / 10 or * 0.1)
      if (payload.length >= 8) {
        final rawPressure = (payload[6] << 8) | payload[7];
        final pBar = rawPressure / 10.0;
        if (pBar >= 0 && pBar <= 300) {
          railPressureBar = pBar;
        }
      }

      // Offset 8..9: Battery voltage (mV)
      if (payload.length >= 10) {
        final rawMv = (payload[8] << 8) | payload[9];
        final v = rawMv / 1000.0;
        if (v >= 8.0 && v <= 16.0) {
          batteryVoltage = v;
        }
      }

      // Offset 10: Fault counter
      if (payload.length >= 11) {
        faultFrequency = payload[10];
      }
    }

    return DtcFreezeFrame(
      mileageKm: mileageKm,
      engineRpm: engineRpm,
      coolantTempC: coolantTempC,
      railPressureBar: railPressureBar,
      batteryVoltage: batteryVoltage,
      faultFrequency: faultFrequency,
      rawDids: rawDids,
      rawSnapshotBytes: payload,
    );
  }

  /// Clears Shadow Fault Memory on a specific ECU (UDS 0x14 0xFF 0xFF 0xFF)
  Future<bool> clearShadowFaultCodes(int ecuAddress) async {
    return await protocol.clearDtcCodes(ecuAddress);
  }

  /// Performs full ECU topology discovery, reads standard DTCs (0x19 0x02 0x0A),
  /// and scans Shadow Fault Memory (0x19 0x04 0xFF) with Freeze Frame records.
  Future<DiagnosticScanResult> performFullDiagnosticScan({
    bool includeShadowMemory = true,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final topology = getDefaultFSeriesTopology();
    String detectedVin = 'UNKNOWN_VIN';
    String chassis = 'F26';

    // 1. Read VIN
    onProgress?.call('Reading Vehicle Identification (VIN)...', 0.05);
    final vinDme = await protocol.readVin(0x12) ?? await protocol.readVin(0x10);
    if (vinDme != null && vinDme.isNotEmpty) {
      detectedVin = vinDme;
      debugPrint('[BmwEcuScanner] Detected Vehicle VIN: $detectedVin');
    }

    // 2. Ping and Query each ECU
    int totalFaults = 0;
    int totalShadowFaults = 0;
    final allShadowRecords = <ShadowDtcRecord>[];

    for (int i = 0; i < topology.length; i++) {
      final ecu = topology[i];
      final progress = 0.1 + (0.85 * (i / topology.length));
      onProgress?.call('Scanning ${ecu.name} (${ecu.description})...', progress);

      try {
        // Test responsiveness via DiagnosticSessionControl (0x10 0x01 default session)
        final sessionResp = await protocol.sendUdsAndAwait(
          ecu.address,
          [0x10, 0x01],
          timeout: const Duration(milliseconds: 600),
        );

        if (sessionResp != null && sessionResp.isNotEmpty && sessionResp[0] == 0x50) {
          ecu.isResponding = true;

          // 2a. Read standard DTCs (0x19 0x02 0x0A)
          final dtcs = await protocol.readDtcCodes(ecu.address);
          ecu.faultCodes = dtcs;
          totalFaults += dtcs.length;
          debugPrint('[BmwEcuScanner] ECU ${ecu.name} (0x${ecu.address.toRadixString(16)}): ${dtcs.length} standard faults');

          // 2b. Read Shadow Fault Memory (0x19 0x04 0xFF) for deep diagnostics
          if (includeShadowMemory) {
            final shadowCodes = await readShadowFaultCodes(
              ecu.address,
              ecuName: ecu.name,
              fetchFreezeFrames: true,
            );
            ecu.shadowFaultCodes = shadowCodes;
            totalShadowFaults += shadowCodes.length;
            allShadowRecords.addAll(shadowCodes);
            if (shadowCodes.isNotEmpty) {
              debugPrint('[BmwEcuScanner] ECU ${ecu.name}: ${shadowCodes.length} shadow faults detected');
            }
          }
        } else {
          ecu.isResponding = false;
        }
      } catch (e) {
        debugPrint('[BmwEcuScanner] Error scanning ${ecu.name}: $e');
        ecu.isResponding = false;
      }
    }

    onProgress?.call('Diagnostic scan complete.', 1.0);

    return DiagnosticScanResult(
      vin: detectedVin,
      chassis: chassis,
      ecuTopology: topology,
      totalFaults: totalFaults,
      totalShadowFaults: totalShadowFaults,
      allShadowFaults: allShadowRecords,
      timestamp: DateTime.now(),
    );
  }

  /// Clears fault codes across all responding ECUs (0x14 0xFF 0xFF 0xFF)
  Future<int> clearAllFaultCodes(List<EcuInfo> topology) async {
    int clearedCount = 0;
    for (final ecu in topology) {
      if (ecu.isResponding && (ecu.faultCodes.isNotEmpty || ecu.shadowFaultCodes.isNotEmpty)) {
        final success = await protocol.clearDtcCodes(ecu.address);
        if (success) {
          ecu.faultCodes.clear();
          ecu.shadowFaultCodes.clear();
          clearedCount++;
        }
      }
    }
    return clearedCount;
  }

  /// Clears fault codes and shadow memory on an individual ECU (UDS 0x14 0xFF 0xFF 0xFF).
  Future<bool> clearSingleEcuFaultCodes(int ecuAddress) async {
    try {
      final success = await protocol.clearDtcCodes(ecuAddress);
      debugPrint('[BmwEcuScanner] Cleared single ECU 0x${ecuAddress.toRadixString(16)}: $success');
      return success;
    } catch (e) {
      debugPrint('[BmwEcuScanner] Error clearing single ECU 0x${ecuAddress.toRadixString(16)}: $e');
      return false;
    }
  }

  /// ISTA ECU Reset Control (ISO 14229 UDS Service 0x11 Reset Steuergerät)
  /// Sends UDS 0x11 with the specified [EcuResetType] sub-function (0x01 Hard, 0x02 Key Off/On, 0x03 Soft).
  /// Validates positive response 0x51 with matching sub-function byte.
  Future<bool> resetControlUnit(int ecuAddress, EcuResetType type) async {
    try {
      debugPrint('[BmwEcuScanner] Sending UDS Reset 0x11 0x0${type.subFunction} to ECU 0x${ecuAddress.toRadixString(16)}...');
      final resp = await protocol.sendUdsAndAwait(
        ecuAddress,
        [0x11, type.subFunction],
        timeout: const Duration(seconds: 4),
      );
      if (resp != null && resp.length >= 2 && resp[0] == 0x51 && resp[1] == type.subFunction) {
        debugPrint('[BmwEcuScanner] ECU 0x${ecuAddress.toRadixString(16)} reset successful (0x51 0x0${type.subFunction})');
        return true;
      }
      debugPrint('[BmwEcuScanner] ECU 0x${ecuAddress.toRadixString(16)} reset rejected or unexpected response: $resp');
      return false;
    } catch (e) {
      debugPrint('[BmwEcuScanner] Exception resetting ECU 0x${ecuAddress.toRadixString(16)}: $e');
      return false;
    }
  }

  /// Reads OBD-II I/M Emissions Inspection Readiness (Mode 01 PID 01 or UDS DID 0xF401)
  /// Queries DME (0x12) by default.
  Future<EmissionsReadinessResult?> readEmissionsReadiness({int dmeAddress = 0x12}) async {
    try {
      // 1. Attempt standard OBD-II Mode 01 PID 01 [0x01, 0x01]
      final obdResp = await protocol.sendUdsAndAwait(
        dmeAddress,
        [0x01, 0x01],
        timeout: const Duration(seconds: 2),
      );

      if (obdResp != null && obdResp.length >= 6 && obdResp[0] == 0x41 && obdResp[1] == 0x01) {
        return parseEmissionsReadinessPayload(obdResp.sublist(2, 6));
      }

      // 2. Attempt UDS ReadDataByIdentifier DID 0xF401 [0x22, 0xF4, 0x01]
      final udsResp = await protocol.sendUdsAndAwait(
        dmeAddress,
        [0x22, 0xF4, 0x01],
        timeout: const Duration(seconds: 2),
      );

      if (udsResp != null && udsResp.length >= 7 && udsResp[0] == 0x62 && udsResp[1] == 0xF4 && udsResp[2] == 0x01) {
        return parseEmissionsReadinessPayload(udsResp.sublist(3, 7));
      }

      // 3. Fallback check for any 4-byte payload from DME
      if (udsResp != null && udsResp.length >= 4) {
        final startIdx = (udsResp[0] == 0x62) ? 3 : 0;
        if (udsResp.length >= startIdx + 4) {
          return parseEmissionsReadinessPayload(udsResp.sublist(startIdx, startIdx + 4));
        }
      }

      return null;
    } catch (e) {
      debugPrint('[BmwEcuScanner] Error reading emissions readiness from 0x${dmeAddress.toRadixString(16)}: $e');
      return null;
    }
  }

  /// Parses 4-byte OBD-II PID 01 / DID 0xF401 Emissions Readiness bitmask.
  /// Decodes MIL status, DTC count, and all 9 standard emission monitors:
  /// - Misfire Monitor
  /// - Fuel System Monitor
  /// - Comprehensive Component Monitor
  /// - Catalyst Monitor (კატალიზატორი)
  /// - Evaporative System (EVAP)
  /// - Secondary Air System
  /// - Oxygen Sensor (ლამბდა)
  /// - Oxygen Sensor Heater (ლამბდას გამათბობელი)
  /// - EGR / VVT System Monitor
  static EmissionsReadinessResult parseEmissionsReadinessPayload(Uint8List payload) {
    Uint8List dataBytes = payload;
    if (dataBytes.length >= 6 && dataBytes[0] == 0x41 && dataBytes[1] == 0x01) {
      dataBytes = dataBytes.sublist(2, 6);
    } else if (dataBytes.length >= 7 && dataBytes[0] == 0x62 && dataBytes[1] == 0xF4 && dataBytes[2] == 0x01) {
      dataBytes = dataBytes.sublist(3, 7);
    }

    if (dataBytes.length < 4) {
      return EmissionsReadinessResult(
        milOn: false,
        dtcCount: 0,
        monitors: const [],
        rawBytes: payload,
        timestamp: DateTime.now(),
      );
    }

    final byteA = dataBytes[0];
    final byteB = dataBytes[1];
    final byteC = dataBytes[2];
    final byteD = dataBytes[3];

    final milOn = (byteA & 0x80) != 0;
    final dtcCount = byteA & 0x7F;

    MonitorStatus resolveStatus(bool isSupported, bool isComplete) {
      if (!isSupported) return MonitorStatus.unsupported;
      if (isComplete) return MonitorStatus.passed;
      return milOn ? MonitorStatus.failed : MonitorStatus.incomplete;
    }

    final monitors = <EmissionsMonitor>[
      EmissionsMonitor(
        id: 'MISFIRE',
        name: 'Misfire Monitor',
        description: 'Cylinder combustion misfire detection (ცილინდრებში აფეთქების ჩავარდნის კონტროლი)',
        isSupported: (byteB & 0x01) != 0,
        isComplete: (byteB & 0x10) == 0,
        status: resolveStatus((byteB & 0x01) != 0, (byteB & 0x10) == 0),
      ),
      EmissionsMonitor(
        id: 'FUEL_SYSTEM',
        name: 'Fuel System Monitor',
        description: 'Fuel delivery and closed-loop mixture trim (საწვავის მიწოდება და ნარევის რეგულირება)',
        isSupported: (byteB & 0x02) != 0,
        isComplete: (byteB & 0x20) == 0,
        status: resolveStatus((byteB & 0x02) != 0, (byteB & 0x20) == 0),
      ),
      EmissionsMonitor(
        id: 'COMPREHENSIVE',
        name: 'Comprehensive Component Monitor',
        description: 'Powertrain sensors, actuators and CAN signals (სენსორებისა და აქტუატორების კომპონენტები)',
        isSupported: (byteB & 0x04) != 0,
        isComplete: (byteB & 0x40) == 0,
        status: resolveStatus((byteB & 0x04) != 0, (byteB & 0x40) == 0),
      ),
      EmissionsMonitor(
        id: 'CATALYST',
        name: 'Catalyst Monitor',
        description: 'Catalytic converter conversion efficiency (კატალიზატორის ეფექტურობა)',
        isSupported: (byteC & 0x01) != 0,
        isComplete: (byteD & 0x01) == 0,
        status: resolveStatus((byteC & 0x01) != 0, (byteD & 0x01) == 0),
      ),
      EmissionsMonitor(
        id: 'EVAP',
        name: 'Evaporative System (EVAP)',
        description: 'Fuel tank vapor purge and leak detection (საწვავის ავზის ორთქლის შთანთქმის სისტემა)',
        isSupported: (byteC & 0x04) != 0,
        isComplete: (byteD & 0x04) == 0,
        status: resolveStatus((byteC & 0x04) != 0, (byteD & 0x04) == 0),
      ),
      EmissionsMonitor(
        id: 'SECONDARY_AIR',
        name: 'Secondary Air System',
        description: 'Secondary air pump and injection valve (მეორადი ჰაერის შეფრქვევის სისტემა)',
        isSupported: (byteC & 0x08) != 0,
        isComplete: (byteD & 0x08) == 0,
        status: resolveStatus((byteC & 0x08) != 0, (byteD & 0x08) == 0),
      ),
      EmissionsMonitor(
        id: 'O2_SENSOR',
        name: 'Oxygen Sensor (Lambda)',
        description: 'Pre/Post-catalytic oxygen sensors response (ჟანგბადის სენსორები / ლამბდა-ზონდები)',
        isSupported: (byteC & 0x20) != 0,
        isComplete: (byteD & 0x20) == 0,
        status: resolveStatus((byteC & 0x20) != 0, (byteD & 0x20) == 0),
      ),
      EmissionsMonitor(
        id: 'O2_HEATER',
        name: 'Oxygen Sensor Heater',
        description: 'Lambda sensor heating element circuits (ლამბდა-ზონდის გამათბობელი ელემენტები)',
        isSupported: (byteC & 0x40) != 0,
        isComplete: (byteD & 0x40) == 0,
        status: resolveStatus((byteC & 0x40) != 0, (byteD & 0x40) == 0),
      ),
      EmissionsMonitor(
        id: 'EGR_VVT',
        name: 'EGR / VVT System Monitor',
        description: 'Exhaust gas recirculation and VANOS/Valvetronic variable valve timing (EGR და VANOS/VVT სისტემა)',
        isSupported: (byteC & 0x80) != 0,
        isComplete: (byteD & 0x80) == 0,
        status: resolveStatus((byteC & 0x80) != 0, (byteD & 0x80) == 0),
      ),
    ];

    return EmissionsReadinessResult(
      milOn: milOn,
      dtcCount: dtcCount,
      monitors: monitors,
      rawBytes: payload,
      timestamp: DateTime.now(),
    );
  }

  /// Reads ECU Hardware and Software Identification DIDs (0xF187..0xF190)
  /// - DID 0xF187: BMW Sachnummer (7-digit Part Number)
  /// - DID 0xF188: HWEL (Hardware Electronic Version)
  /// - DID 0xF189: SWFL (Software Flash / Application Version)
  /// - DID 0xF18B: Coding Index (Codierindex)
  /// - DID 0xF190: Vehicle Identification Number (VIN)
  Future<EcuIdentification?> readEcuIdentification(int ecuAddress, {String? ecuName}) async {
    final name = ecuName ?? 'ECU_0x${ecuAddress.toRadixString(16).toUpperCase()}';
    try {
      final dids = [0xF187, 0xF188, 0xF189, 0xF18B, 0xF190];
      final rawResults = <int, Uint8List>{};

      Future<void> queryDids() async {
        for (final did in dids) {
          final msb = (did >> 8) & 0xFF;
          final lsb = did & 0xFF;
          final resp = await protocol.sendUdsAndAwait(
            ecuAddress,
            [0x22, msb, lsb],
            timeout: const Duration(milliseconds: 1500),
          );

          if (resp != null && resp.length >= 3 && resp[0] == 0x62 && resp[1] == msb && resp[2] == lsb) {
            rawResults[did] = resp.sublist(3);
          }
        }
      }

      await queryDids();

      // If initial read yielded nothing, try opening extended diagnostic session (0x10 0x03)
      if (rawResults.isEmpty) {
        await protocol.sendUdsAndAwait(
          ecuAddress,
          [0x10, 0x03],
          timeout: const Duration(milliseconds: 1000),
        );
        await queryDids();
      }

      if (rawResults.isEmpty) {
        return null;
      }

      final partNumber = rawResults.containsKey(0xF187)
          ? parseSachnummer(rawResults[0xF187]!)
          : 'Unknown';
      final hwel = rawResults.containsKey(0xF188)
          ? parseHwelVersion(rawResults[0xF188]!)
          : 'Unknown';
      final swfl = rawResults.containsKey(0xF189)
          ? parseSwflVersion(rawResults[0xF189]!)
          : 'Unknown';
      final codingIdx = rawResults.containsKey(0xF18B)
          ? parseCodingIndex(rawResults[0xF18B]!)
          : 'Unknown';
      final vin = rawResults.containsKey(0xF190)
          ? parseVin(rawResults[0xF190]!)
          : 'Unknown';

      return EcuIdentification(
        ecuAddress: ecuAddress,
        ecuName: name,
        partNumber: partNumber,
        hwelVersion: hwel,
        swflVersion: swfl,
        codingIndex: codingIdx,
        vin: vin,
        rawDids: rawResults.map((k, v) => MapEntry('0x${k.toRadixString(16).toUpperCase()}', v)),
      );
    } catch (e) {
      debugPrint('[BmwEcuScanner] Error reading identification on 0x${ecuAddress.toRadixString(16)}: $e');
      return null;
    }
  }

  static String parseSachnummer(Uint8List bytes) {
    if (bytes.isEmpty) return 'N/A';

    final isPrintableAscii = bytes.every((b) => b >= 0x20 && b <= 0x7E);
    if (isPrintableAscii) {
      final str = String.fromCharCodes(bytes).trim();
      if (str.isNotEmpty) return str;
    }

    if (bytes.length == 4) {
      final val = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      return val.toString().padLeft(7, '0');
    }
    if (bytes.length == 3) {
      final val = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
      return val.toString().padLeft(7, '0');
    }

    final cleaned = bytes.where((b) => b != 0xFF).toList();
    return cleaned.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join('');
  }

  static String parseHwelVersion(Uint8List bytes) {
    if (bytes.isEmpty) return 'N/A';

    final isPrintableAscii = bytes.every((b) => b >= 0x20 && b <= 0x7E);
    if (isPrintableAscii) {
      final str = String.fromCharCodes(bytes).trim();
      if (str.length >= 4 && (str.startsWith('HW') || str.contains('.'))) {
        return str;
      }
    }

    if (bytes.length >= 7) {
      final id = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      final major = bytes[4];
      final minor = bytes[5];
      final patch = bytes[6];
      return 'HWEL_${id.toRadixString(16).toUpperCase().padLeft(8, '0')}_${major.toString().padLeft(3, '0')}_${minor.toString().padLeft(3, '0')}_${patch.toString().padLeft(3, '0')}';
    }

    final cleaned = bytes.where((b) => b != 0xFF).toList();
    return cleaned.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join('.');
  }

  static String parseSwflVersion(Uint8List bytes) {
    if (bytes.isEmpty) return 'N/A';

    final isPrintableAscii = bytes.every((b) => b >= 0x20 && b <= 0x7E);
    if (isPrintableAscii) {
      final str = String.fromCharCodes(bytes).trim();
      if (str.length >= 4 && (str.startsWith('SW') || str.contains('.'))) {
        return str;
      }
    }

    if (bytes.length >= 7) {
      final id = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      final major = bytes[4];
      final minor = bytes[5];
      final patch = bytes[6];
      return 'SWFL_${id.toRadixString(16).toUpperCase().padLeft(8, '0')}_${major.toString().padLeft(3, '0')}_${minor.toString().padLeft(3, '0')}_${patch.toString().padLeft(3, '0')}';
    }

    final cleaned = bytes.where((b) => b != 0xFF).toList();
    return cleaned.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join('.');
  }

  static String parseCodingIndex(Uint8List bytes) {
    if (bytes.isEmpty) return 'N/A';
    final cleaned = bytes.where((b) => b != 0xFF).toList();
    if (cleaned.isEmpty) return 'N/A';

    if (cleaned.length == 1) {
      final val = cleaned[0];
      return '0x${val.toRadixString(16).toUpperCase().padLeft(2, '0')} ($val)';
    }
    if (cleaned.length == 2) {
      final val = (cleaned[0] << 8) | cleaned[1];
      return '0x${val.toRadixString(16).toUpperCase().padLeft(4, '0')} ($val)';
    }

    final isPrintableAscii = cleaned.every((b) => b >= 0x20 && b <= 0x7E);
    if (isPrintableAscii) {
      final str = String.fromCharCodes(cleaned).trim();
      if (str.isNotEmpty) return str;
    }

    return '0x${cleaned.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join('')}';
  }

  static String parseVin(Uint8List bytes) {
    if (bytes.isEmpty) return 'N/A';
    final cleaned = bytes.where((b) => b >= 0x20 && b <= 0x7E).toList();
    if (cleaned.isEmpty) return 'N/A';
    final vin = String.fromCharCodes(cleaned).trim();
    if (vin.length >= 17) return vin.substring(0, 17);
    return vin;
  }

  String _formatStandardDtc(int b1, int b2, int b3) {
    String prefix;
    final type = (b1 >> 6) & 0x03;
    switch (type) {
      case 0: prefix = 'P'; break;
      case 1: prefix = 'C'; break;
      case 2: prefix = 'B'; break;
      case 3: prefix = 'U'; break;
      default: prefix = 'P';
    }
    final digit1 = (b1 >> 4) & 0x03;
    final digit2 = b1 & 0x0F;
    final digit3 = (b2 >> 4) & 0x0F;
    final digit4 = b2 & 0x0F;
    return '$prefix$digit1${digit2.toRadixString(16).toUpperCase()}${digit3.toRadixString(16).toUpperCase()}${digit4.toRadixString(16).toUpperCase()}';
  }

  String _decodeStatusByte(int status) {
    final flags = <String>[];
    if (status & 0x01 != 0) flags.add('Active');
    if (status & 0x04 != 0) flags.add('Infospeicher');
    if (status & 0x08 != 0) flags.add('Confirmed');
    if (status & 0x20 != 0) flags.add('History');
    if (status & 0x80 != 0) flags.add('MIL-On');
    if (flags.isEmpty) flags.add('Silent Shadow');
    return flags.join(' | ');
  }
}
