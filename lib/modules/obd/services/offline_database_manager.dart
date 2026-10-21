import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Offline data entity for an FDL Cheat Code extracted from LauncherPRO / E-Sys.
class OfflineFdlCheatCode {
  final String cafdId;
  final String cafdName;
  final String description;
  final String series;
  final String author;
  final String sourceFile;
  final List<OfflineFdlGroup> groups;

  const OfflineFdlCheatCode({
    required this.cafdId,
    required this.cafdName,
    required this.description,
    required this.series,
    required this.author,
    required this.sourceFile,
    required this.groups,
  });

  factory OfflineFdlCheatCode.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'] as List<dynamic>? ?? [];
    return OfflineFdlCheatCode(
      cafdId: json['cafd_id'] as String? ?? '',
      cafdName: json['cafd_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      series: json['series'] as String? ?? '',
      author: json['author'] as String? ?? '',
      sourceFile: json['source_file'] as String? ?? '',
      groups: rawGroups
          .map((g) => OfflineFdlGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OfflineFdlGroup {
  final String groupId;
  final List<OfflineFdlFunction> functions;

  const OfflineFdlGroup({
    required this.groupId,
    required this.functions,
  });

  factory OfflineFdlGroup.fromJson(Map<String, dynamic> json) {
    final rawFuncs = json['functions'] as List<dynamic>? ?? [];
    return OfflineFdlGroup(
      groupId: json['group_id'] as String? ?? '',
      functions: rawFuncs
          .map((f) => OfflineFdlFunction.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OfflineFdlFunction {
  final int start;
  final int end;
  final int mask;
  final String maskRaw;
  final String paramName;
  final String targetValue;

  const OfflineFdlFunction({
    required this.start,
    required this.end,
    required this.mask,
    required this.maskRaw,
    required this.paramName,
    required this.targetValue,
  });

  factory OfflineFdlFunction.fromJson(Map<String, dynamic> json) {
    return OfflineFdlFunction(
      start: json['start'] as int? ?? 0,
      end: json['end'] as int? ?? 0,
      mask: json['mask'] as int? ?? 0xFF,
      maskRaw: json['mask_raw'] as String? ?? '',
      paramName: json['param_name'] as String? ?? '',
      targetValue: json['target_value'] as String? ?? '',
    );
  }
}

/// Offline ECU definition from BMW KIS database.
class KisEcuDefinition {
  final int id;
  final String name;
  final int diagAddress;
  final String diagAddressHex;
  final String description;

  const KisEcuDefinition({
    required this.id,
    required this.name,
    required this.diagAddress,
    required this.diagAddressHex,
    required this.description,
  });

  factory KisEcuDefinition.fromJson(Map<String, dynamic> json) {
    return KisEcuDefinition(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      diagAddress: json['diag_addr_dec'] as int? ?? 0,
      diagAddressHex: json['diag_addr_hex'] as String? ?? '',
      description: json['desc'] as String? ?? '',
    );
  }
}

/// Offline I-Step level from BMW KIS database.
class KisILevel {
  final int id;
  final String name;
  final bool programmable;
  final String? description;

  const KisILevel({
    required this.id,
    required this.name,
    required this.programmable,
    this.description,
  });

  factory KisILevel.fromJson(Map<String, dynamic> json) {
    return KisILevel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      programmable: json['programmable'] as bool? ?? false,
      description: json['desc'] as String?,
    );
  }
}

/// Factory ISTA Service Routine definition.
class IstaServiceRoutine {
  final String id;
  final String name;
  final String description;
  final String ecuTarget;
  final String diagAddress;
  final String routineType;
  final List<String>? items;
  final List<String>? preconditions;
  final List<String>? supportedTypes;
  final String? udsRoutineId;
  final String? udsJob;
  final String? udsDid;
  final String safetyLevel;

  const IstaServiceRoutine({
    required this.id,
    required this.name,
    required this.description,
    required this.ecuTarget,
    required this.diagAddress,
    required this.routineType,
    this.items,
    this.preconditions,
    this.supportedTypes,
    this.udsRoutineId,
    this.udsJob,
    this.udsDid,
    required this.safetyLevel,
  });

  factory IstaServiceRoutine.fromJson(Map<String, dynamic> json) {
    return IstaServiceRoutine(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      ecuTarget: json['ecu_target'] as String? ?? '',
      diagAddress: json['diag_address'] as String? ?? '',
      routineType: json['routine_type'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      preconditions: (json['preconditions'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      supportedTypes: (json['supported_types'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      udsRoutineId: json['uds_routine_id'] as String?,
      udsJob: json['uds_job'] as String?,
      udsDid: json['uds_did'] as String?,
      safetyLevel: json['safety_level'] as String? ?? 'safe',
    );
  }
}

/// Unified 100% Offline Database Manager for FIX AI.
/// Loads pre-extracted ISTA+ 4.59.30, PSdZData, and E-Sys LauncherPRO databases
/// directly from the application's offline assets bundle with zero network dependency.
class OfflineDatabaseManager {
  static final OfflineDatabaseManager instance = OfflineDatabaseManager._internal();
  OfflineDatabaseManager._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  List<OfflineFdlCheatCode> _fdlCheatCodes = [];
  Map<String, dynamic> _kisData = {};
  List<IstaServiceRoutine> _serviceRoutines = [];
  Map<String, dynamic> _ecuDiagnosticJobs = {};

  // Fast index caches
  final Map<String, List<OfflineFdlCheatCode>> _codesByCafd = {};
  final Map<String, List<OfflineFdlCheatCode>> _codesByEcuName = {};
  final Map<int, KisEcuDefinition> _ecuByDiagAddr = {};

  /// Initializes all offline databases from assets bundle asynchronously.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('[OfflineDatabaseManager] Initializing offline databases from assets bundle...');

      // 1. Load FDL Cheat Codes (2,561 entries)
      final fdlString = await rootBundle.loadString('assets/offline_db/fdl_cheat_codes.json');
      final fdlJson = json.decode(fdlString) as Map<String, dynamic>;
      final rawCodes = fdlJson['codes'] as List<dynamic>? ?? [];
      _fdlCheatCodes = rawCodes
          .map((c) => OfflineFdlCheatCode.fromJson(c as Map<String, dynamic>))
          .toList();

      for (final code in _fdlCheatCodes) {
        final cid = code.cafdId.toUpperCase();
        _codesByCafd.putIfAbsent(cid, () => []).add(code);

        final cname = code.cafdName.toUpperCase();
        if (cname.isNotEmpty) {
          _codesByEcuName.putIfAbsent(cname, () => []).add(code);
        }
      }
      debugPrint('[OfflineDatabaseManager] Loaded ${_fdlCheatCodes.length} FDL cheat codes.');

      // 2. Load KIS Compatibility Database
      final kisString = await rootBundle.loadString('assets/offline_db/kis_compatibility.json');
      _kisData = json.decode(kisString) as Map<String, dynamic>;
      
      // Index ECUs by diagnostic address
      final seriesMap = _kisData['series'] as Map<String, dynamic>? ?? {};
      for (final sEntry in seriesMap.values) {
        final ecus = (sEntry as Map<String, dynamic>)['ecus'] as List<dynamic>? ?? [];
        for (final e in ecus) {
          final ecuDef = KisEcuDefinition.fromJson(e as Map<String, dynamic>);
          _ecuByDiagAddr.putIfAbsent(ecuDef.diagAddress, () => ecuDef);
        }
      }
      debugPrint('[OfflineDatabaseManager] Loaded KIS compatibility with ${_ecuByDiagAddr.length} indexed ECUs.');

      // 3. Load ISTA Service Functions & ECU Jobs
      final istaString = await rootBundle.loadString('assets/offline_db/ista_service_functions.json');
      final istaJson = json.decode(istaString) as Map<String, dynamic>;
      final rawRoutines = istaJson['service_routines'] as List<dynamic>? ?? [];
      _serviceRoutines = rawRoutines
          .map((r) => IstaServiceRoutine.fromJson(r as Map<String, dynamic>))
          .toList();
      _ecuDiagnosticJobs = istaJson['ecu_diagnostic_jobs'] as Map<String, dynamic>? ?? {};
      debugPrint('[OfflineDatabaseManager] Loaded ${_serviceRoutines.length} factory service routines.');

      _isInitialized = true;
    } catch (e, st) {
      debugPrint('[OfflineDatabaseManager] Failed to initialize offline database: $e\n$st');
    }
  }

  /// Returns all 2,561 FDL cheat codes.
  List<OfflineFdlCheatCode> getAllCheatCodes() => List.unmodifiable(_fdlCheatCodes);

  /// Filters cheat codes by CAFD ID, ECU Name, or Series.
  List<OfflineFdlCheatCode> getCheatCodes({
    String? cafdId,
    String? ecuName,
    String? series,
  }) {
    Iterable<OfflineFdlCheatCode> result = _fdlCheatCodes;

    if (cafdId != null && cafdId.isNotEmpty) {
      final key = cafdId.toUpperCase();
      result = _codesByCafd[key] ?? [];
    } else if (ecuName != null && ecuName.isNotEmpty) {
      final key = ecuName.toUpperCase();
      result = _codesByEcuName[key] ?? result.where((c) => c.cafdName.toUpperCase().contains(key));
    }

    if (series != null && series.isNotEmpty) {
      final sUpper = series.toUpperCase();
      result = result.where((c) =>
          c.series.isEmpty ||
          c.series.toUpperCase().contains(sUpper) ||
          sUpper.contains(c.series.toUpperCase()));
    }

    return result.toList();
  }

  /// Full-text search across cheat code descriptions and parameter names.
  List<OfflineFdlCheatCode> searchCheatCodes(String query) {
    if (query.trim().isEmpty) return _fdlCheatCodes;
    final q = query.toLowerCase();

    return _fdlCheatCodes.where((code) {
      if (code.description.toLowerCase().contains(q)) return true;
      if (code.cafdName.toLowerCase().contains(q)) return true;
      if (code.cafdId.toLowerCase().contains(q)) return true;
      for (final grp in code.groups) {
        for (final fn in grp.functions) {
          if (fn.paramName.toLowerCase().contains(q)) return true;
        }
      }
      return false;
    }).toList();
  }

  /// Resolves an ECU by its UDS physical diagnosis address (e.g. 0x12 -> DME, 0x40 -> CAS, 0x10 -> ZGW).
  KisEcuDefinition? resolveEcuByAddress(int diagAddress) {
    return _ecuByDiagAddr[diagAddress];
  }

  /// Resolves chassis models for a main series (e.g. F025 -> [F25, F26, F15, F16, F85, F86]).
  List<String> getChassisForSeries(String mainSeries) {
    final sUpper = mainSeries.toUpperCase();
    final seriesMap = _kisData['series'] as Map<String, dynamic>? ?? {};
    final sData = seriesMap[sUpper] as Map<String, dynamic>?;
    if (sData == null) return [];

    final rawChassis = sData['chassis'] as List<dynamic>? ?? [];
    return rawChassis
        .map((c) => (c as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Returns all I-Step levels available for a main series.
  List<KisILevel> getILevelsForSeries(String mainSeries) {
    final sUpper = mainSeries.toUpperCase();
    final seriesMap = _kisData['series'] as Map<String, dynamic>? ?? {};
    final sData = seriesMap[sUpper] as Map<String, dynamic>?;
    if (sData == null) return [];

    final rawLevels = sData['i_levels'] as List<dynamic>? ?? [];
    return rawLevels
        .map((il) => KisILevel.fromJson(il as Map<String, dynamic>))
        .toList();
  }

  /// Returns all factory ISTA Service Routines.
  List<IstaServiceRoutine> getServiceRoutines() => List.unmodifiable(_serviceRoutines);

  /// Resolves a single factory ISTA Service Routine by its ID.
  IstaServiceRoutine? getServiceRoutine(String routineId) {
    try {
      return _serviceRoutines.firstWhere((r) => r.id == routineId);
    } catch (_) {
      return null;
    }
  }

  /// Resolves an ECU diagnostic job and its telemetry status results from EcuFunctions.
  Map<String, dynamic>? getEcuDiagnosticJob(String jobName) {
    return _ecuDiagnosticJobs[jobName] as Map<String, dynamic>?;
  }
}
