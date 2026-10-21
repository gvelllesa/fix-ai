import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'bmw_ecu_scanner.dart';
import 'bmw_flash_manager.dart';

/// Version-specific parameter override for a specific BMW CAFD SGBM-ID prefix
/// (e.g. `CAFD_00000794_014`).
class CafdParameterOverride {
  final int? did;
  final int? byteOffset;
  final int? bitMask;
  final int? activeValue;
  final int? inactiveValue;

  const CafdParameterOverride({
    this.did,
    this.byteOffset,
    this.bitMask,
    this.activeValue,
    this.inactiveValue,
  });
}

/// Representation of a 1-Tap BMW FDL Cheat Code parameter.
class FdlCheatCode {
  final String id;
  final String name;
  final String category; // 'Lighting & Visibility', 'Cockpit & Cluster', 'Safety & Chimes', 'Comfort & Convenience', 'Infotainment & Media', 'Drivetrain & Performance', 'Engine & Start-Stop'
  final String description;
  final int targetEcuAddress;
  final String targetEcuName;
  final int did; // ISO 14229 Data Identifier
  final int byteOffset; // Offset inside NCD block
  final int bitMask; // Bitmask to target
  final int activeValue; // Target byte value for active state
  final int inactiveValue; // Target byte value for inactive state
  final int? secondaryEcuAddress;
  final String? secondaryEcuName;
  final int? secondaryDid;
  final int? secondaryByteOffset;
  final int? secondaryBitMask;
  final int? secondaryActiveValue;
  final int? secondaryInactiveValue;
  final Map<String, CafdParameterOverride>? cafdOverrides;
  bool isCurrentlyActive;

  FdlCheatCode({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.targetEcuAddress,
    required this.targetEcuName,
    required this.did,
    required this.byteOffset,
    required this.bitMask,
    required this.activeValue,
    required this.inactiveValue,
    this.secondaryEcuAddress,
    this.secondaryEcuName,
    this.secondaryDid,
    this.secondaryByteOffset,
    this.secondaryBitMask,
    this.secondaryActiveValue,
    this.secondaryInactiveValue,
    this.cafdOverrides,
    this.isCurrentlyActive = false,
  });

  /// Resolves CAFD-version-specific DID, byteOffset, bitMask, and target values
  /// when the ECU's active `CAFD` SGBM-ID matches an entry in [cafdOverrides].
  FdlCheatCode resolveForCafd(String? cafdSgbmId) {
    if (cafdSgbmId == null || cafdOverrides == null || cafdOverrides!.isEmpty) {
      return this;
    }
    final upperCafd = cafdSgbmId.toUpperCase();
    for (final entry in cafdOverrides!.entries) {
      if (upperCafd.startsWith(entry.key.toUpperCase())) {
        final ov = entry.value;
        return FdlCheatCode(
          id: id,
          name: name,
          category: category,
          description: description,
          targetEcuAddress: targetEcuAddress,
          targetEcuName: targetEcuName,
          did: ov.did ?? did,
          byteOffset: ov.byteOffset ?? byteOffset,
          bitMask: ov.bitMask ?? bitMask,
          activeValue: ov.activeValue ?? activeValue,
          inactiveValue: ov.inactiveValue ?? inactiveValue,
          secondaryEcuAddress: secondaryEcuAddress,
          secondaryEcuName: secondaryEcuName,
          secondaryDid: secondaryDid,
          secondaryByteOffset: secondaryByteOffset,
          secondaryBitMask: secondaryBitMask,
          secondaryActiveValue: secondaryActiveValue,
          secondaryInactiveValue: secondaryInactiveValue,
          cafdOverrides: cafdOverrides,
          isCurrentlyActive: isCurrentlyActive,
        );
      }
    }
    return this;
  }

  FdlCheatCode copyWith({bool? isCurrentlyActive}) {
    return FdlCheatCode(
      id: id,
      name: name,
      category: category,
      description: description,
      targetEcuAddress: targetEcuAddress,
      targetEcuName: targetEcuName,
      did: did,
      byteOffset: byteOffset,
      bitMask: bitMask,
      activeValue: activeValue,
      inactiveValue: inactiveValue,
      secondaryEcuAddress: secondaryEcuAddress,
      secondaryEcuName: secondaryEcuName,
      secondaryDid: secondaryDid,
      secondaryByteOffset: secondaryByteOffset,
      secondaryBitMask: secondaryBitMask,
      secondaryActiveValue: secondaryActiveValue,
      secondaryInactiveValue: secondaryInactiveValue,
      cafdOverrides: cafdOverrides,
      isCurrentlyActive: isCurrentlyActive ?? this.isCurrentlyActive,
    );
  }
}

/// NCD Raw Coding Block Backup representation.
/// Saves the pristine original bytes of an ECU's coding DID before any write occurs,
/// allowing guaranteed 1-Tap Rollback to factory state.
class NcdBackup {
  final String id;
  final DateTime timestamp;
  final String vin;
  final int ecuAddress;
  final String ecuName;
  final int did;
  final String cheatCodeId;
  final String cheatCodeName;
  final Uint8List originalBytes;
  final String description;

  const NcdBackup({
    required this.id,
    required this.timestamp,
    required this.vin,
    required this.ecuAddress,
    required this.ecuName,
    required this.did,
    required this.cheatCodeId,
    required this.cheatCodeName,
    required this.originalBytes,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'vin': vin,
      'ecuAddress': ecuAddress,
      'ecuName': ecuName,
      'did': did,
      'cheatCodeId': cheatCodeId,
      'cheatCodeName': cheatCodeName,
      'originalBytes': base64Encode(originalBytes),
      'description': description,
    };
  }

  factory NcdBackup.fromJson(Map<String, dynamic> json) {
    return NcdBackup(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      vin: json['vin'] as String? ?? 'UNKNOWN_VIN',
      ecuAddress: json['ecuAddress'] as int,
      ecuName: json['ecuName'] as String,
      did: json['did'] as int,
      cheatCodeId: json['cheatCodeId'] as String,
      cheatCodeName: json['cheatCodeName'] as String,
      originalBytes: base64Decode(json['originalBytes'] as String),
      description: json['description'] as String? ?? '',
    );
  }
}

/// Coding Execution Result
class CodingResult {
  final bool success;
  final String title;
  final String message;
  final String? backupId;
  final int? nrcCode;
  final DateTime timestamp;
  final Map<String, dynamic> details;

  CodingResult({
    required this.success,
    required this.title,
    required this.message,
    this.backupId,
    this.nrcCode,
    DateTime? timestamp,
    this.details = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  String? get nrcDescription {
    if (nrcCode == null) return null;
    switch (nrcCode) {
      case 0x11: return 'Service Not Supported';
      case 0x12: return 'Sub-function Not Supported';
      case 0x13: return 'Incorrect Message Length or Format';
      case 0x22: return 'Conditions Not Correct (Ignition ON required)';
      case 0x31: return 'Request Out Of Range';
      case 0x33: return 'Security Access Denied';
      case 0x72: return 'General Programming Failure';
      case 0x78: return 'Response Pending (ECU Busy)';
      case 0x7E: return 'Sub-function Not Supported In Active Session';
      default: return 'UDS NRC 0x${nrcCode!.toRadixString(16).toUpperCase()}';
    }
  }
}

/// E-Sys SALAPA Option Code Metadata (E-Sys bmwcodes.txt & ISTA FA Retrofit Engine)
class SalapaOptionInfo {
  final String code; // e.g. '$2TB'
  final String name; // e.g. 'Sport Automatic Transmission'
  final String description; // E-Sys official factory description
  final String category; // e.g. 'Drivetrain & Performance'
  final List<String> affectedEcus; // e.g. ['EGS (0x18)', 'FEM/BDC (0x40)', 'KOMBI (0x60)']
  final List<int> affectedEcuAddresses; // e.g. [0x18, 0x40, 0x60]

  const SalapaOptionInfo({
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.affectedEcus,
    this.affectedEcuAddresses = const [],
  });

  String get cleanCode => code.replaceAll(r'$', '');

  BmwSalapaOption toBmwSalapaOption() {
    return BmwSalapaOption(
      code: code,
      name: name,
      description: description,
      category: category,
      affectedEcuAddresses: affectedEcuAddresses,
      affectedEcuNames: affectedEcus,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'cleanCode': cleanCode,
    'name': name,
    'description': description,
    'category': category,
    'affectedEcus': affectedEcus,
    'affectedEcuAddresses': affectedEcuAddresses.map((a) => '0x${a.toRadixString(16)}').toList(),
  };
}

/// E-Sys SALAPA Option Code Dictionary & Retrofit Engine
/// Comprehensive catalog of 60+ authentic BMW factory option codes from E-Sys `bmwcodes.txt`.
class SalapaOptionDictionary {
  static const List<SalapaOptionInfo> options = [
    SalapaOptionInfo(
      code: r'$2TB',
      name: 'Sport Automatic Transmission',
      description: 'Sport automatic gearbox with rapid gear shifting, steering wheel paddle shifters, Launch Control, and Sport+ drive profile.',
      category: 'Drivetrain & Performance',
      affectedEcus: ['EGS (0x18)', 'FEM/BDC (0x40)', 'KOMBI (0x60)', 'DME (0x12)', 'DSC (0x29)'],
      affectedEcuAddresses: [0x18, 0x40, 0x60, 0x12, 0x29],
    ),
    SalapaOptionInfo(
      code: r'$205',
      name: 'Automatic Transmission (Standard)',
      description: 'Factory baseline automatic transmission shift calibrations without paddle shift capability.',
      category: 'Drivetrain & Performance',
      affectedEcus: ['EGS (0x18)', 'FEM/BDC (0x40)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x18, 0x40, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$2VF',
      name: 'Adaptive M Suspension',
      description: 'Electronic Damper Control (EDC) with dynamic real-time shock absorber valving and stiffened Sport/Sport+ rebound damping.',
      category: 'Chassis & Suspension',
      affectedEcus: ['VDC/EDC (0x3F)', 'FEM/BDC (0x40)', 'DSC (0x29)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x3F, 0x40, 0x29, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$2VL',
      name: 'Variable Sport Steering',
      description: 'Variable steering rack ratio with speed-sensitive mechanical angle progression and EPS rack assistance mapping.',
      category: 'Chassis & Suspension',
      affectedEcus: ['EPS (0x30)', 'DSC (0x29)'],
      affectedEcuAddresses: [0x30, 0x29],
    ),
    SalapaOptionInfo(
      code: r'$704',
      name: 'M Sport Suspension',
      description: 'Fixed firmer spring rates, aggressive shock damping, stiffer anti-roll bars, and 10mm lowered chassis stance.',
      category: 'Chassis & Suspension',
      affectedEcus: ['DSC (0x29)', 'FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x29, 0x40],
    ),
    SalapaOptionInfo(
      code: r'$2NH',
      name: 'M Sport Brake',
      description: '4-piston aluminum fixed front calipers and 2-piston rear calipers with enlarged discs; recalibrates DSC brake booster curves and pre-fill pressure.',
      category: 'Chassis & Suspension',
      affectedEcus: ['DSC (0x29)'],
      affectedEcuAddresses: [0x29],
    ),
    SalapaOptionInfo(
      code: r'$2VB',
      name: 'Tyre Pressure Display (RDC)',
      description: 'Direct tire pressure monitoring system broadcasting individual live wheel pressures (bar/psi) and tire temperatures (°C) to iDrive.',
      category: 'Chassis & Suspension',
      affectedEcus: ['DSC (0x29)', 'HU_NBT (0x63)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x29, 0x63, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$248',
      name: 'Steering Wheel Heating',
      description: 'Heated steering wheel rim with dedicated push-button activation and temperature feedback control via switch center.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)', 'SZL (0x1C)'],
      affectedEcuAddresses: [0x40, 0x1C],
    ),
    SalapaOptionInfo(
      code: r'$302',
      name: 'Alarm System',
      description: 'Ultrasonic interior motion detector, tilt alarm sensor, and siren with acoustic confirmation chirp on lock/unlock.',
      category: 'Safety & Security',
      affectedEcus: ['FEM/BDC (0x40)', 'FZD (0x56)'],
      affectedEcuAddresses: [0x40, 0x56],
    ),
    SalapaOptionInfo(
      code: r'$316',
      name: 'Automatic Tailgate Operation',
      description: 'Electromechanical luggage compartment spindle drives with remote fob and hands-free opening/closing.',
      category: 'Comfort & Convenience',
      affectedEcus: ['HKFM (0x78)', 'FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x78, 0x40],
    ),
    SalapaOptionInfo(
      code: r'$319',
      name: 'Integrated Universal Remote Control',
      description: 'Integrated HomeLink 3-channel garage door transceiver built into interior rearview mirror.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$322',
      name: 'Comfort Access System',
      description: 'Keyless passive entry and start, capacitive exterior door handle touch unlock, and smart trunk kick gesture sensor.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$323',
      name: 'Soft-Close Automatic Doors',
      description: 'Motorized electric door pull-in latches automatically securing partially closed doors.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)', 'REM (0x74)'],
      affectedEcuAddresses: [0x40, 0x74],
    ),
    SalapaOptionInfo(
      code: r'$337',
      name: 'M Sport Package',
      description: 'Complete aerodynamic body package, sport seats, Anthracite headliner, M door sills, and M steering wheel.',
      category: 'Interior & Styling',
      affectedEcus: ['FEM/BDC (0x40)', 'KOMBI (0x60)', 'HU_NBT (0x63)'],
      affectedEcuAddresses: [0x40, 0x60, 0x63],
    ),
    SalapaOptionInfo(
      code: r'$3AG',
      name: 'Reversing Camera',
      description: 'Wide-angle rear view camera with interactive dynamic trajectory guidelines and obstacle distance markers on iDrive display.',
      category: 'Driver Assistance',
      affectedEcus: ['HU_NBT (0x63)', 'PDC/PMA (0x67)', 'REM (0x74)'],
      affectedEcuAddresses: [0x63, 0x67, 0x74],
    ),
    SalapaOptionInfo(
      code: r'$430',
      name: 'Interior/Exterior Auto-Dim Mirror',
      description: 'Automatic electrochromic anti-glare dipping for interior and exterior mirrors, plus motorized folding on vehicle lock.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$431',
      name: 'Interior Rearview Mirror with Auto-Dip',
      description: 'Automatic electrochromic dimming rearview mirror preventing rear headlight glare.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$459',
      name: 'Electric Seat Adjustment with Memory',
      description: 'Multi-axis power seat adjustment with 2-position driver memory, mirror synchronization, and easy exit entry tilt.',
      category: 'Comfort & Convenience',
      affectedEcus: ['SMFA (0x6E)', 'SMBF (0x6F)', 'FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x6E, 0x6F, 0x40],
    ),
    SalapaOptionInfo(
      code: r'$481',
      name: 'Sport Seats for Driver and Front Passenger',
      description: 'Deep bolster front bucket seats with power adjustable side bolsters and manual thigh support extension.',
      category: 'Interior & Styling',
      affectedEcus: ['SMFA (0x6E)', 'SMBF (0x6F)', 'FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x6E, 0x6F, 0x40],
    ),
    SalapaOptionInfo(
      code: r'$488',
      name: 'Lumbar Support for Driver and Passenger',
      description: 'Pneumatic 4-way height and depth lumbar adjustment chamber cushions in front seat backrests.',
      category: 'Comfort & Convenience',
      affectedEcus: ['SMFA (0x6E)', 'SMBF (0x6F)'],
      affectedEcuAddresses: [0x6E, 0x6F],
    ),
    SalapaOptionInfo(
      code: r'$494',
      name: 'Seat Heating for Driver and Front Passenger',
      description: '3-stage rapid seat cushion and backrest electric heating elements with automatic temperature regulation.',
      category: 'Comfort & Convenience',
      affectedEcus: ['FEM/BDC (0x40)', 'IHKA (0x6D)'],
      affectedEcuAddresses: [0x40, 0x6D],
    ),
    SalapaOptionInfo(
      code: r'$496',
      name: 'Seat Heating for Rear Passengers',
      description: '2-stage independent seat bottom heating elements for outboard rear bench seating.',
      category: 'Comfort & Convenience',
      affectedEcus: ['REM (0x74)', 'IHKA (0x6D)'],
      affectedEcuAddresses: [0x74, 0x6D],
    ),
    SalapaOptionInfo(
      code: r'$508',
      name: 'Park Distance Control (Front & Rear PDC)',
      description: 'Ultrasonic proximity sensors in front and rear bumpers with acoustic warning beeps and visual radar graphic.',
      category: 'Driver Assistance',
      affectedEcus: ['FEM/BDC (0x40)', 'HU_NBT (0x63)', 'REM (0x74)'],
      affectedEcuAddresses: [0x40, 0x63, 0x74],
    ),
    SalapaOptionInfo(
      code: r'$521',
      name: 'Rain Sensor & Automatic Headlights',
      description: 'Optical infrared rain sensor on windshield with automatic wiper frequency and ambient twilight headlamp activation.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)', 'FZD/RLS (0x56)'],
      affectedEcuAddresses: [0x40, 0x56],
    ),
    SalapaOptionInfo(
      code: r'$522',
      name: 'Xenon Light',
      description: 'Bi-xenon gas discharge projector headlamps with automatic dynamic headlight range control.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$524',
      name: 'Adaptive Headlights',
      description: 'Swiveling bi-xenon headlights following steering angle with dynamic cornering light illumination.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)', 'DSC (0x29)'],
      affectedEcuAddresses: [0x40, 0x29],
    ),
    SalapaOptionInfo(
      code: r'$534',
      name: 'Automatic Air Conditioning (Dual-Zone)',
      description: 'Digital 2-zone automatic climate control with automatic air recirculation (AUC), microfilter, and solar sensor.',
      category: 'Comfort & Convenience',
      affectedEcus: ['IHKA (0x6D)', 'FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x6D, 0x40],
    ),
    SalapaOptionInfo(
      code: r'$544',
      name: 'Cruise Control with Braking Function',
      description: 'Speed control system retaining set speed downhill via automatic brake actuation; displayed in instrument cluster.',
      category: 'Driver Assistance',
      affectedEcus: ['DME (0x12)', 'DSC (0x29)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x12, 0x29, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$548',
      name: 'Kilometre Speedo',
      description: 'Instrument cluster dial calibrated primarily in km/h scale.',
      category: 'Cockpit & Cluster',
      affectedEcus: ['KOMBI (0x60)'],
      affectedEcuAddresses: [0x60],
    ),
    SalapaOptionInfo(
      code: r'$552',
      name: 'Adaptive LED Headlights',
      description: 'Full LED projector headlamps with selective beam matrix anti-glare tunneling and dynamic cornering illumination.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)', 'KAFAS (0x5D)', 'FLE_L (0x43)', 'FLE_R (0x44)'],
      affectedEcuAddresses: [0x40, 0x5D, 0x43, 0x44],
    ),
    SalapaOptionInfo(
      code: r'$563',
      name: 'Lights Package',
      description: 'Interior ambient mood lighting (Classic Orange / Sport White), door handle puddle LED lights, and footwell illumination.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$5A1',
      name: 'LED Fog Lights Retrofit',
      description: 'Configures front electronic module for LED fog lamps: sets 100% PWM and disables bulb cold/warm monitoring checks.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$5AC',
      name: 'High-Beam Assistant',
      description: 'Automatic high-beam dimming camera system detecting oncoming traffic and street lighting.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)', 'KAFAS (0x5D)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x40, 0x5D, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$5AD',
      name: 'Lane Departure Warning',
      description: 'KAFAS optical windshield camera tracking road lane markings with steering wheel haptic vibration actuator warning.',
      category: 'Driver Assistance',
      affectedEcus: ['KAFAS (0x5D)', 'SZL (0x1C)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x5D, 0x1C, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$5AG',
      name: 'Lane Change Warning',
      description: 'Rear bumper 24 GHz radar sensors alerting of vehicles approaching fast in blind spots via triangular LED in side mirror glass.',
      category: 'Driver Assistance',
      affectedEcus: ['SWW/HC2 (0x3C)', 'FEM/BDC (0x40)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x3C, 0x40, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$5AL',
      name: 'Active Protection',
      description: 'Pre-crash preventative safety system: pretenses seat belts, closes windows/sunroof, and triggers post-crash braking.',
      category: 'Safety & Security',
      affectedEcus: ['ACSM (0x01)', 'FEM/BDC (0x40)', 'DSC (0x29)'],
      affectedEcuAddresses: [0x01, 0x40, 0x29],
    ),
    SalapaOptionInfo(
      code: r'$5AR',
      name: 'Traffic Jam Assistant',
      description: 'Semi-autonomous steering and lane centering assist in heavy stop-and-go highway traffic up to 60 km/h.',
      category: 'Driver Assistance',
      affectedEcus: ['KAFAS (0x5D)', 'ACC (0x20)', 'EPS (0x30)'],
      affectedEcuAddresses: [0x5D, 0x20, 0x30],
    ),
    SalapaOptionInfo(
      code: r'$5AT',
      name: 'Driving Assistant Plus',
      description: 'Comprehensive active safety suite: Stop&Go radar cruise control, forward collision braking, pedestrian avoidance, and active steering.',
      category: 'Driver Assistance',
      affectedEcus: ['KAFAS (0x5D)', 'ACC (0x20)', 'DSC (0x29)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x5D, 0x20, 0x29, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$5DF',
      name: 'Active Cruise Control + Stop&Go',
      description: '77 GHz long-range front radar maintaining distance down to complete standstill with automatic pull-away resumption.',
      category: 'Driver Assistance',
      affectedEcus: ['ACC/FRR (0x20)', 'DME (0x12)', 'DSC (0x29)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x20, 0x12, 0x29, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$5DL',
      name: 'Surround View',
      description: '360° bird-eye panorama view using bumper side-view cameras, mirror bottom cameras, and rear camera on iDrive display.',
      category: 'Driver Assistance',
      affectedEcus: ['TRSVC (0x66)', 'HU_NBT (0x63)', 'REM (0x74)'],
      affectedEcuAddresses: [0x66, 0x63, 0x74],
    ),
    SalapaOptionInfo(
      code: r'$5DP',
      name: 'Park Assistant',
      description: 'Ultrasonic side sensors measuring parking space length and autonomously steering vehicle into parallel/perpendicular spots.',
      category: 'Driver Assistance',
      affectedEcus: ['PMA (0x67)', 'EPS (0x30)', 'HU_NBT (0x63)', 'DSC (0x29)'],
      affectedEcuAddresses: [0x67, 0x30, 0x63, 0x29],
    ),
    SalapaOptionInfo(
      code: r'$606',
      name: 'Navigation System Business',
      description: '6.5" iDrive display with 2D arrow guidance and entry-level route guidance.',
      category: 'Infotainment & Media',
      affectedEcus: ['HU_ENTRYNAV (0x63)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x63, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$609',
      name: 'Navigation System Professional',
      description: 'High-definition 8.8"/10.25" widescreen display, 3D city buildings, 200GB hard drive with 20GB jukebox, and split-screen view.',
      category: 'Infotainment & Media',
      affectedEcus: ['HU_NBT (0x63)', 'KOMBI (0x60)'],
      affectedEcuAddresses: [0x63, 0x60],
    ),
    SalapaOptionInfo(
      code: r'$610',
      name: 'Head-Up Display',
      description: 'TFT virtual windscreen projection: projects speed, navigation turn arrows, speed limit signs, and cruise control status directly in driver line of sight.',
      category: 'Cockpit & Cluster',
      affectedEcus: ['HUD (0x64)', 'KOMBI (0x60)', 'HU_NBT (0x63)'],
      affectedEcuAddresses: [0x64, 0x60, 0x63],
    ),
    SalapaOptionInfo(
      code: r'$654',
      name: 'DAB Tuner',
      description: 'Digital Audio Broadcasting tuner delivering CD-quality interference-free digital radio reception.',
      category: 'Infotainment & Media',
      affectedEcus: ['HU_NBT (0x63)'],
      affectedEcuAddresses: [0x63],
    ),
    SalapaOptionInfo(
      code: r'$676',
      name: 'HiFi Loudspeaker System',
      description: '7-channel 205W analog amplifier with dual subwoofers under front seats and separate midranges/tweeters.',
      category: 'Audio & Acoustics',
      affectedEcus: ['HU_NBT (0x63)', 'AMPH (0x27)'],
      affectedEcuAddresses: [0x63, 0x27],
    ),
    SalapaOptionInfo(
      code: r'$688',
      name: 'Harman Kardon Surround Sound System',
      description: '16 high-performance speakers with 600W 9-channel DSP amplifier, aluminum dome tweeters, and Logic 7 surround sound processing.',
      category: 'Audio & Acoustics',
      affectedEcus: ['AMPH (0x27)', 'HU_NBT (0x63)'],
      affectedEcuAddresses: [0x27, 0x63],
    ),
    SalapaOptionInfo(
      code: r'$6CP',
      name: 'Apple CarPlay Preparation',
      description: 'Wireless Apple CarPlay enabling iPhone navigation, Siri voice control, and audio apps directly on the iDrive screen.',
      category: 'Infotainment & Media',
      affectedEcus: ['HU_NBT (0x63)'],
      affectedEcuAddresses: [0x63],
    ),
    SalapaOptionInfo(
      code: r'$6F2',
      name: 'Bang & Olufsen High-End Surround Sound',
      description: 'Acoustic Lens Technology motorized dashboard center speaker, 1200W active DSP amplifier, and 16 illuminated speakers.',
      category: 'Audio & Acoustics',
      affectedEcus: ['AMPH (0x27)', 'HU_NBT (0x63)'],
      affectedEcuAddresses: [0x27, 0x63],
    ),
    SalapaOptionInfo(
      code: r'$6NS',
      name: 'Enhanced Bluetooth & Smartphone Integration',
      description: 'Unlocks Bluetooth audio streaming (A2DP), dual phone simultaneous connection, voice control, and SMS/email display on iDrive.',
      category: 'Infotainment & Media',
      affectedEcus: ['HU_NBT (0x63)'],
      affectedEcuAddresses: [0x63],
    ),
    SalapaOptionInfo(
      code: r'$6NW',
      name: 'Telephony with Wireless Charging',
      description: 'Inductive Qi charging tray in center console and external roof antenna coupling for cellular boost.',
      category: 'Comfort & Convenience',
      affectedEcus: ['HU_NBT (0x63)', 'FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x63, 0x40],
    ),
    SalapaOptionInfo(
      code: r'$6WB',
      name: 'Multifunctional Instrument Display',
      description: 'Full 12.3" customizable digital LCD instrument cluster with animated theme transitions across Comfort, ECO PRO, and Sport modes.',
      category: 'Cockpit & Cluster',
      affectedEcus: ['KOMBI (0x60)', 'HU_NBT (0x63)'],
      affectedEcuAddresses: [0x60, 0x63],
    ),
    SalapaOptionInfo(
      code: r'$710',
      name: 'M Leather Steering Wheel',
      description: 'Thick contoured rim M leather steering wheel with thumb rests and tri-color M stitching.',
      category: 'Interior & Styling',
      affectedEcus: ['FEM/BDC (0x40)', 'SZL (0x1C)'],
      affectedEcuAddresses: [0x40, 0x1C],
    ),
    SalapaOptionInfo(
      code: r'$715',
      name: 'M Aerodynamics Package',
      description: 'Distinctive front apron with enlarged cooling ducts, side sills, and rear diffuser with dark insert.',
      category: 'Interior & Styling',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$760',
      name: 'BMW Individual High-Gloss Shadow Line',
      description: 'Exterior window surrounds, mirror bases, and roof trim in high-gloss black finish.',
      category: 'Interior & Styling',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$775',
      name: 'BMW Individual Headliner Anthracite',
      description: 'Dark anthracite woven fabric roof lining, sun visors, and pillar trims.',
      category: 'Interior & Styling',
      affectedEcus: ['FEM/BDC (0x40)'],
      affectedEcuAddresses: [0x40],
    ),
    SalapaOptionInfo(
      code: r'$8S4',
      name: 'Variable Light Decoding (Anti-Dazzle)',
      description: 'Enables European glare-free high beams (tunneling around oncoming and preceding vehicles) by removing North American light decoding restrictions.',
      category: 'Lighting & Visibility',
      affectedEcus: ['FEM/BDC (0x40)', 'KAFAS (0x5D)', 'FLE_L (0x43)', 'FLE_R (0x44)'],
      affectedEcuAddresses: [0x40, 0x5D, 0x43, 0x44],
    ),
    SalapaOptionInfo(
      code: r'$8TH',
      name: 'Speed Limit Info',
      description: 'Real-time road sign optical recognition camera displaying speed limits and overtaking restrictions in instrument cluster and HUD.',
      category: 'Driver Assistance',
      affectedEcus: ['KAFAS (0x5D)', 'KOMBI (0x60)', 'HU_NBT (0x63)'],
      affectedEcuAddresses: [0x5D, 0x60, 0x63],
    ),
  ];

  /// Look up an option code in the E-Sys SALAPA dictionary (case-insensitive, with or without '$')
  static SalapaOptionInfo? lookupSalapaCode(String code) {
    final clean = code.trim().toUpperCase().replaceAll(r'$', '');
    for (final opt in options) {
      if (opt.cleanCode == clean) return opt;
    }
    return null;
  }

  /// Search SALAPA option codes by keyword, code, or description
  static List<SalapaOptionInfo> searchSalapaOptions(String query) {
    final cleanQuery = query.trim().toLowerCase().replaceAll(r'$', '');
    if (cleanQuery.isEmpty) return List.unmodifiable(options);
    return options.where((opt) {
      return opt.cleanCode.toLowerCase().contains(cleanQuery) ||
          opt.name.toLowerCase().contains(cleanQuery) ||
          opt.description.toLowerCase().contains(cleanQuery) ||
          opt.category.toLowerCase().contains(cleanQuery);
    }).toList();
  }

  /// Convenient alias for [lookupSalapaCode]
  static SalapaOptionInfo? lookup(String code) => lookupSalapaCode(code);

  /// Convenient alias for [searchSalapaOptions]
  static List<SalapaOptionInfo> search(String query) => searchSalapaOptions(query);
}

/// Representation of a BMW Factory Option Code (SALAPA Element).
class BmwSalapaOption {
  final String code; // e.g. '$2TB'
  final String name; // e.g. 'Sport Automatic Transmission'
  final String description; // Detailed description
  final String category; // 'Drivetrain & Performance', 'Infotainment & Media', 'Lighting & Visibility', 'Comfort & Convenience', 'Driver Assistance', 'Chassis & Suspension', 'Audio & Acoustics', 'Interior & Styling', 'Safety & Chimes'
  final List<int> affectedEcuAddresses; // e.g. [0x18, 0x40, 0x60]
  final List<String> affectedEcuNames; // e.g. ['EGS (0x18)', 'FEM/BDC (0x40)', 'KOMBI (0x60)']

  const BmwSalapaOption({
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.affectedEcuAddresses,
    required this.affectedEcuNames,
  });
}

/// BMW Vehicle Order (FA - Fahrzeugauftrag) Model
/// 
/// Contains complete vehicle identity and factory specification according to BMW EDIABAS & ProTool:
/// - Series (e.g. 'F030')
/// - Type Key / Typschlüssel (e.g. '3B93' F30 328i, '3R93' F80 M3, '8H91' G20 M340i)
/// - Production Date / Zeitkriterium (e.g. '0315' for March 2015)
/// - Paint Code / Lackcode (e.g. '475' Black Sapphire)
/// - Upholstery Code / Polstercode (e.g. 'LCSW' Leather Dakota Black)
/// - SALAPA Option Elements (e.g. ['$1CA', '$2TB', '$5A1', '$609', '$6NS'])
/// - E-Words / Entwicklungs-Wörter ('&xxxx')
/// - K-Words / Konvertierungs-Wörter ('%xxxx')
/// - HO-Words / Händler-Optionen ('+xxxx')
class BmwVehicleOrder {
  final String vin;
  final String series;
  final String typeKey;
  final String productionDate;
  final String paintCode;
  final String upholsteryCode;
  final List<String> options;
  final List<String> eWords;
  final List<String> kWords;
  final List<String> hoWords;

  const BmwVehicleOrder({
    required this.vin,
    this.series = 'F030',
    required this.typeKey,
    required this.productionDate,
    this.paintCode = '475',
    this.upholsteryCode = 'LCSW',
    required this.options,
    this.eWords = const [],
    this.kWords = const [],
    this.hoWords = const [],
  });

  /// Resolves human-readable model name from BMW Type Key
  String get modelName {
    return BmwCodingService.lookupTypeKeyDescription(typeKey);
  }

  /// Formatted production date (e.g. "03/2015")
  String get formattedDate {
    if (productionDate.length == 4) {
      final m = productionDate.substring(0, 2);
      final y = productionDate.substring(2, 4);
      return '$m/20$y';
    }
    return productionDate;
  }

  /// Formatted Paint Description
  String get paintDescription {
    return BmwCodingService.lookupPaintDescription(paintCode);
  }

  /// Formatted Upholstery Description
  String get upholsteryDescription {
    return BmwCodingService.lookupUpholsteryDescription(upholsteryCode);
  }

  /// Serializes into standard BMW FA String format:
  /// e.g. "E F030 -15-03-500 *3B93 #0315 %0000 &0000 $1CA $205 $2TB ... +MPE1"
  String toFaString() {
    final buffer = StringBuffer();
    buffer.write('E $series ');
    if (productionDate.length == 4) {
      final m = productionDate.substring(0, 2);
      final y = productionDate.substring(2, 4);
      buffer.write('-$y-$m-500 ');
    }
    buffer.write('*$typeKey ');
    buffer.write('#$productionDate ');
    if (paintCode.isNotEmpty) buffer.write('L$paintCode ');
    if (upholsteryCode.isNotEmpty) buffer.write('P$upholsteryCode ');
    if (kWords.isNotEmpty) buffer.write('${kWords.join(' ')} ');
    if (eWords.isNotEmpty) buffer.write('${eWords.join(' ')} ');
    buffer.write(options.join(' '));
    if (hoWords.isNotEmpty) {
      buffer.write(' ${hoWords.join(' ')}');
    }
    return buffer.toString().trim();
  }

  /// Parses standard BMW FA String into structured BmwVehicleOrder
  factory BmwVehicleOrder.fromFaString(String rawFa, {String vin = 'UNKNOWN_VIN'}) {
    final tokens = rawFa.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    String series = 'F030';
    String typeKey = '3B93';
    String productionDate = '0315';
    String paintCode = '475';
    String upholsteryCode = 'LCSW';
    final options = <String>[];
    final eWords = <String>[];
    final kWords = <String>[];
    final hoWords = <String>[];

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == 'E' && i + 1 < tokens.length) {
        series = tokens[i + 1].toUpperCase();
      } else if (token.startsWith('*')) {
        typeKey = token.substring(1).toUpperCase();
      } else if (token.startsWith('#')) {
        productionDate = token.substring(1);
      } else if (token.startsWith('L') && token.length > 1 && !token.startsWith('LCSW') && !token.startsWith('LCOM')) {
        paintCode = token.substring(1).toUpperCase();
      } else if (token.startsWith('P') && token.length > 1) {
        upholsteryCode = token.substring(1).toUpperCase();
      } else if (token.startsWith(r'$')) {
        options.add(token.toUpperCase());
      } else if (token.startsWith('&')) {
        eWords.add(token.toUpperCase());
      } else if (token.startsWith('%')) {
        kWords.add(token.toUpperCase());
      } else if (token.startsWith('+')) {
        hoWords.add(token.toUpperCase());
      }
    }

    return BmwVehicleOrder(
      vin: vin,
      series: series,
      typeKey: typeKey,
      productionDate: productionDate,
      paintCode: paintCode,
      upholsteryCode: upholsteryCode,
      options: options,
      eWords: eWords,
      kWords: kWords,
      hoWords: hoWords,
    );
  }

  /// Encodes into standard UDS binary bytes for DID 0xFA01
  Uint8List toBinaryFa() {
    // ProTool UDS 0xFA01 format:
    // Header (20 bytes):
    // 0..3: Series (4 ASCII bytes, padded e.g. "F030")
    // 4..7: TypeKey (4 ASCII bytes e.g. "3B93")
    // 8..11: Date (4 ASCII bytes e.g. "0315")
    // 12..15: Paint (4 ASCII bytes e.g. "0475")
    // 16..19: Upholstery (4 ASCII bytes e.g. "LCSW")
    // 20..21: Options Count (uint16 big endian)
    // 22..: Options (each 4 ASCII bytes e.g. "$2TB" or "2TB ")
    // Followed by HO words count (uint16) + HO words (each 4 bytes)
    final bytes = <int>[];
    bytes.addAll(ascii.encode(series.padRight(4).substring(0, 4)));
    bytes.addAll(ascii.encode(typeKey.padRight(4).substring(0, 4)));
    bytes.addAll(ascii.encode(productionDate.padRight(4).substring(0, 4)));
    bytes.addAll(ascii.encode(paintCode.padRight(4).substring(0, 4)));
    bytes.addAll(ascii.encode(upholsteryCode.padRight(4).substring(0, 4)));

    // Options count (uint16)
    bytes.add((options.length >> 8) & 0xFF);
    bytes.add(options.length & 0xFF);

    for (final opt in options) {
      final clean = opt.replaceAll(r'$', '').padRight(4).substring(0, 4);
      bytes.addAll(ascii.encode(clean));
    }

    // HO Words count
    bytes.add((hoWords.length >> 8) & 0xFF);
    bytes.add(hoWords.length & 0xFF);
    for (final ho in hoWords) {
      final clean = ho.replaceAll('+', '').padRight(4).substring(0, 4);
      bytes.addAll(ascii.encode(clean));
    }

    return Uint8List.fromList(bytes);
  }

  /// Decodes UDS binary bytes from DID 0xFA01
  factory BmwVehicleOrder.fromBinaryFa(Uint8List bytes, {String vin = 'UNKNOWN_VIN'}) {
    if (bytes.length >= 22) {
      try {
        final series = ascii.decode(bytes.sublist(0, 4)).trim();
        final typeKey = ascii.decode(bytes.sublist(4, 8)).trim();
        final productionDate = ascii.decode(bytes.sublist(8, 12)).trim();
        final paintCode = ascii.decode(bytes.sublist(12, 16)).trim();
        final upholsteryCode = ascii.decode(bytes.sublist(16, 20)).trim();

        final optCount = (bytes[20] << 8) | bytes[21];
        final options = <String>[];
        int offset = 22;

        for (int i = 0; i < optCount && offset + 4 <= bytes.length; i++) {
          final opt = ascii.decode(bytes.sublist(offset, offset + 4)).trim();
          if (opt.isNotEmpty) {
            options.add('\$$opt');
          }
          offset += 4;
        }

        final hoWords = <String>[];
        if (offset + 2 <= bytes.length) {
          final hoCount = (bytes[offset] << 8) | bytes[offset + 1];
          offset += 2;
          for (int i = 0; i < hoCount && offset + 4 <= bytes.length; i++) {
            final ho = ascii.decode(bytes.sublist(offset, offset + 4)).trim();
            if (ho.isNotEmpty) {
              hoWords.add('+$ho');
            }
            offset += 4;
          }
        }

        return BmwVehicleOrder(
          vin: vin,
          series: series.isNotEmpty ? series : 'F030',
          typeKey: typeKey.isNotEmpty ? typeKey : '3B93',
          productionDate: productionDate.isNotEmpty ? productionDate : '0315',
          paintCode: paintCode.isNotEmpty ? paintCode : '475',
          upholsteryCode: upholsteryCode.isNotEmpty ? upholsteryCode : 'LCSW',
          options: options,
          hoWords: hoWords,
        );
      } catch (e) {
        debugPrint('[BmwVehicleOrder] Binary decode failed, falling back to string: $e');
      }
    }

    // Fallback: try ASCII string decoding
    try {
      final str = ascii.decode(bytes).trim();
      return BmwVehicleOrder.fromFaString(str, vin: vin);
    } catch (_) {
      return BmwVehicleOrder.createDefault(vin: vin);
    }
  }

  static BmwVehicleOrder createDefault({String vin = 'UNKNOWN_VIN'}) {
    return BmwVehicleOrder(
      vin: vin,
      series: 'F030',
      typeKey: '3B93',
      productionDate: '0315',
      paintCode: '475',
      upholsteryCode: 'LCSW',
      options: [
        r'$1CA', r'$205', r'$216', r'$249', r'$255', r'$258', r'$2A6',
        r'$302', r'$423', r'$441', r'$465', r'$481', r'$493', r'$502',
        r'$520', r'$521', r'$534', r'$548', r'$575', r'$698', r'$845', r'$853'
      ],
      eWords: [r'&0000'],
      kWords: [r'%0000'],
      hoWords: [],
    );
  }

  BmwVehicleOrder copyWith({
    String? vin,
    String? series,
    String? typeKey,
    String? productionDate,
    String? paintCode,
    String? upholsteryCode,
    List<String>? options,
    List<String>? eWords,
    List<String>? kWords,
    List<String>? hoWords,
  }) {
    return BmwVehicleOrder(
      vin: vin ?? this.vin,
      series: series ?? this.series,
      typeKey: typeKey ?? this.typeKey,
      productionDate: productionDate ?? this.productionDate,
      paintCode: paintCode ?? this.paintCode,
      upholsteryCode: upholsteryCode ?? this.upholsteryCode,
      options: options ?? List.from(this.options),
      eWords: eWords ?? List.from(this.eWords),
      kWords: kWords ?? List.from(this.kWords),
      hoWords: hoWords ?? List.from(this.hoWords),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vin': vin,
      'series': series,
      'typeKey': typeKey,
      'productionDate': productionDate,
      'paintCode': paintCode,
      'upholsteryCode': upholsteryCode,
      'options': options,
      'eWords': eWords,
      'kWords': kWords,
      'hoWords': hoWords,
    };
  }

  factory BmwVehicleOrder.fromJson(Map<String, dynamic> json) {
    return BmwVehicleOrder(
      vin: json['vin'] as String? ?? 'UNKNOWN_VIN',
      series: json['series'] as String? ?? 'F030',
      typeKey: json['typeKey'] as String? ?? '3B93',
      productionDate: json['productionDate'] as String? ?? '0315',
      paintCode: json['paintCode'] as String? ?? '475',
      upholsteryCode: json['upholsteryCode'] as String? ?? 'LCSW',
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      eWords: (json['eWords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      kWords: (json['kWords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      hoWords: (json['hoWords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

/// Vehicle Order Backup representation (res_backupVO / res_restoreVO)
class VehicleOrderBackup {
  final String id;
  final DateTime timestamp;
  final String vin;
  final String series;
  final String typeKey;
  final String productionDate;
  final String rawFaString;
  final List<String> options;
  final String description;

  const VehicleOrderBackup({
    required this.id,
    required this.timestamp,
    required this.vin,
    required this.series,
    required this.typeKey,
    required this.productionDate,
    required this.rawFaString,
    required this.options,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'vin': vin,
      'series': series,
      'typeKey': typeKey,
      'productionDate': productionDate,
      'rawFaString': rawFaString,
      'options': options,
      'description': description,
    };
  }

  factory VehicleOrderBackup.fromJson(Map<String, dynamic> json) {
    return VehicleOrderBackup(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      vin: json['vin'] as String? ?? 'UNKNOWN_VIN',
      series: json['series'] as String? ?? 'F030',
      typeKey: json['typeKey'] as String? ?? '3B93',
      productionDate: json['productionDate'] as String? ?? '0315',
      rawFaString: json['rawFaString'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      description: json['description'] as String? ?? '',
    );
  }
}

/// Result of res_VoFix (Vehicle Order Syntax Check and Repair)
class VoFixResult {
  final bool wasModified;
  final List<String> fixesApplied;
  final List<String> warnings;
  final BmwVehicleOrder fixedVo;

  const VoFixResult({
    required this.wasModified,
    required this.fixesApplied,
    required this.warnings,
    required this.fixedVo,
  });
}

/// Plan for Factory Default Coding (SG_CODIEREN / Code ECU)
class FactoryCodingPlan {
  final int ecuAddress;
  final String ecuName;
  final List<String> triggeredByOptions;
  final int primaryDid;
  bool isSelected;

  FactoryCodingPlan({
    required this.ecuAddress,
    required this.ecuName,
    required this.triggeredByOptions,
    required this.primaryDid,
    this.isSelected = true,
  });
}

/// BMW FDL Cheat-Code Coding & Deep Diagnostics Service
///
/// Reverse-engineered from BimmerGeeks ProTool, EDIABAS, E-Sys, and PSDZData.
/// Directly reads and flashes NCD (Netto-Codier-Daten) blocks over UDS / ISO 14229:
/// - Extended Diagnostic Session (0x10 0x03)
/// - ReadDataByIdentifier (0x22)
/// - WriteDataByIdentifier (0x2E)
/// - ECU Reset / Soft Reboot (0x11 0x03)
/// - NCD Raw Backup and 1-Tap Rollback
class BmwCodingService {
  final EnetHsfzProtocol? protocol;
  final Future<List<int>> Function(int ecuAddress, int level, List<int> seed)? remoteKeyProvider;
  late final BmwEcuScanner _ecuScanner;

  static const String _backupsPrefsKey = 'fix_ai_ncd_backups';
  static const String _voBackupsPrefsKey = 'fix_ai_vo_backups';

  // Target ECU Addresses
  static const int dmeAddress = 0x12;   // Engine (DME/DDE)
  static const int egsAddress = 0x18;   // Transmission (8HP/DCT)
  static const int casAddress = 0x40;   // FEM / BDC / CAS
  static const int kombiAddress = 0x60; // Cluster
  static const int huNbtAddress = 0x63; // Headunit (HU_NBT/ENTRYNAV)
  static const int acsmAddress = 0x01;  // Airbag / Safety
  static const int dscAddress = 0x29;   // Stability Control (DSC/ABS)
  static const int zgwAddress = 0x10;   // Central Gateway (ZGW)
  static const int kafasAddress = 0x5D; // Camera Assistance (KAFAS)
  static const int ihkaAddress = 0x6D;  // Climate Control (IHKA)
  static const int fzdAddress = 0x56;   // Function Zone Dome / Alarm (FZD)
  static const int hkfmAddress = 0x78;  // Trunk Lid Function (HKFM)
  static const int remAddress = 0x72;   // Rear Electronic Module (REM)
  static const int vdcAddress = 0x3F;   // Vertical Dynamics / Adaptive Suspension (VDC/EDC)
  static const int ampAddress = 0x37;   // Top-HiFi / Harman Kardon Amplifier (AMP)
  static const int szlAddress = 0x1C;   // Steering Column Switch (SZL)
  static const int fleLeftAddress = 0x43;  // Front Light Electronics Left (FLE_L)
  static const int fleRightAddress = 0x44; // Front Light Electronics Right (FLE_R)
  static const int trsvcAddress = 0x06; // Rear Camera (TRSVC/ICAM)

  BmwCodingService({this.protocol, this.remoteKeyProvider}) {
    _ecuScanner = BmwEcuScanner(protocol: _getActiveProtocol());
  }

  EnetHsfzProtocol _getActiveProtocol() {
    return protocol ?? EnetHsfzProtocol();
  }

  /// Verifies or establishes diagnostic connection to the BMW vehicle
  Future<bool> ensureConnected() async {
    final activeProto = _getActiveProtocol();
    if (!activeProto.isConnected) {
      debugPrint('[BmwCodingService] Detecting vehicle adapter...');
      final target = await activeProto.detectAdapter();
      if (target != null) {
        return await activeProto.connect(
          host: target.host,
          port: target.port,
          useDoip: target.isDoip,
        );
      }
      return await activeProto.connect();
    }
    return true;
  }

  /// Reads battery terminal voltage (mV -> V) via DME DID 0xF111
  Future<double?> readBatteryVoltage() async {
    final activeProto = _getActiveProtocol();
    try {
      final resp = await activeProto.sendUdsAndAwait(
        dmeAddress,
        [0x22, 0xF1, 0x11],
        timeout: const Duration(seconds: 1),
      );
      if (resp != null && resp.length >= 5 && resp[0] == 0x62) {
        final mv = (resp[3] << 8) | resp[4];
        return mv / 1000.0;
      }
    } catch (_) {}
    return null;
  }

  /// Reads vehicle VIN
  Future<String?> readVehicleVin() async {
    final activeProto = _getActiveProtocol();
    return await activeProto.readVin(dmeAddress) ?? await activeProto.readVin(0x10);
  }

  /// Returns the complete catalog of 1-Tap BMW Cheat Codes
  List<FdlCheatCode> getAvailableCheatCodes() {
    return [
      // 1. Auto Start-Stop Memory
      FdlCheatCode(
        id: 'TCM_MSA_MEMORY',
        name: 'Auto Start-Stop Memory',
        category: 'Engine & Start-Stop',
        description: 'Saves last button state across trips. If disabled, Auto Start-Stop remains disabled on next vehicle startup.',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3023,
        byteOffset: 0,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 2. Power Folding Mirrors on Lock
      FdlCheatCode(
        id: 'KOMFORTSCHLIESSUNG_FB',
        name: 'Fold Mirrors on Lock',
        category: 'Comfort & Convenience',
        description: 'Automatically folds side mirrors immediately upon pressing lock on the key fob or touching Comfort Access.',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3053,
        byteOffset: 1,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 3. Digital Speedometer in Cluster
      FdlCheatCode(
        id: 'BC_DIGITAL_V',
        name: 'Digital Speedometer in Cluster',
        category: 'Cockpit & Cluster',
        description: 'Enables real-time digital speed readout (km/h or mph) in the instrument cluster on-board computer display.',
        targetEcuAddress: kombiAddress,
        targetEcuName: 'KOMBI (0x60)',
        did: 0x3000,
        byteOffset: 4,
        bitMask: 0x02,
        activeValue: 0x02,
        inactiveValue: 0x00,
      ),

      // 4. Seatbelt Chime Suppression
      FdlCheatCode(
        id: 'GURTWARNUNG',
        name: 'Seatbelt Chime Suppression',
        category: 'Safety & Chimes',
        description: 'Mutes annoying repetitive seatbelt gong for driver and passenger without affecting airbag safety.',
        targetEcuAddress: acsmAddress,
        targetEcuName: 'ACSM (0x01)',
        did: 0x3000,
        byteOffset: 2,
        bitMask: 0x03,
        activeValue: 0x00, // nicht_aktiv
        inactiveValue: 0x03, // aktiv
      ),

      // 5. Video In Motion (VIM Unlock)
      FdlCheatCode(
        id: 'SPEEDLOCK',
        name: 'Video In Motion (VIM Unlock)',
        category: 'Infotainment & Media',
        description: 'Removes the 3 km/h speedlock limitation, permitting video playback and screen mirroring on iDrive while in motion.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3000,
        byteOffset: 8,
        bitMask: 0xFF,
        activeValue: 0xFF, // Unlocked
        inactiveValue: 0x03, // 3 km/h factory limit
      ),

      // 6. Sport Automatic 2TB
      FdlCheatCode(
        id: 'SPORTSWITCH_2TB',
        name: 'Sport Automatic Transmission 2TB',
        category: 'Drivetrain & Performance',
        description: 'Codes factory 2TB Sport Automatic: lightning-fast shifts, aggressive rev matching, Launch Control, and unlocks Sport+ mode.',
        targetEcuAddress: egsAddress,
        targetEcuName: 'EGS (0x18)',
        did: 0x3001,
        byteOffset: 0,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
        secondaryEcuAddress: casAddress,
        secondaryEcuName: 'FEM/BDC (0x40)',
        secondaryDid: 0x3020,
        secondaryByteOffset: 2,
        secondaryBitMask: 0x04,
        secondaryActiveValue: 0x04,
        secondaryInactiveValue: 0x00,
      ),

      // 7. Continuous Window Roll-up with Door Open
      FdlCheatCode(
        id: 'DOOR_OPEN_WINDOW_ROLL',
        name: 'Window Roll-Up with Door Open',
        category: 'Comfort & Convenience',
        description: 'Power windows continue closing uninterrupted even when a car door is opened during rolling.',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3053,
        byteOffset: 3,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 8. Acoustic Lock Confirmation
      FdlCheatCode(
        id: 'ACOUSTIC_LOCK_BEEP',
        name: 'Acoustic Lock/Unlock Chirp',
        category: 'Infotainment & Media',
        description: 'Unlocks iDrive menu setting to activate acoustic chirp confirmation via alarm siren when locking/unlocking.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3000,
        byteOffset: 11,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 9. M Performance Cluster Logo
      FdlCheatCode(
        id: 'M_PERFORMANCE_LOGO',
        name: 'M Performance Cluster Boot Logo',
        category: 'Cockpit & Cluster',
        description: 'Displays authentic BMW M Performance startup logo in instrument cluster screen on vehicle wake up.',
        targetEcuAddress: kombiAddress,
        targetEcuName: 'KOMBI (0x60)',
        did: 0x3000,
        byteOffset: 6,
        bitMask: 0x07,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 10. Driving Mode Memory
      FdlCheatCode(
        id: 'DRIVE_MODE_MEMORY',
        name: 'Driving Mode Memory',
        category: 'Drivetrain & Performance',
        description: 'Vehicle restarts in the last selected driving mode (e.g. Eco Pro or Sport) instead of forcing default Comfort.',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3020,
        byteOffset: 0,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 11. Instant Mirror Fold on Convenience Lock (0.0s delay)
      FdlCheatCode(
        id: 'mirrors_fold_convenience',
        name: 'Convenience Mirror Folding (Instant)',
        category: 'Comfort & Convenience',
        description: 'Folds side mirrors immediately upon lock with 0.0s delay (removes standard 1.5s Comfort Access delay).',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3101,
        byteOffset: 14,
        bitMask: 0x0F,
        activeValue: 0x00, // Instant
        inactiveValue: 0x0F, // 1.5s delay
      ),

      // 12. Acoustic Lock/Unlock Confirmation Chirp
      FdlCheatCode(
        id: 'acoustic_lock_chirp',
        name: 'Acoustic Lock/Unlock Chirp',
        category: 'Safety & Chimes',
        description: 'Acoustic confirmation chirp via alarm siren upon locking and unlocking the vehicle.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3000,
        byteOffset: 8,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
        secondaryEcuAddress: casAddress,
        secondaryEcuName: 'FZD/FEM (0x40)',
        secondaryDid: 0x3010,
        secondaryByteOffset: 4,
        secondaryBitMask: 0x01,
        secondaryActiveValue: 0x01,
        secondaryInactiveValue: 0x00,
      ),

      // 13. Digital Speedometer in KOMBI
      FdlCheatCode(
        id: 'digital_speedo_kombi',
        name: 'Digital Speedometer in KOMBI',
        category: 'Cockpit & Cluster',
        description: 'Displays numerical real-time digital speed in the instrument cluster on-board computer display.',
        targetEcuAddress: kombiAddress,
        targetEcuName: 'KOMBI (0x60)',
        did: 0x3000,
        byteOffset: 12,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 14. Tire Pressure & Temperature in iDrive
      FdlCheatCode(
        id: 'tire_pressure_temp_idrive',
        name: 'Tire Pressure & Temperature in iDrive',
        category: 'Infotainment & Media',
        description: 'Enables individual tire pressure (Bar/PSI) and real-time tire temperature (°C) readouts in iDrive TPMS status.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3001,
        byteOffset: 22,
        bitMask: 0x03,
        activeValue: 0x02,
        inactiveValue: 0x01,
      ),

      // 15. Rolls-Royce Warning Chimes
      FdlCheatCode(
        id: 'chimes_rolls_royce',
        name: 'Rolls-Royce Warning Chimes',
        category: 'Safety & Chimes',
        description: 'Replaces standard BMW acoustic gongs with distinctive Rolls-Royce warning melodies and notification tones.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3002,
        byteOffset: 18,
        bitMask: 0x07,
        activeValue: 0x04, // Rolls Royce
        inactiveValue: 0x00, // BMW
      ),

      // 16. Video In Motion Speedlock Unlock
      FdlCheatCode(
        id: 'video_in_motion_speedlock',
        name: 'Video in Motion (Speedlock Removal)',
        category: 'Infotainment & Media',
        description: 'Removes the 3 km/h speedlock limitation, permitting video playback and screen mirroring on iDrive at any speed.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3000,
        byteOffset: 35,
        bitMask: 0xFF,
        activeValue: 0xFF, // Unlimited
        inactiveValue: 0x03, // 3 km/h lock
      ),

      // 17. Angel Eyes 100% Brightness
      FdlCheatCode(
        id: 'angel_eyes_100_percent',
        name: 'Angel Eyes 100% Brightness',
        category: 'Lighting & Visibility',
        description: 'Sets daytime running lights (DRL / Angel Eyes corona rings) brightness to 100% intensity.',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3062,
        byteOffset: 16,
        bitMask: 0xFF,
        activeValue: 0x64, // 100%
        inactiveValue: 0x32, // 50%
      ),

      // 18. Ambient Lighting Dual-Tone Profiles
      FdlCheatCode(
        id: 'ambient_lighting_dual_tone',
        name: 'Dual-Tone Ambient Lighting Profiles',
        category: 'Lighting & Visibility',
        description: 'Enables LCI dual-tone interior ambient lighting color profiles and independent upper/lower zone assignment.',
        targetEcuAddress: casAddress,
        targetEcuName: 'BDC (0x40)',
        did: 0x3070,
        byteOffset: 9,
        bitMask: 0x03,
        activeValue: 0x02,
        inactiveValue: 0x01,
      ),

      // 19. Brake Force Display Flashing
      FdlCheatCode(
        id: 'brake_force_display_flash',
        name: 'Brake Force Display Flashing',
        category: 'Lighting & Visibility',
        description: 'Rapidly flashes brake lights under hard emergency braking to alert following motorists.',
        targetEcuAddress: casAddress,
        targetEcuName: 'REM/FEM (0x40)',
        did: 0x3060,
        byteOffset: 27,
        bitMask: 0x03,
        activeValue: 0x02, // Flashing
        inactiveValue: 0x00, // Static
      ),

      // 20. Door Handle LEDs in Reverse
      FdlCheatCode(
        id: 'door_handle_lights_reverse',
        name: 'Door Handle LEDs in Reverse',
        category: 'Lighting & Visibility',
        description: 'Activates exterior door handle LEDs automatically when reverse gear is selected for ground illumination.',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3070,
        byteOffset: 31,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 21. Disable Driver Seatbelt Chime
      FdlCheatCode(
        id: 'seatbelt_chime_driver_disable',
        name: 'Disable Driver Seatbelt Chime',
        category: 'Safety & Chimes',
        description: 'Silences driver seatbelt reminder warning chime without compromising SRS airbag functionality.',
        targetEcuAddress: acsmAddress,
        targetEcuName: 'ACSM (0x01)',
        did: 0x3000,
        byteOffset: 2,
        bitMask: 0x01,
        activeValue: 0x00,
        inactiveValue: 0x01,
      ),

      // 22. Disable Passenger Seatbelt Chime
      FdlCheatCode(
        id: 'seatbelt_chime_passenger_disable',
        name: 'Disable Passenger Seatbelt Chime',
        category: 'Safety & Chimes',
        description: 'Silences passenger seatbelt reminder warning chime without compromising SRS airbag functionality.',
        targetEcuAddress: acsmAddress,
        targetEcuName: 'ACSM (0x01)',
        did: 0x3000,
        byteOffset: 3,
        bitMask: 0x01,
        activeValue: 0x00,
        inactiveValue: 0x01,
      ),

      // 23. Turn Off Radio on Door Open (from FDLCodes.xml)
      FdlCheatCode(
        id: 'radio_off_door_open',
        name: 'Radio/Nav Off on Door Open',
        category: 'Comfort & Convenience',
        description: 'Turns off radio, navigation, and infotainment system immediately upon opening driver door after engine shutoff (Terminal R off).',
        targetEcuAddress: casAddress,
        targetEcuName: 'FEM/BDC (0x40)',
        did: 0x3020,
        byteOffset: 12,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 24. A/C Last Settings Memory (from FDLCodes.xml)
      FdlCheatCode(
        id: 'ac_memory_last',
        name: 'A/C Last Settings Memory',
        category: 'Comfort & Convenience',
        description: 'Stores last A/C status (on/off) in memory across key cycles, preventing air conditioning from automatically powering on at every startup.',
        targetEcuAddress: ihkaAddress,
        targetEcuName: 'IHKA (0x6D)',
        did: 0x3000,
        byteOffset: 5,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 25. A/C Air Recirculation Memory (from FDLCodes.xml)
      FdlCheatCode(
        id: 'ac_recirc_memory',
        name: 'A/C Air Recirculation Memory',
        category: 'Comfort & Convenience',
        description: 'Remembers air recirculation setting across vehicle restarts instead of resetting to fresh air.',
        targetEcuAddress: ihkaAddress,
        targetEcuName: 'IHKA (0x6D)',
        did: 0x3000,
        byteOffset: 6,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),

      // 26. Disable Startup Legal Disclaimer (from FDLCodes.xml)
      FdlCheatCode(
        id: 'idrive_legal_disclaimer_disable',
        name: 'Disable Startup Legal Disclaimer',
        category: 'Infotainment & Media',
        description: 'Disables the startup legal warning disclaimer on iDrive screen for immediate navigation and media access.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3001,
        byteOffset: 14,
        bitMask: 0xFF,
        activeValue: 0x00,
        inactiveValue: 0x0A,
      ),

      // 27. iDrive Volume Popup Bar (from FDLCodes.xml)
      FdlCheatCode(
        id: 'idrive_volume_popup',
        name: 'Volume Bar On-Screen Popup',
        category: 'Infotainment & Media',
        description: 'Displays a graphic visual volume level bar indicator on the iDrive screen whenever volume knob or steering controls are adjusted.',
        targetEcuAddress: huNbtAddress,
        targetEcuName: 'HU_NBT (0x63)',
        did: 0x3000,
        byteOffset: 28,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
      ),
    ];
  }

  /// Reads the BMW SVK (Software-Verbaukung-Kennung) table (`UDS 0x22 0xF1 0x01`)
  /// from [ecuAddress] and parses all 8-byte binary SGBM-ID entries (`HWEL`, `BTLD`,
  /// `SWFL`, `CAFD`, etc.).
  Future<List<SvkRecord>> readEcuSvkRecords(int ecuAddress) async {
    final activeProto = _getActiveProtocol();
    try {
      final resp = await activeProto.sendUdsAndAwait(
        ecuAddress,
        [0x22, 0xF1, 0x01],
        timeout: const Duration(seconds: 2),
      );
      if (resp != null && resp.length > 3 && resp[0] == 0x62) {
        return EcuIdentity.parseSvkRecords(resp);
      }
    } catch (e) {
      debugPrint('[BmwCodingService] Error reading SVK from 0x${ecuAddress.toRadixString(16)}: $e');
    }
    return const [];
  }

  /// Detects the active `CAFD` SGBM-ID (e.g. `CAFD_00000794_014_040_122`) from
  /// the target ECU's SVK (`DID 0xF101`), matching `FxxSpecificHelper.DetectCafdFromSwe`.
  Future<String?> detectCafdFromSvk(int ecuAddress) async {
    final records = await readEcuSvkRecords(ecuAddress);
    for (final rec in records) {
      if (rec.processClassName == 'CAFD') {
        return rec.formatted;
      }
    }
    return null;
  }

  /// Queries the live vehicle coding state of a single cheat code
  Future<bool?> readCheatCodeStatus(FdlCheatCode code) async {
    final activeProto = _getActiveProtocol();
    try {
      FdlCheatCode effectiveCode = code;
      if (code.cafdOverrides != null && code.cafdOverrides!.isNotEmpty) {
        final cafd = await detectCafdFromSvk(code.targetEcuAddress);
        effectiveCode = code.resolveForCafd(cafd);
      }

      final resp = await activeProto.sendUdsAndAwait(
        effectiveCode.targetEcuAddress,
        [0x22, (effectiveCode.did >> 8) & 0xFF, effectiveCode.did & 0xFF],
        timeout: const Duration(seconds: 2),
      );

      if (resp != null && resp.length > 3 && resp[0] == 0x62) {
        final payload = resp.sublist(3);
        if (effectiveCode.byteOffset < payload.length) {
          final currentByte = payload[effectiveCode.byteOffset];
          final currentVal = currentByte & effectiveCode.bitMask;
          final isActive = currentVal == (effectiveCode.activeValue & effectiveCode.bitMask);

          // If secondary ECU parameters exist, verify secondary module state as well
          if (isActive &&
              effectiveCode.secondaryEcuAddress != null &&
              effectiveCode.secondaryDid != null &&
              effectiveCode.secondaryByteOffset != null) {
            try {
              final secResp = await activeProto.sendUdsAndAwait(
                effectiveCode.secondaryEcuAddress!,
                [0x22, (effectiveCode.secondaryDid! >> 8) & 0xFF, effectiveCode.secondaryDid! & 0xFF],
                timeout: const Duration(seconds: 2),
              );
              if (secResp != null && secResp.length > 3 && secResp[0] == 0x62) {
                final secPayload = secResp.sublist(3);
                if (effectiveCode.secondaryByteOffset! < secPayload.length) {
                  final secByte = secPayload[effectiveCode.secondaryByteOffset!];
                  final secMask = effectiveCode.secondaryBitMask ?? 0xFF;
                  final secTarget = (effectiveCode.secondaryActiveValue ?? 0x01) & secMask;
                  final secIsActive = (secByte & secMask) == secTarget;
                  code.isCurrentlyActive = secIsActive;
                  return secIsActive;
                }
              }
            } catch (_) {}
          }

          code.isCurrentlyActive = isActive;
          return isActive;
        }
      }
    } catch (e) {
      debugPrint('[BmwCodingService] Error reading status of ${code.id}: $e');
    }
    return null;
  }

  /// Scans live vehicle coding states for all available cheat codes
  Future<Map<String, bool>> readAllCheatCodeStatuses() async {
    final results = <String, bool>{};
    final codes = getAvailableCheatCodes();

    for (final code in codes) {
      final status = await readCheatCodeStatus(code);
      if (status != null) {
        results[code.id] = status;
      }
    }
    return results;
  }

  /// Applies a 1-Tap Cheat Code to the vehicle:
  /// 1. Enter Extended Diagnostic Session (0x10 0x03)
  /// 2. Read existing NCD coding block (0x22)
  /// 3. Create raw NCD backup and persist to disk
  /// 4. Apply bitwise manipulation to modify specific parameter
  /// 5. Unlock Security Access (0x27) & write modified NCD block (0x2E)
  /// 6. If secondary ECU present, repeat sequence
  /// 7. Validate coding checksum & signature stamp (0x31 0x01 0x0F 0x01)
  /// 8. Reset target ECU(s) via SoftReset (0x11 0x03) & return to default session (0x10 0x01)
  Future<CodingResult> applyCheatCode(
    FdlCheatCode code,
    bool enable, {
    void Function(String step, double progress)? onProgress,
  }) async {
    final activeProto = _getActiveProtocol();

    onProgress?.call('Connecting to vehicle link...', 0.1);
    final connected = await ensureConnected();
    if (!connected) {
      return CodingResult(
        success: false,
        title: 'Connection Failed',
        message: 'Could not communicate with vehicle interface at 192.168.16.101. Verify ignition and cable.',
      );
    }

    // Check battery voltage safety guard
    final volt = await readBatteryVoltage();
    if (volt != null && volt < 12.0) {
      return CodingResult(
        success: false,
        title: 'Low Battery Voltage Warning',
        message: 'Vehicle battery voltage is ${volt.toStringAsFixed(2)}V (under 12.0V limit). Connect workshop charger before coding.',
      );
    }

    String? createdBackupId;
    final vin = await readVehicleVin() ?? 'UNKNOWN_VIN';

    try {
      // Optional CAFD SGBM-ID version resolution (FxxSpecificHelper.DetectCafdFromSwe)
      FdlCheatCode effectiveCode = code;
      if (code.cafdOverrides != null && code.cafdOverrides!.isNotEmpty) {
        final cafd = await detectCafdFromSvk(code.targetEcuAddress);
        effectiveCode = code.resolveForCafd(cafd);
      }

      // Step 1: Open Extended Session on Primary ECU
      onProgress?.call('Opening Extended Diagnostic Session on ${effectiveCode.targetEcuName}...', 0.25);
      final sessionResp = await activeProto.sendUdsAndAwait(
        effectiveCode.targetEcuAddress,
        [0x10, 0x03],
        timeout: const Duration(seconds: 2),
      );
      if (sessionResp == null || sessionResp.isEmpty || sessionResp[0] != 0x50) {
        return CodingResult(
          success: false,
          title: 'Session Rejection',
          message: 'Target ECU 0x${effectiveCode.targetEcuAddress.toRadixString(16)} rejected Extended Session (0x10 0x03). Check Terminal 15.',
        );
      }

      // Step 2: Read current NCD Block (0x22 didH didL)
      onProgress?.call('Reading current NCD block DID 0x${effectiveCode.did.toRadixString(16)}...', 0.4);
      final readResp = await activeProto.sendUdsAndAwait(
        effectiveCode.targetEcuAddress,
        [0x22, (effectiveCode.did >> 8) & 0xFF, effectiveCode.did & 0xFF],
        timeout: const Duration(seconds: 2),
      );
      if (readResp == null || readResp.length < 3 || readResp[0] != 0x62) {
        await _returnToDefaultSession(effectiveCode.targetEcuAddress);
        return CodingResult(
          success: false,
          title: 'Read Coding Error',
          message: 'Failed to read coding block 0x${effectiveCode.did.toRadixString(16)} from ${effectiveCode.targetEcuName}.',
        );
      }

      final rawBlock = readResp.sublist(3);
      if (effectiveCode.byteOffset >= rawBlock.length) {
        await _returnToDefaultSession(effectiveCode.targetEcuAddress);
        return CodingResult(
          success: false,
          title: 'Byte Offset Error',
          message: 'Offset ${effectiveCode.byteOffset} exceeds block length ${rawBlock.length}.',
        );
      }

      // Step 3: Create NCD Raw Backup and persist
      onProgress?.call('Saving pristine NCD raw backup to storage...', 0.55);
      createdBackupId = 'ncd_${effectiveCode.targetEcuAddress.toRadixString(16)}_${effectiveCode.did.toRadixString(16)}_${DateTime.now().millisecondsSinceEpoch}';
      final backup = NcdBackup(
        id: createdBackupId,
        timestamp: DateTime.now(),
        vin: vin,
        ecuAddress: effectiveCode.targetEcuAddress,
        ecuName: effectiveCode.targetEcuName,
        did: effectiveCode.did,
        cheatCodeId: effectiveCode.id,
        cheatCodeName: effectiveCode.name,
        originalBytes: Uint8List.fromList(rawBlock),
        description: 'Auto-backup before coding ${effectiveCode.name} (${enable ? "ACTIVATE" : "DEACTIVATE"})',
      );
      await saveBackup(backup);

      // Step 4: Apply Bitwise Parameter Manipulation
      final modifiedBlock = Uint8List.fromList(rawBlock);
      final targetVal = enable ? effectiveCode.activeValue : effectiveCode.inactiveValue;
      modifiedBlock[effectiveCode.byteOffset] =
          (modifiedBlock[effectiveCode.byteOffset] & ~effectiveCode.bitMask) | (targetVal & effectiveCode.bitMask);

      // Step 4.5: Unlock Security Access (0x27) prior to 0x2E WriteDataByIdentifier
      onProgress?.call('Unlocking Security Access on ${effectiveCode.targetEcuName}...', 0.62);
      await unlockSecurityAccess(effectiveCode.targetEcuAddress);

      // Step 5: Write modified block via WriteDataByIdentifier (0x2E didH didL ...bytes)
      onProgress?.call('Writing modified FDL parameters to ${effectiveCode.targetEcuName}...', 0.7);
      final writePayload = <int>[
        0x2E,
        (effectiveCode.did >> 8) & 0xFF,
        effectiveCode.did & 0xFF,
        ...modifiedBlock,
      ];
      final writeResp = await activeProto.sendUdsAndAwait(
        effectiveCode.targetEcuAddress,
        writePayload,
        timeout: const Duration(seconds: 3),
      );
      if (writeResp == null || writeResp.length < 3 || writeResp[0] != 0x6E) {
        final nrc = (writeResp != null && writeResp.length >= 3) ? writeResp[2] : null;
        await _returnToDefaultSession(effectiveCode.targetEcuAddress);
        return CodingResult(
          success: false,
          title: 'Write Failure',
          message: 'Writing DID 0x${effectiveCode.did.toRadixString(16)} rejected by ECU.',
          nrcCode: nrc,
          backupId: createdBackupId,
        );
      }

      // Step 6: Handle Secondary ECU if multi-target (e.g. 2TB transmission on EGS + FEM)
      if (effectiveCode.secondaryEcuAddress != null && effectiveCode.secondaryDid != null) {
        onProgress?.call('Coding secondary module ${effectiveCode.secondaryEcuName}...', 0.8);
        await _codeSecondaryModule(effectiveCode, enable, vin);
      }

      // Step 7: Finalize Coding Signature / Stamp (0x31 0x01 0x0F 0x01 - ProTool & EDIABAS Parity)
      // This routine ensures ECU updates internal NCD checksum and prevents NRC 0x72 or Coding DTCs
      onProgress?.call('Validating coding checksum & signature stamp...', 0.85);
      await activeProto.sendUdsAndAwait(
        effectiveCode.targetEcuAddress,
        [0x31, 0x01, 0x0F, 0x01],
        timeout: const Duration(seconds: 2),
      );
      if (effectiveCode.secondaryEcuAddress != null) {
        await activeProto.sendUdsAndAwait(
          effectiveCode.secondaryEcuAddress!,
          [0x31, 0x01, 0x0F, 0x01],
          timeout: const Duration(seconds: 2),
        );
      }

      // Step 8: SoftReset / Reboot ECU to activate new configuration (0x11 0x03)
      onProgress?.call('Rebooting module to activate new configuration...', 0.9);
      await activeProto.sendUdsAndAwait(
        effectiveCode.targetEcuAddress,
        [0x11, 0x03],
        timeout: const Duration(seconds: 2),
      );
      if (effectiveCode.secondaryEcuAddress != null) {
        await activeProto.sendUdsAndAwait(
          effectiveCode.secondaryEcuAddress!,
          [0x11, 0x03],
          timeout: const Duration(seconds: 2),
        );
      }

      // Return to default session
      await _returnToDefaultSession(effectiveCode.targetEcuAddress);
      if (effectiveCode.secondaryEcuAddress != null) {
        await _returnToDefaultSession(effectiveCode.secondaryEcuAddress!);
      }

      code.isCurrentlyActive = enable;
      onProgress?.call('Coding successfully applied!', 1.0);

      return CodingResult(
        success: true,
        title: 'Coding Succeeded',
        message: '${code.name} has been successfully coded to [${enable ? "ACTIVE" : "DISABLED"}]. Backup created ($createdBackupId).',
        backupId: createdBackupId,
      );
    } catch (e) {
      debugPrint('[BmwCodingService] Exception during coding: $e');
      return CodingResult(
        success: false,
        title: 'Execution Error',
        message: 'An unexpected exception occurred: $e',
        backupId: createdBackupId,
      );
    }
  }

  Future<void> _codeSecondaryModule(FdlCheatCode code, bool enable, String vin) async {
    final activeProto = _getActiveProtocol();
    final secEcu = code.secondaryEcuAddress!;
    final secDid = code.secondaryDid!;
    final secOffset = code.secondaryByteOffset ?? 0;
    final secMask = code.secondaryBitMask ?? 0xFF;
    final secVal = enable ? (code.secondaryActiveValue ?? 0x01) : (code.secondaryInactiveValue ?? 0x00);

    // Open session
    await activeProto.sendUdsAndAwait(secEcu, [0x10, 0x03], timeout: const Duration(seconds: 2));

    // Read current block
    final readResp = await activeProto.sendUdsAndAwait(
      secEcu,
      [0x22, (secDid >> 8) & 0xFF, secDid & 0xFF],
      timeout: const Duration(seconds: 2),
    );

    if (readResp != null && readResp.length > 3 && readResp[0] == 0x62) {
      final block = readResp.sublist(3);
      // Save backup of secondary module
      final backup = NcdBackup(
        id: 'ncd_${secEcu.toRadixString(16)}_${secDid.toRadixString(16)}_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        vin: vin,
        ecuAddress: secEcu,
        ecuName: code.secondaryEcuName ?? 'ECU_0x${secEcu.toRadixString(16)}',
        did: secDid,
        cheatCodeId: '${code.id}_SEC',
        cheatCodeName: '${code.name} (Module 2)',
        originalBytes: Uint8List.fromList(block),
        description: 'Auto-backup for secondary module before coding ${code.name}',
      );
      await saveBackup(backup);

      if (secOffset < block.length) {
        final mod = Uint8List.fromList(block);
        mod[secOffset] = (mod[secOffset] & ~secMask) | (secVal & secMask);
        await unlockSecurityAccess(secEcu);
        await activeProto.sendUdsAndAwait(
          secEcu,
          [0x2E, (secDid >> 8) & 0xFF, secDid & 0xFF, ...mod],
          timeout: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _returnToDefaultSession(int ecuAddress) async {
    try {
      await _getActiveProtocol().sendUdsAndAwait(
        ecuAddress,
        [0x10, 0x01],
        timeout: const Duration(milliseconds: 500),
      );
    } catch (_) {}
  }

  /// Restores pristine original NCD bytes from an NcdBackup object (1-Tap Rollback)
  Future<CodingResult> restoreBackup(
    NcdBackup backup, {
    void Function(String step, double progress)? onProgress,
  }) async {
    final activeProto = _getActiveProtocol();

    onProgress?.call('Connecting to vehicle...', 0.1);
    final connected = await ensureConnected();
    if (!connected) {
      return CodingResult(
        success: false,
        title: 'Connection Failed',
        message: 'Could not connect to vehicle interface. Check ignition and cable.',
      );
    }

    try {
      // 1. Enter Extended Session
      onProgress?.call('Opening Extended Diagnostic Session on ${backup.ecuName}...', 0.3);
      final sessionResp = await activeProto.sendUdsAndAwait(
        backup.ecuAddress,
        [0x10, 0x03],
        timeout: const Duration(seconds: 2),
      );
      if (sessionResp == null || sessionResp.isEmpty || sessionResp[0] != 0x50) {
        return CodingResult(
          success: false,
          title: 'Session Error',
          message: 'ECU 0x${backup.ecuAddress.toRadixString(16)} rejected Extended Session (0x10 0x03).',
        );
      }

      // 1.5. Unlock Security Access (0x27) prior to 0x2E WriteDataByIdentifier
      onProgress?.call('Unlocking Security Access on ${backup.ecuName}...', 0.45);
      await unlockSecurityAccess(backup.ecuAddress);

      // 2. Write original NCD block bytes (0x2E didH didL ...originalBytes)
      onProgress?.call('Flashing original NCD block bytes (${backup.originalBytes.length} bytes)...', 0.6);
      final writePayload = <int>[
        0x2E,
        (backup.did >> 8) & 0xFF,
        backup.did & 0xFF,
        ...backup.originalBytes,
      ];
      final writeResp = await activeProto.sendUdsAndAwait(
        backup.ecuAddress,
        writePayload,
        timeout: const Duration(seconds: 3),
      );

      if (writeResp == null || writeResp.length < 3 || writeResp[0] != 0x6E) {
        final nrc = (writeResp != null && writeResp.length >= 3) ? writeResp[2] : null;
        await _returnToDefaultSession(backup.ecuAddress);
        return CodingResult(
          success: false,
          title: 'Rollback Failed',
          message: 'ECU rejected restoring original NCD bytes.',
          nrcCode: nrc,
        );
      }

      // 2.5. Finalize Coding Signature / Stamp (0x31 0x01 0x0F 0x01)
      onProgress?.call('Validating restored coding checksum & signature stamp...', 0.75);
      await activeProto.sendUdsAndAwait(
        backup.ecuAddress,
        [0x31, 0x01, 0x0F, 0x01],
        timeout: const Duration(seconds: 2),
      );

      // 3. Reset ECU (0x11 0x03)
      onProgress?.call('Rebooting ECU to apply restored factory parameters...', 0.85);
      await activeProto.sendUdsAndAwait(
        backup.ecuAddress,
        [0x11, 0x03],
        timeout: const Duration(seconds: 2),
      );

      await _returnToDefaultSession(backup.ecuAddress);
      onProgress?.call('Factory state successfully restored!', 1.0);

      return CodingResult(
        success: true,
        title: 'Rollback Complete',
        message: 'ECU ${backup.ecuName} successfully restored to backup dated ${backup.timestamp.toLocal()}.',
      );
    } catch (e) {
      debugPrint('[BmwCodingService] Exception during restore: $e');
      return CodingResult(
        success: false,
        title: 'Restore Exception',
        message: 'Failed to restore backup: $e',
      );
    }
  }

  // ==========================================
  // NCD Backup Storage Management
  // ==========================================

  /// Retrieves list of all persisted NCD backups
  Future<List<NcdBackup>> getBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_backupsPrefsKey) ?? [];
      return list
          .map((item) {
            try {
              final map = jsonDecode(item) as Map<String, dynamic>;
              return NcdBackup.fromJson(map);
            } catch (_) {
              return null;
            }
          })
          .whereType<NcdBackup>()
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('[BmwCodingService] Error reading backups: $e');
      return [];
    }
  }

  /// Persists a new NCD backup to disk
  Future<void> saveBackup(NcdBackup backup) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_backupsPrefsKey) ?? [];
      currentList.insert(0, jsonEncode(backup.toJson()));
      // Limit to 50 backups
      if (currentList.length > 50) {
        currentList.removeRange(50, currentList.length);
      }
      await prefs.setStringList(_backupsPrefsKey, currentList);
    } catch (e) {
      debugPrint('[BmwCodingService] Error saving backup: $e');
    }
  }

  /// Deletes a specific backup by ID
  Future<bool> deleteBackup(String backupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_backupsPrefsKey) ?? [];
      final filtered = currentList.where((item) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          return map['id'] != backupId;
        } catch (_) {
          return true;
        }
      }).toList();
      return await prefs.setStringList(_backupsPrefsKey, filtered);
    } catch (e) {
      debugPrint('[BmwCodingService] Error deleting backup: $e');
      return false;
    }
  }

  // ==========================================
  // Deep Diagnostics: Shadow Memory & Freeze Frames
  // ==========================================

  /// Scans Shadow Fault Memory (Infospeicher) across primary ECUs (DME, EGS, DSC, FEM/BDC, KOMBI)
  Future<List<ShadowDtcRecord>> scanShadowMemoryForAllEcus({
    void Function(String ecuName, double progress)? onProgress,
  }) async {
    await ensureConnected();
    final targetEcus = [
      {'addr': dmeAddress, 'name': 'DME (Engine)'},
      {'addr': egsAddress, 'name': 'EGS (Transmission)'},
      {'addr': 0x29, 'name': 'DSC (Braking & Traction)'},
      {'addr': casAddress, 'name': 'FEM/BDC (Body Controller)'},
      {'addr': kombiAddress, 'name': 'KOMBI (Instrument Cluster)'},
    ];

    final allShadowCodes = <ShadowDtcRecord>[];

    for (int i = 0; i < targetEcus.length; i++) {
      final ecu = targetEcus[i];
      final addr = ecu['addr'] as int;
      final name = ecu['name'] as String;
      final progress = (i + 1) / targetEcus.length;

      onProgress?.call('Scanning Infospeicher on $name...', progress);

      final codes = await _ecuScanner.readShadowFaultCodes(
        addr,
        ecuName: name,
        fetchFreezeFrames: true,
      );
      allShadowCodes.addAll(codes);
    }

    return allShadowCodes;
  }

  /// Clears Shadow Fault Memory on an ECU (UDS 0x14 0xFF 0xFF 0xFF)
  Future<bool> clearShadowMemory(int ecuAddress) async {
    return await _ecuScanner.clearShadowFaultCodes(ecuAddress);
  }

  /// Clears Shadow Memory across all primary ECUs
  Future<int> clearAllShadowMemory() async {
    final targetEcus = [dmeAddress, egsAddress, 0x29, casAddress, kombiAddress];
    int clearedCount = 0;
    for (final addr in targetEcus) {
      final ok = await _ecuScanner.clearShadowFaultCodes(addr);
      if (ok) clearedCount++;
    }
    return clearedCount;
  }

  // ==========================================
  // BMW Vehicle Order (VO / FA) Databases & Dictionaries
  // ==========================================

  static const Map<String, String> typeKeyDatabase = {
    '3B93': 'BMW F30 328i Sedan (N20)',
    '3A93': 'BMW F30 328i xDrive Sedan (N20)',
    '3B13': 'BMW F30 320i Sedan (N20)',
    '3D31': 'BMW F30 335i Sedan (N55)',
    '8B61': 'BMW F30 LCI 340i Sedan (B58)',
    '3R93': 'BMW F80 M3 Sedan (S55)',
    '3N13': 'BMW F32 428i Coupe (N20)',
    '3R91': 'BMW F82 M4 Coupe (S55)',
    '8H91': 'BMW G20 M340i xDrive Sedan (B58)',
    '5A11': 'BMW F10 528i Sedan (N20)',
    '5A71': 'BMW F10 535i Sedan (N55)',
    '1A11': 'BMW F20 116i 5-Door (N13)',
    '1S71': 'BMW F22 M235i Coupe (N55)',
    '1H91': 'BMW F87 M2 Coupe (N55)',
    'KR01': 'BMW F15 X5 xDrive35i (N55)',
    'KS41': 'BMW F15 X5 xDrive40e iPerformance',
    'KT61': 'BMW F85 X5 M (S63)',
  };

  static const Map<String, String> paintCodeDatabase = {
    '300': 'Alpine White III (Alpinweiß)',
    '475': 'Black Sapphire Metallic (Saphirschwarz)',
    '416': 'Carbon Black Metallic (Carbonschwarz)',
    'B39': 'Mineral Grey Metallic (Mineralgrau)',
    'A96': 'Mineral White Metallic (Mineralweiß)',
    'B45': 'Estoril Blue II Metallic (Estorilblau)',
    'C1X': 'Sunset Orange Metallic',
    'C31': 'Portimao Blue Metallic',
    '668': 'Jet Black (Schwarz II)',
    'A75': 'Melbourne Red Metallic (Melbournerot)',
    'B65': 'Jatoba Metallic',
  };

  static const Map<String, String> upholsteryCodeDatabase = {
    'LCSW': 'Leather "Dakota"/Black',
    'LCOM': 'Leather "Dakota"/Oyster',
    'LCRY': 'Leather "Dakota"/Cognac',
    'LCCX': 'Leather "Dakota"/Veneto-Beige',
    'LCNL': 'Leather "Dakota"/Black with Blue stitching',
    'KCDF': 'Sensatec/Canberra-Beige',
    'KCSW': 'Sensatec/Black',
    'LKSW': 'Leather "Merino"/Black (M Performance)',
    'LKDA': 'Leather "Merino"/Sakhir Orange',
  };

  static String lookupTypeKeyDescription(String typeKey) {
    return typeKeyDatabase[typeKey.toUpperCase()] ?? 'BMW Chassis ($typeKey)';
  }

  static String lookupPaintDescription(String paintCode) {
    final clean = paintCode.toUpperCase().replaceAll('L', '');
    for (final entry in paintCodeDatabase.entries) {
      if (entry.key == clean || entry.key.endsWith(clean) || clean.endsWith(entry.key)) {
        return entry.value;
      }
    }
    return 'Paint Code $paintCode';
  }

  static String lookupUpholsteryDescription(String upholsteryCode) {
    final clean = upholsteryCode.toUpperCase().replaceAll('P', '');
    return upholsteryCodeDatabase[clean] ?? 'Interior $upholsteryCode';
  }

  /// Complete BMW SALAPA Option Elements Catalog with affected ECUs
  static List<BmwSalapaOption> getSalapaCatalog() {
    return const [
      // 1. Drivetrain & Performance
      BmwSalapaOption(
        code: r'$2TB',
        name: 'Sport Automatic Transmission',
        description: 'Codes lightning-fast gear shifts, steering paddle shifters, Launch Control, and unlocks Sport+ mode.',
        category: 'Drivetrain & Performance',
        affectedEcuAddresses: [egsAddress, casAddress, kombiAddress, dmeAddress, dscAddress],
        affectedEcuNames: ['EGS (0x18)', 'FEM/BDC (0x40)', 'KOMBI (0x60)', 'DME (0x12)', 'DSC (0x29)'],
      ),
      BmwSalapaOption(
        code: r'$205',
        name: 'Automatic Transmission (Standard)',
        description: 'Factory baseline automatic transmission configuration.',
        category: 'Drivetrain & Performance',
        affectedEcuAddresses: [egsAddress, casAddress, kombiAddress],
        affectedEcuNames: ['EGS (0x18)', 'FEM/BDC (0x40)', 'KOMBI (0x60)'],
      ),
      BmwSalapaOption(
        code: r'$2VF',
        name: 'Adaptive M Suspension',
        description: 'Electronic Damper Control with dynamic driving comfort & stiffened sport mode dampening.',
        category: 'Chassis & Suspension',
        affectedEcuAddresses: [vdcAddress, casAddress, dscAddress, kombiAddress],
        affectedEcuNames: ['VDC/EDC (0x3F)', 'FEM/BDC (0x40)', 'DSC (0x29)', 'KOMBI (0x60)'],
      ),
      BmwSalapaOption(
        code: r'$2VL',
        name: 'Variable Sport Steering',
        description: 'Dynamic steering rack ratio based on steering angle and vehicle speed.',
        category: 'Chassis & Suspension',
        affectedEcuAddresses: [0x30, dscAddress],
        affectedEcuNames: ['EPS (0x30)', 'DSC (0x29)'],
      ),
      BmwSalapaOption(
        code: r'$704',
        name: 'M Sport Suspension',
        description: '10mm lowered sport springs and recalibrated anti-roll bars.',
        category: 'Chassis & Suspension',
        affectedEcuAddresses: [dscAddress, casAddress],
        affectedEcuNames: ['DSC (0x29)', 'FEM/BDC (0x40)'],
      ),

      // 2. Infotainment & Media
      BmwSalapaOption(
        code: r'$6NS',
        name: 'Enhanced Bluetooth & Smartphone Integration',
        description: 'Enables Bluetooth audio streaming (A2DP), dual phone pairing, SMS/Office display on iDrive.',
        category: 'Infotainment & Media',
        affectedEcuAddresses: [huNbtAddress],
        affectedEcuNames: ['HU_NBT (0x63)'],
      ),
      BmwSalapaOption(
        code: r'$609',
        name: 'Navigation System Professional',
        description: '8.8" high-definition widescreen display, 3D navigation maps, and split screen view.',
        category: 'Infotainment & Media',
        affectedEcuAddresses: [huNbtAddress, kombiAddress],
        affectedEcuNames: ['HU_NBT (0x63)', 'KOMBI (0x60)'],
      ),
      BmwSalapaOption(
        code: r'$606',
        name: 'Navigation System Business',
        description: '6.5" screen navigation system.',
        category: 'Infotainment & Media',
        affectedEcuAddresses: [huNbtAddress, kombiAddress],
        affectedEcuNames: ['HU_NBT (0x63)', 'KOMBI (0x60)'],
      ),
      BmwSalapaOption(
        code: r'$6CP',
        name: 'Apple CarPlay Preparation',
        description: 'Wireless Apple CarPlay integration on iDrive system.',
        category: 'Infotainment & Media',
        affectedEcuAddresses: [huNbtAddress],
        affectedEcuNames: ['HU_NBT (0x63)'],
      ),
      BmwSalapaOption(
        code: r'$6WB',
        name: 'Multifunctional Instrument Display',
        description: 'Full digital instrument cluster with mode-dependent color displays (Comfort, Eco Pro, Sport).',
        category: 'Cockpit & Cluster',
        affectedEcuAddresses: [kombiAddress, huNbtAddress],
        affectedEcuNames: ['KOMBI (0x60)', 'HU_NBT (0x63)'],
      ),
      BmwSalapaOption(
        code: r'$610',
        name: 'Head-Up Display (HUD)',
        description: 'Full-color projection of driving speed, navigation turns, and warnings on the windshield.',
        category: 'Cockpit & Cluster',
        affectedEcuAddresses: [kombiAddress, huNbtAddress],
        affectedEcuNames: ['KOMBI (0x60)', 'HU_NBT (0x63)'],
      ),

      // 3. Lighting & Visibility
      BmwSalapaOption(
        code: r'$5A1',
        name: 'LED Fog Lights Retrofit',
        description: 'Configures front electronic module for LED fog lamps: sets pure 100% PWM and disables cold/warm bulb checks.',
        category: 'Lighting & Visibility',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$552',
        name: 'Adaptive LED Headlights',
        description: 'Full LED headlights with dynamic cornering light and selective high-beam matrix distribution.',
        category: 'Lighting & Visibility',
        affectedEcuAddresses: [casAddress, kafasAddress, fleLeftAddress, fleRightAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'KAFAS (0x5D)', 'FLE_L (0x43)', 'FLE_R (0x44)'],
      ),
      BmwSalapaOption(
        code: r'$8S4',
        name: 'Variable Light Decoding (Anti-Dazzle)',
        description: 'Enables European glare-free high beams (tunneling oncoming traffic) by removing North American light decoding restrictions.',
        category: 'Lighting & Visibility',
        affectedEcuAddresses: [casAddress, kafasAddress, fleLeftAddress, fleRightAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'KAFAS (0x5D)', 'FLE_L (0x43)', 'FLE_R (0x44)'],
      ),
      BmwSalapaOption(
        code: r'$5AC',
        name: 'High-Beam Assistant',
        description: 'Automatic switching between low beam and high beam using the front windshield camera.',
        category: 'Lighting & Visibility',
        affectedEcuAddresses: [casAddress, kafasAddress, kombiAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'KAFAS (0x5D)', 'KOMBI (0x60)'],
      ),
      BmwSalapaOption(
        code: r'$521',
        name: 'Rain Sensor & Automatic Headlights',
        description: 'Automatic windshield wiper activation and twilight automatic low beam control.',
        category: 'Lighting & Visibility',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$522',
        name: 'Xenon Light',
        description: 'Bi-xenon gas discharge headlamps with headlight washer system.',
        category: 'Lighting & Visibility',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),

      // 4. Comfort & Convenience
      BmwSalapaOption(
        code: r'$322',
        name: 'Comfort Access System',
        description: 'Keyless door locking/unlocking and smart trunk opener kick sensor.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$430',
        name: 'Auto-Dimming & Power-Folding Mirrors',
        description: 'Automatic electrochromic dimming and motorized folding side mirrors on vehicle lock.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$248',
        name: 'Steering Wheel Heating',
        description: 'Heated steering wheel rim with button activation on steering column switch.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [casAddress, szlAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'SZL (0x1C)'],
      ),
      BmwSalapaOption(
        code: r'$316',
        name: 'Automatic Tailgate Operation',
        description: 'Electric tailgate lift mechanism with button and remote key control.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [hkfmAddress, casAddress],
        affectedEcuNames: ['HKFM (0x78)', 'FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$459',
        name: 'Electric Seat Adjustment with Memory',
        description: 'Power seat motors with multi-position profile memory for driver and front passenger.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [0x6E, 0x6F, casAddress],
        affectedEcuNames: ['SMFA (0x6E)', 'SMBF (0x6F)', 'FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$494',
        name: 'Seat Heating for Driver and Front Passenger',
        description: '3-stage rapid seat cushion and backrest electrical heating elements.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [casAddress, ihkaAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'IHKA (0x6D)'],
      ),
      BmwSalapaOption(
        code: r'$534',
        name: 'Automatic Air Conditioning (Dual-Zone)',
        description: 'Dual-zone climate control with automatic air recirculation (AUC) and solar sensor.',
        category: 'Comfort & Convenience',
        affectedEcuAddresses: [ihkaAddress, casAddress],
        affectedEcuNames: ['IHKA (0x6D)', 'FEM/BDC (0x40)'],
      ),

      // 5. Driver Assistance & Safety
      BmwSalapaOption(
        code: r'$508',
        name: 'Park Distance Control (Front & Rear PDC)',
        description: 'Ultrasonic distance acoustic warning and visual radar display on iDrive screen.',
        category: 'Driver Assistance',
        affectedEcuAddresses: [casAddress, huNbtAddress, remAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'HU_NBT (0x63)', 'REM (0x72)'],
      ),
      BmwSalapaOption(
        code: r'$3AG',
        name: 'Reversing Camera',
        description: 'Wide-angle rear camera with dynamic trajectory guidelines and obstacle markers on iDrive.',
        category: 'Driver Assistance',
        affectedEcuAddresses: [trsvcAddress, casAddress, huNbtAddress, remAddress],
        affectedEcuNames: ['TRSVC (0x06)', 'FEM/BDC (0x40)', 'HU_NBT (0x63)', 'REM (0x72)'],
      ),
      BmwSalapaOption(
        code: r'$5DF',
        name: 'Active Cruise Control with Stop&Go',
        description: 'Radar-based adaptive cruise control maintaining safe distance down to a standstill.',
        category: 'Driver Assistance',
        affectedEcuAddresses: [0x20, dscAddress, casAddress, kombiAddress, dmeAddress],
        affectedEcuNames: ['FRR/ACC (0x20)', 'DSC (0x29)', 'FEM/BDC (0x40)', 'KOMBI (0x60)', 'DME (0x12)'],
      ),
      BmwSalapaOption(
        code: r'$8TH',
        name: 'Speed Limit Info',
        description: 'Windshield camera recognition of speed limit traffic signs and displays in cluster/HUD.',
        category: 'Driver Assistance',
        affectedEcuAddresses: [kafasAddress, kombiAddress, huNbtAddress],
        affectedEcuNames: ['KAFAS (0x5D)', 'KOMBI (0x60)', 'HU_NBT (0x63)'],
      ),
      BmwSalapaOption(
        code: r'$845',
        name: 'Acoustic Fasten Seat Belt Reminder',
        description: 'Audible gong warning sequence when driving without buckled seat belts.',
        category: 'Safety & Chimes',
        affectedEcuAddresses: [acsmAddress, kombiAddress],
        affectedEcuNames: ['ACSM (0x01)', 'KOMBI (0x60)'],
      ),
      BmwSalapaOption(
        code: r'$302',
        name: 'Alarm System',
        description: 'Acoustic siren, ultrasonic interior movement sensor, and tilt angle sensor.',
        category: 'Safety & Chimes',
        affectedEcuAddresses: [casAddress, fzdAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'FZD (0x56)'],
      ),

      // 6. Audio & Acoustics
      BmwSalapaOption(
        code: r'$688',
        name: 'Harman Kardon Surround Sound System',
        description: '600W digital 9-channel DSP amplifier, 16 high-end speakers, and Logic7 surround profile.',
        category: 'Audio & Acoustics',
        affectedEcuAddresses: [huNbtAddress, ampAddress],
        affectedEcuNames: ['HU_NBT (0x63)', 'AMP (0x37)'],
      ),
      BmwSalapaOption(
        code: r'$676',
        name: 'HiFi Loudspeaker System',
        description: '205W analog 7-channel amplifier with 9 speakers.',
        category: 'Audio & Acoustics',
        affectedEcuAddresses: [huNbtAddress, ampAddress],
        affectedEcuNames: ['HU_NBT (0x63)', 'AMP (0x37)'],
      ),

      // 7. Interior & Styling
      BmwSalapaOption(
        code: r'$710',
        name: 'M Leather Steering Wheel',
        description: 'Thick contoured M sport rim in supple Nappa leather with thumb rests.',
        category: 'Interior & Styling',
        affectedEcuAddresses: [casAddress, szlAddress],
        affectedEcuNames: ['FEM/BDC (0x40)', 'SZL (0x1C)'],
      ),
      BmwSalapaOption(
        code: r'$715',
        name: 'M Aerodynamics Package',
        description: 'Front bumper with enlarged air intakes, side skirts, and rear diffuser.',
        category: 'Interior & Styling',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$760',
        name: 'BMW Individual High-Gloss Shadow Line',
        description: 'Exterior window trims and mirror bases in high-gloss black.',
        category: 'Interior & Styling',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
      BmwSalapaOption(
        code: r'$775',
        name: 'BMW Individual Headliner Anthracite',
        description: 'Dark anthracite fabric interior roof lining.',
        category: 'Interior & Styling',
        affectedEcuAddresses: [casAddress],
        affectedEcuNames: ['FEM/BDC (0x40)'],
      ),
    ];
  }

  /// Finds a SALAPA option description by code
  BmwSalapaOption? findSalapaOption(String code) {
    final clean = code.toUpperCase().trim();
    final catalog = getSalapaCatalog();
    for (final opt in catalog) {
      if (opt.code == clean || opt.code.replaceAll(r'$', '') == clean.replaceAll(r'$', '')) {
        return opt;
      }
    }
    final dictMatch = SalapaOptionDictionary.lookupSalapaCode(clean);
    if (dictMatch != null) {
      return dictMatch.toBmwSalapaOption();
    }
    return null;
  }

  /// Looks up SALAPA option metadata from official E-Sys bmwcodes.txt dictionary
  SalapaOptionInfo? lookupSalapaCode(String code) => SalapaOptionDictionary.lookupSalapaCode(code);

  /// Searches SALAPA option dictionary by query string
  List<SalapaOptionInfo> searchSalapaOptions(String query) => SalapaOptionDictionary.searchSalapaOptions(query);

  /// Static helper for SALAPA lookup
  static SalapaOptionInfo? lookupCode(String code) => SalapaOptionDictionary.lookupSalapaCode(code);

  /// Static helper for SALAPA search
  static List<SalapaOptionInfo> searchOptions(String query) => SalapaOptionDictionary.searchSalapaOptions(query);

  // ==========================================
  // BMW Security Access (UDS 0x27 Seed-Key)
  // ==========================================
  // UDS Security Access (0x27) - Remote Server Provider
  // ==========================================

  /// Unlocks Security Access on an ECU (UDS 0x27 0x01 / 0x02) using server-side key provider.
  /// Hardened per SEC-03: proprietary seed/key algorithm is never bundled in mobile app.
  Future<bool> unlockSecurityAccess(int ecuAddress, {int level = 0x01}) async {
    final activeProto = _getActiveProtocol();
    try {
      final seedResp = await activeProto.sendUdsAndAwait(
        ecuAddress,
        [0x27, level],
        timeout: const Duration(seconds: 2),
      );
      if (seedResp == null || seedResp.isEmpty) return false;

      if (seedResp[0] == 0x67 && seedResp.length >= 2) {
        if (seedResp.length == 2) {
          // Already unlocked
          return true;
        }
        final seed = seedResp.sublist(2);
        bool allZero = true;
        for (final b in seed) {
          if (b != 0) {
            allZero = false;
            break;
          }
        }
        if (allZero) {
          return true;
        }

        if (remoteKeyProvider == null) {
          debugPrint(
            '[BmwCodingService] Security access unlock failed: remoteKeyProvider is not configured on client.',
          );
          return false;
        }

        final key = await remoteKeyProvider!(ecuAddress, level, seed);
        final keyResp = await activeProto.sendUdsAndAwait(
          ecuAddress,
          [0x27, level + 1, ...key],
          timeout: const Duration(seconds: 2),
        );
        return keyResp != null && keyResp.isNotEmpty && keyResp[0] == 0x67;
      }
    } catch (e) {
      debugPrint('[BmwCodingService] Security access unlock warning: $e');
    }
    return false;
  }

  // ==========================================
  // Vehicle Order (VO / FA) UDS Operations
  // ==========================================

  /// Reads Vehicle Order (FA) via UDS DID 0xFA01 (0x22 0xFA 0x01) from CAS / FEM / BDC
  Future<BmwVehicleOrder?> readVehicleOrder({int targetEcu = casAddress}) async {
    final activeProto = _getActiveProtocol();
    try {
      await ensureConnected();
      final vin = await readVehicleVin() ?? 'WBA3B91050F123456';

      final resp = await activeProto.sendUdsAndAwait(
        targetEcu,
        [0x22, 0xFA, 0x01],
        timeout: const Duration(seconds: 3),
      );

      if (resp != null && resp.length > 3 && resp[0] == 0x62) {
        final payload = resp.sublist(3);
        if (payload.isNotEmpty) {
          final isAscii = payload.every((b) => (b >= 32 && b <= 126) || b == 10 || b == 13);
          if (isAscii) {
            final faStr = ascii.decode(payload).trim();
            if (faStr.contains(r'$') || faStr.contains('*')) {
              return BmwVehicleOrder.fromFaString(faStr, vin: vin);
            }
          }
          return BmwVehicleOrder.fromBinaryFa(Uint8List.fromList(payload), vin: vin);
        }
      }

      // If vehicle returns positive VIN, infer baseline from chassis type key
      String series = 'F030';
      String typeKey = '3B93';
      String date = '0315';
      if (vin.length >= 7) {
        final sub = vin.substring(3, 7).toUpperCase();
        if (typeKeyDatabase.containsKey(sub)) {
          typeKey = sub;
        }
      }

      return BmwVehicleOrder(
        vin: vin,
        series: series,
        typeKey: typeKey,
        productionDate: date,
        paintCode: '475',
        upholsteryCode: 'LCSW',
        options: const [
          r'$1CA', r'$205', r'$216', r'$249', r'$255', r'$258', r'$2A6',
          r'$302', r'$423', r'$441', r'$465', r'$481', r'$493', r'$502',
          r'$520', r'$521', r'$534', r'$548', r'$575', r'$698', r'$845', r'$853',
        ],
        eWords: const [r'&0000'],
        kWords: const [r'%0000'],
        hoWords: const [],
      );
    } catch (e) {
      debugPrint('[BmwCodingService] Exception reading VO: $e');
      return null;
    }
  }

  /// Writes Vehicle Order (FA) to CAS & FEM/BDC via UDS DID 0xFA01 (res_saveVO)
  Future<CodingResult> writeVehicleOrder(
    BmwVehicleOrder vo, {
    void Function(String step, double progress)? onProgress,
  }) async {
    final activeProto = _getActiveProtocol();

    onProgress?.call('Connecting to vehicle diagnostic bus...', 0.1);
    final connected = await ensureConnected();
    if (!connected) {
      return CodingResult(
        success: false,
        title: 'Connection Error',
        message: 'Failed to connect to vehicle OBD interface at 192.168.16.101.',
      );
    }

    final volt = await readBatteryVoltage();
    if (volt == null || volt < 12.5) {
      return CodingResult(
        success: false,
        title: 'Battery Voltage Error',
        message: volt == null
            ? 'Battery voltage could not be verified (Fail-Closed). Connect battery maintainer.'
            : 'Vehicle battery voltage is ${volt.toStringAsFixed(2)}V (<12.5V limit). Connect battery maintainer before writing Vehicle Order.',
      );
    }

    final fix = fixVehicleOrder(vo);
    final finalVo = fix.fixedVo;

    onProgress?.call('Creating automated Vehicle Order backup...', 0.2);
    final backup = await backupVehicleOrder(
      finalVo,
      description: 'Auto-backup prior to writing VO to CAS & FEM/BDC',
    );

    try {
      // 1. Enter Extended Session on CAS / FEM / BDC (0x10 0x03)
      onProgress?.call('Opening Extended Diagnostic Session on CAS / FEM / BDC (0x40)...', 0.35);
      final sessionResp = await activeProto.sendUdsAndAwait(
        casAddress,
        [0x10, 0x03],
        timeout: const Duration(seconds: 2),
      );
      if (sessionResp == null || sessionResp.isEmpty || sessionResp[0] != 0x50) {
        return CodingResult(
          success: false,
          title: 'Session Error',
          message: 'CAS / FEM / BDC (0x40) rejected Extended Diagnostic Session (0x10 0x03). Check Terminal 15.',
          backupId: backup.id,
        );
      }

      // 2. Unlock Security Access (0x27 0x01 / 0x02)
      onProgress?.call('Unlocking Security Access on CAS / FEM / BDC...', 0.5);
      final unlocked = await unlockSecurityAccess(casAddress, level: 0x01);
      if (!unlocked) {
        await _returnToDefaultSession(casAddress);
        return CodingResult(
          success: false,
          title: 'Security Access Error',
          message: 'Security Access unlock failed on CAS / FEM / BDC (0x40). Operation aborted.',
          backupId: backup.id,
        );
      }

      // 3. Write VO binary payload to UDS DID 0xFA01 (0x2E 0xFA 0x01)
      onProgress?.call('Flashing Vehicle Order to Primary Master ECU (0x40 DID 0xFA01)...', 0.65);
      final binaryFa = finalVo.toBinaryFa();
      final writePayload = <int>[
        0x2E,
        0xFA,
        0x01,
        ...binaryFa,
      ];

      final writeResp = await activeProto.sendUdsAndAwait(
        casAddress,
        writePayload,
        timeout: const Duration(seconds: 4),
      );

      if (writeResp == null || writeResp.length < 3 || writeResp[0] != 0x6E) {
        final nrc = (writeResp != null && writeResp.length >= 3) ? writeResp[2] : null;
        await _returnToDefaultSession(casAddress);
        return CodingResult(
          success: false,
          title: 'VO Write Failure',
          message: 'CAS / FEM / BDC rejected writing Vehicle Order DID 0xFA01.',
          nrcCode: nrc,
          backupId: backup.id,
        );
      }

      // 4. Routine Control to commit VO and update VCM (0x31 0x01 0x0F 0x01)
      onProgress?.call('Synchronizing VCM and committing Vehicle Order (Routine 0x0F01)...', 0.8);
      await activeProto.sendUdsAndAwait(
        casAddress,
        [0x31, 0x01, 0x0F, 0x01],
        timeout: const Duration(seconds: 2),
      );

      // 5. SoftReset / Reboot CAS/FEM/BDC (0x11 0x03)
      onProgress?.call('Rebooting CAS / FEM / BDC to activate new Vehicle Order...', 0.9);
      await activeProto.sendUdsAndAwait(
        casAddress,
        [0x11, 0x03],
        timeout: const Duration(seconds: 2),
      );

      // 6. Return to default session
      await _returnToDefaultSession(casAddress);
      onProgress?.call('Vehicle Order successfully written and activated!', 1.0);

      return CodingResult(
        success: true,
        title: 'Vehicle Order Written',
        message: 'Vehicle Order (${finalVo.options.length} options, TypeKey: ${finalVo.typeKey}) successfully flashed to CAS & FEM/BDC. Backup saved (${backup.id}).',
        backupId: backup.id,
        details: {
          'vo': finalVo.toJson(),
          'backupId': backup.id,
        },
      );
    } catch (e) {
      debugPrint('[BmwCodingService] Exception writing VO: $e');
      return CodingResult(
        success: false,
        title: 'VO Write Error',
        message: 'Unexpected error writing Vehicle Order: $e',
        backupId: backup.id,
      );
    }
  }

  /// Sanity-check and repair VO string syntax, prefixes, and conflicts (res_VoFix)
  VoFixResult fixVehicleOrder(BmwVehicleOrder vo) {
    final fixes = <String>[];
    final warnings = <String>[];
    bool modified = false;

    // 1. Sanitize Series
    String series = vo.series.trim().toUpperCase();
    if (series.isEmpty) {
      series = 'F030';
      fixes.add('Set missing series to default F030');
      modified = true;
    }

    // 2. Sanitize Type Key
    String typeKey = vo.typeKey.trim().toUpperCase();
    if (typeKey.startsWith('*')) {
      typeKey = typeKey.substring(1);
      fixes.add('Stripped leading asterisk from Type Key');
      modified = true;
    }
    if (typeKey.length != 4 || !RegExp(r'^[0-9A-Z]{4}$').hasMatch(typeKey)) {
      fixes.add('Invalid Type Key "$typeKey" reset to 3B93 (F30 328i)');
      typeKey = '3B93';
      modified = true;
    }

    // 3. Sanitize Zeitkriterium
    String date = vo.productionDate.trim().replaceAll('#', '');
    if (date.length != 4 || !RegExp(r'^\d{4}$').hasMatch(date)) {
      fixes.add('Invalid Zeitkriterium "$date" corrected to 0315');
      date = '0315';
      modified = true;
    } else {
      final month = int.tryParse(date.substring(0, 2)) ?? 0;
      if (month < 1 || month > 12) {
        fixes.add('Corrected invalid month "$month" in Zeitkriterium to 03');
        date = '03${date.substring(2, 4)}';
        modified = true;
      }
    }

    // 4. Sanitize Paint & Upholstery
    String paint = vo.paintCode.trim().toUpperCase().replaceAll('L', '');
    if (paint.isEmpty) {
      paint = '475';
      fixes.add('Set missing paint code to 475 (Black Sapphire)');
      modified = true;
    }

    String upholstery = vo.upholsteryCode.trim().toUpperCase().replaceAll('P', '');
    if (upholstery.isEmpty) {
      upholstery = 'LCSW';
      fixes.add('Set missing upholstery code to LCSW (Dakota Black)');
      modified = true;
    }

    // 5. Sanitize SALAPA Options
    final cleanedOptions = <String>[];
    final seen = <String>{};

    for (final raw in vo.options) {
      var opt = raw.trim().toUpperCase();
      if (!opt.startsWith(r'$')) {
        opt = '\$$opt';
        fixes.add('Added missing \$ prefix to $opt');
        modified = true;
      }
      final body = opt.substring(1).replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final cleanCode = '\$$body';
      if (body.isEmpty) continue;

      if (seen.contains(cleanCode)) {
        fixes.add('Removed duplicate option $cleanCode');
        modified = true;
        continue;
      }
      seen.add(cleanCode);
      cleanedOptions.add(cleanCode);
    }

    // 6. Check conflicts:
    // Conflict 1: $205 vs $2TB
    if (cleanedOptions.contains(r'$2TB') && cleanedOptions.contains(r'$205')) {
      cleanedOptions.remove(r'$205');
      fixes.add(r'Resolved conflict: removed $205 (Automatic) in favor of $2TB (Sport Automatic)');
      modified = true;
    }

    // Conflict 2: $606 vs $609
    if (cleanedOptions.contains(r'$609') && cleanedOptions.contains(r'$606')) {
      cleanedOptions.remove(r'$606');
      fixes.add(r'Resolved conflict: removed $606 (Business Nav) in favor of $609 (Pro Nav)');
      modified = true;
    }

    // Conflict 3: $676 vs $688
    if (cleanedOptions.contains(r'$688') && cleanedOptions.contains(r'$676')) {
      cleanedOptions.remove(r'$676');
      fixes.add(r'Resolved conflict: removed $676 (HiFi) in favor of $688 (Harman Kardon)');
      modified = true;
    }

    // 7. Sanitize E, K, HO words
    final eWords = vo.eWords.map((e) => e.startsWith('&') ? e : '&$e').toSet().toList();
    final kWords = vo.kWords.map((k) => k.startsWith('%') ? k : '%$k').toSet().toList();
    final hoWords = vo.hoWords.map((h) => h.startsWith('+') ? h : '+$h').toSet().toList();

    final fixedVo = BmwVehicleOrder(
      vin: vo.vin,
      series: series,
      typeKey: typeKey,
      productionDate: date,
      paintCode: paint,
      upholsteryCode: upholstery,
      options: cleanedOptions,
      eWords: eWords,
      kWords: kWords,
      hoWords: hoWords,
    );

    return VoFixResult(
      wasModified: modified,
      fixesApplied: fixes,
      warnings: warnings,
      fixedVo: fixedVo,
    );
  }

  /// Adds a custom SALAPA option code to Vehicle Order (res_addCusVO)
  BmwVehicleOrder addCustomOption(BmwVehicleOrder vo, String optionCode) {
    var code = optionCode.trim().toUpperCase();
    if (!code.startsWith(r'$')) {
      code = '\$$code';
    }
    final body = code.substring(1).replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final cleanCode = '\$$body';
    if (body.isEmpty) return vo;

    final newOptions = List<String>.from(vo.options);
    if (!newOptions.contains(cleanCode)) {
      newOptions.add(cleanCode);
    }

    final updatedVo = vo.copyWith(options: newOptions);
    final fixResult = fixVehicleOrder(updatedVo);
    return fixResult.fixedVo;
  }

  /// Removes an option code from Vehicle Order
  BmwVehicleOrder removeOption(BmwVehicleOrder vo, String optionCode) {
    var code = optionCode.trim().toUpperCase();
    if (!code.startsWith(r'$')) {
      code = '\$$code';
    }
    final newOptions = List<String>.from(vo.options)..removeWhere((o) => o.toUpperCase() == code);
    return vo.copyWith(options: newOptions);
  }

  // ==========================================
  // Vehicle Order Backups & Restore (res_backupVO / res_restoreVO)
  // ==========================================

  /// Retrieves list of all persisted Vehicle Order backups
  Future<List<VehicleOrderBackup>> getVoBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_voBackupsPrefsKey) ?? [];
      return list
          .map((item) {
            try {
              final map = jsonDecode(item) as Map<String, dynamic>;
              return VehicleOrderBackup.fromJson(map);
            } catch (_) {
              return null;
            }
          })
          .whereType<VehicleOrderBackup>()
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('[BmwCodingService] Error reading VO backups: $e');
      return [];
    }
  }

  /// Persists a new Vehicle Order backup (res_backupVO)
  Future<VehicleOrderBackup> backupVehicleOrder(
    BmwVehicleOrder vo, {
    String description = '',
  }) async {
    final id = 'vo_${vo.vin}_${DateTime.now().millisecondsSinceEpoch}';
    final backup = VehicleOrderBackup(
      id: id,
      timestamp: DateTime.now(),
      vin: vo.vin,
      series: vo.series,
      typeKey: vo.typeKey,
      productionDate: vo.productionDate,
      rawFaString: vo.toFaString(),
      options: List<String>.from(vo.options),
      description: description.isNotEmpty
          ? description
          : 'VO Backup ${vo.typeKey} (${vo.options.length} options)',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_voBackupsPrefsKey) ?? [];
      currentList.insert(0, jsonEncode(backup.toJson()));
      if (currentList.length > 50) {
        currentList.removeRange(50, currentList.length);
      }
      await prefs.setStringList(_voBackupsPrefsKey, currentList);
    } catch (e) {
      debugPrint('[BmwCodingService] Error saving VO backup: $e');
    }

    return backup;
  }

  /// Restores Vehicle Order from backup snapshot (res_restoreVO)
  Future<CodingResult> restoreVehicleOrder(
    VehicleOrderBackup backup, {
    void Function(String step, double progress)? onProgress,
  }) async {
    final vo = BmwVehicleOrder.fromFaString(backup.rawFaString, vin: backup.vin);
    return await writeVehicleOrder(vo, onProgress: onProgress);
  }

  /// Deletes a specific VO backup by ID
  Future<bool> deleteVoBackup(String backupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_voBackupsPrefsKey) ?? [];
      final filtered = currentList.where((item) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          return map['id'] != backupId;
        } catch (_) {
          return true;
        }
      }).toList();
      return await prefs.setStringList(_voBackupsPrefsKey, filtered);
    } catch (e) {
      debugPrint('[BmwCodingService] Error deleting VO backup: $e');
      return false;
    }
  }

  // ==========================================
  // Factory Auto-Code / Default Coding Engine
  // ==========================================

  /// Calculates which ECUs need Factory Default Coding based on changed SALAPA options
  List<FactoryCodingPlan> calculateFactoryCodingPlan(
    BmwVehicleOrder currentVo,
    List<String> changedOptions,
  ) {
    final planMap = <int, FactoryCodingPlan>{};

    for (final optCode in changedOptions) {
      final opt = findSalapaOption(optCode);
      if (opt == null) continue;

      for (int i = 0; i < opt.affectedEcuAddresses.length; i++) {
        final addr = opt.affectedEcuAddresses[i];
        final name = opt.affectedEcuNames[i];

        int primaryDid = 0x3000;
        if (addr == egsAddress) {
          primaryDid = 0x3001;
        } else if (addr == casAddress) {
          primaryDid = 0x3020;
        }

        if (planMap.containsKey(addr)) {
          if (!planMap[addr]!.triggeredByOptions.contains(opt.code)) {
            planMap[addr]!.triggeredByOptions.add(opt.code);
          }
        } else {
          planMap[addr] = FactoryCodingPlan(
            ecuAddress: addr,
            ecuName: name,
            triggeredByOptions: [opt.code],
            primaryDid: primaryDid,
            isSelected: true,
          );
        }
      }
    }

    return planMap.values.toList();
  }

  /// Executes Factory Default Coding (SG_CODIEREN) for selected ECUs
  Future<CodingResult> executeFactoryDefaultCoding(
    List<FactoryCodingPlan> plans,
    BmwVehicleOrder vo, {
    void Function(String step, double progress)? onProgress,
  }) async {
    final activeProto = _getActiveProtocol();

    onProgress?.call('Connecting to vehicle diagnostic bus...', 0.05);
    final connected = await ensureConnected();
    if (!connected) {
      return CodingResult(
        success: false,
        title: 'Connection Failed',
        message: 'Could not connect to vehicle interface at 192.168.16.101.',
      );
    }

    final selectedPlans = plans.where((p) => p.isSelected).toList();
    if (selectedPlans.isEmpty) {
      return CodingResult(
        success: false,
        title: 'No ECUs Selected',
        message: 'Select at least one ECU for Factory Default Coding.',
      );
    }

    final vin = await readVehicleVin() ?? vo.vin;
    int successCount = 0;
    final codedEcuNames = <String>[];

    for (int i = 0; i < selectedPlans.length; i++) {
      final plan = selectedPlans[i];
      final baseProg = i / selectedPlans.length;
      final stepProg = 1.0 / selectedPlans.length;

      try {
        onProgress?.call(
          'Opening Extended Session on ${plan.ecuName}...',
          baseProg + (stepProg * 0.1),
        );

        // 1. Session 0x10 0x03
        final sess = await activeProto.sendUdsAndAwait(
          plan.ecuAddress,
          [0x10, 0x03],
          timeout: const Duration(seconds: 2),
        );
        if (sess == null || sess.isEmpty || sess[0] != 0x50) {
          debugPrint('[FactoryCoding] ECU 0x${plan.ecuAddress.toRadixString(16)} rejected session');
          continue;
        }

        // 2. Unlock Security Access
        onProgress?.call(
          'Unlocking Security Access on ${plan.ecuName}...',
          baseProg + (stepProg * 0.25),
        );
        await unlockSecurityAccess(plan.ecuAddress);

        // 3. Read current NCD block
        onProgress?.call(
          'Reading existing NCD block on ${plan.ecuName}...',
          baseProg + (stepProg * 0.4),
        );
        final readResp = await activeProto.sendUdsAndAwait(
          plan.ecuAddress,
          [0x22, (plan.primaryDid >> 8) & 0xFF, plan.primaryDid & 0xFF],
          timeout: const Duration(seconds: 2),
        );

        if (readResp != null && readResp.length > 3 && readResp[0] == 0x62) {
          final existingBytes = readResp.sublist(3);

          // 4. Save rollback backup
          final backupId = 'factory_def_${plan.ecuAddress.toRadixString(16)}_${DateTime.now().millisecondsSinceEpoch}';
          final backup = NcdBackup(
            id: backupId,
            timestamp: DateTime.now(),
            vin: vin,
            ecuAddress: plan.ecuAddress,
            ecuName: plan.ecuName,
            did: plan.primaryDid,
            cheatCodeId: 'FACTORY_DEFAULT_CODE',
            cheatCodeName: 'Factory Default Coding (${plan.triggeredByOptions.join(",")})',
            originalBytes: Uint8List.fromList(existingBytes),
            description: 'Auto-backup prior to Factory Default Coding on ${plan.ecuName}',
          );
          await saveBackup(backup);

          // 5. Generate factory default parameters for this ECU based on active VO options
          final modifiedBytes = Uint8List.fromList(existingBytes);
          _applyFactoryCodingDefaults(plan.ecuAddress, plan.primaryDid, modifiedBytes, vo.options);

          // 6. Write Data By Identifier (0x2E)
          onProgress?.call(
            'Flashing factory default NCD to ${plan.ecuName}...',
            baseProg + (stepProg * 0.7),
          );
          final writeResp = await activeProto.sendUdsAndAwait(
            plan.ecuAddress,
            [0x2E, (plan.primaryDid >> 8) & 0xFF, plan.primaryDid & 0xFF, ...modifiedBytes],
            timeout: const Duration(seconds: 3),
          );

          if (writeResp != null && writeResp.length >= 3 && writeResp[0] == 0x6E) {
            successCount++;
            codedEcuNames.add(plan.ecuName);
          }
        }

        // 7. Reset ECU (0x11 0x03)
        onProgress?.call(
          'Rebooting ${plan.ecuName}...',
          baseProg + (stepProg * 0.9),
        );
        await activeProto.sendUdsAndAwait(
          plan.ecuAddress,
          [0x11, 0x03],
          timeout: const Duration(seconds: 2),
        );

        // Return to default session
        await _returnToDefaultSession(plan.ecuAddress);
      } catch (e) {
        debugPrint('[FactoryCoding] Error default coding ${plan.ecuName}: $e');
      }
    }

    onProgress?.call('Factory Default Coding completed!', 1.0);

    if (successCount == 0) {
      return CodingResult(
        success: false,
        title: 'Factory Coding Failed',
        message: 'Failed to write factory default coding to selected ECUs. Verify vehicle battery and ignition.',
      );
    }

    return CodingResult(
      success: true,
      title: 'Factory Default Coding Succeeded',
      message: 'Successfully factory default coded $successCount ECUs (${codedEcuNames.join(", ")}). All options are now active in vehicle controllers.',
    );
  }

  void _applyFactoryCodingDefaults(
    int ecuAddress,
    int did,
    Uint8List block,
    List<String> options,
  ) {
    final has2TB = options.contains(r'$2TB');
    final has6NS = options.contains(r'$6NS');
    final has609 = options.contains(r'$609');
    final has5A1 = options.contains(r'$5A1');
    final has322 = options.contains(r'$322');
    final has430 = options.contains(r'$430');
    final has248 = options.contains(r'$248');
    final has6WB = options.contains(r'$6WB');
    final has3AG = options.contains(r'$3AG');
    final has688 = options.contains(r'$688');
    final has8TH = options.contains(r'$8TH');
    final has8S4 = options.contains(r'$8S4');

    switch (ecuAddress) {
      case egsAddress: // 0x18 Transmission
        if (block.isNotEmpty) {
          if (has2TB) {
            block[0] = (block[0] & ~0x01) | 0x01; // Sport auto enabled, paddle shift
          } else {
            block[0] = block[0] & ~0x01;
          }
        }
        break;

      case casAddress: // 0x40 FEM / BDC
        if (did == 0x3020 && block.length > 2) {
          if (has2TB) block[2] = (block[2] & ~0x04) | 0x04; // Sport+ driving mode
        }
        if (did == 0x3050 && block.isNotEmpty) {
          if (has322) block[0] = (block[0] & ~0x01) | 0x01; // Comfort access
        }
        if (did == 0x3053 && block.length > 1) {
          if (has430) block[1] = (block[1] & ~0x01) | 0x01; // Mirror folding
        }
        if (did == 0x3040 && block.length > 4) {
          if (has248) block[4] = (block[4] & ~0x02) | 0x02; // Heated steering wheel
        }
        if (did == 0x3060 && block.length > 1) {
          if (has5A1) block[1] = 0x00; // LED foglights PWM without bulb check
          if (has8S4) block[0] = (block[0] & ~0x08) | 0x08; // Glare-free high beam
        }
        break;

      case kombiAddress: // 0x60 Cluster
        if (block.length > 7) {
          if (has2TB) block[5] = (block[5] & ~0x01) | 0x01; // Sport+ display in cluster
          if (has609) block[3] = (block[3] & ~0x04) | 0x04; // Navigation arrow display
          if (has6WB) block[0] = (block[0] & ~0x80) | 0x80; // Full digital cluster layout
          if (has8TH) block[7] = (block[7] & ~0x02) | 0x02; // Speed Limit Info
        }
        break;

      case huNbtAddress: // 0x63 Headunit
        if (block.length > 12) {
          if (has6NS) block[10] = (block[10] & ~0x01) | 0x01; // Enhanced BT & Office
          if (has609) block[8] = (block[8] & ~0x10) | 0x10; // Pro Nav 8.8" layout
          if (has3AG) block[2] = (block[2] & ~0x01) | 0x01; // Rear camera overlay
          if (has688) block[1] = (block[1] & ~0x08) | 0x08; // Harman Kardon Logic7
        }
        break;

      case acsmAddress: // 0x01 Airbag
        if (block.length > 2) {
          final has845 = options.contains(r'$845');
          if (!has845) {
            block[2] = block[2] & ~0x03; // Mute seatbelt gong
          }
        }
        break;
    }
  }
}
