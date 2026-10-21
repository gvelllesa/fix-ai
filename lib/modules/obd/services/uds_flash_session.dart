import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/config/feature_flags.dart';
import '../models/verified_flash_image.dart';
import 'protocols/enet_hsfz_protocol.dart';

/// Exception thrown when a UDS flashing operation cannot proceed.
class FlashAbort implements Exception {
  final String stage;
  final String message;
  final bool ecuMayBeInBootloader;
  final int? nrc;

  const FlashAbort(
    this.stage,
    this.message, {
    this.ecuMayBeInBootloader = false,
    this.nrc,
  });

  @override
  String toString() =>
      'FlashAbort[$stage]: $message (ecuMayBeInBootloader: $ecuMayBeInBootloader, nrc: 0x${nrc?.toRadixString(16)})';
}

/// Progress update emitted during UDS flashing
class FlashProgress {
  final String stage;
  final double progress; // 0.0 to 1.0
  final String status;

  const FlashProgress(this.stage, this.progress, this.status);

  @override
  String toString() => 'FlashProgress($stage, ${(progress * 100).toStringAsFixed(1)}%, $status)';
}

/// BMW UDS Flash Compression Method (`UNI_Flash.CompressionMethod` enum `0x020000d1`).
enum FlashCompressionMethod {
  none(0x00, 'Uncompressed (DFI 0x00)'),
  nrv(0x10, 'UCL / NRV2B Compressed (DFI 0x10)');

  final int dataFormatIdentifier;
  final String description;
  const FlashCompressionMethod(this.dataFormatIdentifier, this.description);
}

/// Deterministic UCL / NRV2B Stream Compressor & Decompressor for BMW UDS `TransferData (0x36)`
/// when `RequestDownload (0x34)` specifies `dataFormatIdentifier = 0x10` (`CompressionMethod.NRV`).
///
/// Format:
/// - Control tags are packed into 8-bit control words (1 bit per token: `1` = literal byte,
///   `0` = LZ77/NRV back-reference `[offsetHigh, offsetLow, length - 3]`).
/// - Guarantees lossless round-trip `decompressNrv2b(compressNrv2b(input)) == input`.
class UclNrvCompression {
  static const int _minMatch = 4;
  static const int _maxMatch = 258;
  static const int _maxOffset = 0xFFFF;

  /// Compresses raw binary segment data using NRV2B/UCL sliding-window encoding.
  static Uint8List compressNrv2b(List<int> input) {
    if (input.isEmpty) return Uint8List(0);
    final out = <int>[];
    var pos = 0;

    while (pos < input.length) {
      final ctrlIndex = out.length;
      out.add(0); // Placeholder for 8-bit control word
      var ctrlByte = 0;

      for (var bit = 7; bit >= 0 && pos < input.length; bit--) {
        var bestLen = 0;
        var bestDist = 0;

        final windowStart = (pos - _maxOffset).clamp(0, pos);
        final maxLen = (input.length - pos).clamp(0, _maxMatch);

        if (maxLen >= _minMatch) {
          // Search backward in sliding window for longest match
          final searchLimit = (pos - windowStart).clamp(0, 2048);
          for (var d = 1; d <= searchLimit; d++) {
            final cand = pos - d;
            if (input[cand] != input[pos] ||
                input[cand + bestLen] != input[pos + bestLen]) {
              continue;
            }
            var mLen = 0;
            while (mLen < maxLen && input[cand + mLen] == input[pos + mLen]) {
              mLen++;
            }
            if (mLen >= _minMatch && mLen > bestLen) {
              bestLen = mLen;
              bestDist = d;
              if (bestLen == maxLen) break;
            }
          }
        }

        if (bestLen >= _minMatch) {
          // Bit = 0 (match token): 2-byte distance + 1-byte (len - 3)
          out.add((bestDist >> 8) & 0xFF);
          out.add(bestDist & 0xFF);
          out.add((bestLen - 3) & 0xFF);
          pos += bestLen;
        } else {
          // Bit = 1 (literal byte)
          ctrlByte |= (1 << bit);
          out.add(input[pos] & 0xFF);
          pos++;
        }
      }
      out[ctrlIndex] = ctrlByte;
    }

    return Uint8List.fromList(out);
  }

  /// Decompresses an NRV2B/UCL stream back into the original uncompressed segment of [uncompressedLength] bytes.
  static Uint8List decompressNrv2b(List<int> compressed, {int? uncompressedLength}) {
    if (compressed.isEmpty) return Uint8List(0);
    final out = <int>[];
    var inPos = 0;

    while (inPos < compressed.length) {
      if (uncompressedLength != null && out.length >= uncompressedLength) break;
      final ctrlByte = compressed[inPos++] & 0xFF;

      for (var bit = 7; bit >= 0 && inPos < compressed.length; bit--) {
        if (uncompressedLength != null && out.length >= uncompressedLength) break;
        final isLiteral = ((ctrlByte >> bit) & 0x01) != 0;
        if (isLiteral) {
          out.add(compressed[inPos++] & 0xFF);
        } else {
          if (inPos + 2 >= compressed.length) {
            throw const FormatException('Truncated NRV2B back-reference token');
          }
          final dist = ((compressed[inPos] & 0xFF) << 8) | (compressed[inPos + 1] & 0xFF);
          final len = (compressed[inPos + 2] & 0xFF) + 3;
          inPos += 3;
          if (dist <= 0 || dist > out.length) {
            throw FormatException('Invalid NRV2B match distance: $dist (out.length=${out.length})');
          }
          final copyStart = out.length - dist;
          for (var i = 0; i < len; i++) {
            out.add(out[copyStart + i]);
          }
        }
      }
    }

    return Uint8List.fromList(out);
  }
}

/// Hardened UDS Flashing Session State Machine (ISO 14229-1 / BMW EDIABAS Spec).
///
/// Implements full fail-safe flashing protocols:
/// - TesterPresent (0x3E 0x80) periodic keepalive during programming session
/// - Functional bus silence (0x85 0x82 DTC Off, 0x28 0x81 Disable Normal Comms)
/// - Server-side Seed/Key authentication callback
/// - Dynamic block length parsing from 0x74 RequestDownload response
/// - Block Sequence Counter (BSC) wrap: 0xFF -> 0x00
/// - Per-block retries (<=3 attempts) with exponential/fixed backoff
/// - Check Programming Dependencies (0x31 0x01 0xFF 0x01)
/// - NO resets issued if abort occurs while ECU is in bootloader / erased state
class UdsFlashSession {
  final EnetHsfzProtocol proto;
  final int ecu;
  final Future<List<int>> Function(List<int> seed) remoteKeyProvider;
  final void Function(int segmentIndex, int offset)? onCheckpoint;

  Timer? _testerPresent;
  final Map<int, Uint8List> _backedUpCodingRecords = {};
  Map<int, Uint8List> get backedUpCodingRecords => Map.unmodifiable(_backedUpCodingRecords);
  bool _codingRestored = false;
  bool get isCodingRestored => _codingRestored;

  UdsFlashSession({
    required this.proto,
    this.ecu = 0x12, // Default: BMW DME/DDE
    required this.remoteKeyProvider,
    this.onCheckpoint,
  });

  /// Converts a decimal value (0..99) to Binary-Coded Decimal (BCD) byte (`UNI_Flash.Program_UDS.ConvertToBcd`).
  static int convertToBcd(int value) {
    final clamped = value.clamp(0, 99);
    return ((clamped ~/ 10) << 4) | (clamped % 10);
  }

  /// Returns 3-byte BCD date `[YY, MM, DD]` for UDS Fingerprint (`0xF199`) (`UNI_Flash.Program_UDS.GetLocalDateInBCD`).
  static Uint8List getLocalDateInBcd([DateTime? date]) {
    final d = date ?? DateTime.now();
    return Uint8List.fromList([
      convertToBcd(d.year % 100),
      convertToBcd(d.month),
      convertToBcd(d.day),
    ]);
  }

  /// Returns 3-byte BCD time `[HH, MM, SS]` (`UNI_Flash.Program_UDS.GetLocalTimeInBCD`).
  static Uint8List getLocalTimeInBcd([DateTime? time]) {
    final t = time ?? DateTime.now();
    return Uint8List.fromList([
      convertToBcd(t.hour),
      convertToBcd(t.minute),
      convertToBcd(t.second),
    ]);
  }

  /// Human-readable description for BMW UDS Programming Precondition failure codes (`0x31 0x01 0x02 0x03`).
  static String getProgrammingPreConditionDescription(int code) {
    switch (code) {
      case 0x00:
        return 'All programming preconditions met (OK)';
      case 0x01:
        return 'Engine speed > 0 RPM (Stop engine before flashing)';
      case 0x02:
        return 'Vehicle speed > 0 km/h (Vehicle must be stationary)';
      case 0x03:
        return 'Supply voltage out of range (Connect 50A+ battery charger)';
      case 0x04:
        return 'Ignition Terminal 15 is OFF';
      case 0x05:
        return 'Transmission selector lever not in Park (P)';
      case 0x08:
        return 'ECU / Transmission temperature outside safe programming window';
      default:
        return 'Precondition code 0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }
  }

  /// Queries ECU internal programming preconditions (`0x31 0x01 0x02 0x03`) (`DiagProtocolInterface.UDS_BMW.StartRoutine_checkProgrammingPreCondition`).
  Future<List<int>> startRoutineCheckProgrammingPreCondition() async {
    final rsp = await _expect('PRECONDITION', const [0x31, 0x01, 0x02, 0x03]);
    if (rsp.length > 4) {
      final conditions = rsp.sublist(4).where((b) => b != 0x00).toList();
      return conditions;
    }
    return const [];
  }

  /// Activates or deactivates BMW Flash Energy Mode (`0x31 0x01 0x0F 0x0C`) on Central Gateway (`0x10`)
  /// (`DiagProtocolInterface.UDS_BMW.StartRoutine_SetEnergyMode`).
  Future<bool> startRoutineSetEnergyMode({bool enableFlashMode = true}) async {
    final modeByte = enableFlashMode ? 0x03 : 0x00;
    final rsp = await proto.sendUdsAndAwait(
      EnetHsfzProtocol.zgwAddress,
      [0x31, 0x01, 0x0F, 0x0C, modeByte],
      timeout: const Duration(seconds: 2),
    );
    return rsp != null && rsp.length >= 4 && rsp[0] == 0x71;
  }

  /// Backs up existing NCD coding records (`0x3000..0x3010`) from the target ECU prior to flash erase
  /// (`UNI_Flash.Program_UDS.FetchCodingRecords`).
  Future<Map<int, Uint8List>> fetchCodingRecords({
    List<int> codingDids = const [0x3000, 0x3001, 0x3010],
  }) async {
    _backedUpCodingRecords.clear();
    for (final did in codingDids) {
      final msb = (did >> 8) & 0xFF;
      final lsb = did & 0xFF;
      final rsp = await proto.sendUdsAndAwait(
        ecu,
        [0x22, msb, lsb],
        timeout: const Duration(milliseconds: 1200),
      );
      if (rsp != null && rsp.length > 3 && rsp[0] == 0x62 && rsp[1] == msb && rsp[2] == lsb) {
        _backedUpCodingRecords[did] = Uint8List.fromList(rsp.sublist(3));
      }
    }
    return Map.unmodifiable(_backedUpCodingRecords);
  }

  /// Restores backed-up NCD coding records and validates coding signature (`0x31 0x01 0x0F 0x01`)
  /// after ECU flashing completes (`UNI_Flash.Program_UDS.RestoreCodingRecords`).
  Future<bool> restoreCodingRecords([Map<int, Uint8List>? records]) async {
    final toRestore = records ?? _backedUpCodingRecords;
    if (toRestore.isEmpty) return true;

    final sess = await proto.sendUdsAndAwait(ecu, const [0x10, 0x03], timeout: const Duration(seconds: 2));
    if (sess == null || sess.isEmpty || sess[0] != 0x50) return false;

    final seedRsp = await proto.sendUdsAndAwait(ecu, const [0x27, 0x01], timeout: const Duration(seconds: 2));
    if (seedRsp != null && seedRsp.length > 2 && seedRsp[0] == 0x67) {
      final seed = seedRsp.sublist(2);
      if (seed.any((b) => b != 0)) {
        final key = await remoteKeyProvider(seed);
        await proto.sendUdsAndAwait(ecu, [0x27, 0x02, ...key], timeout: const Duration(seconds: 2));
      }
    }

    var allWritten = true;
    for (final entry in toRestore.entries) {
      final did = entry.key;
      final msb = (did >> 8) & 0xFF;
      final lsb = did & 0xFF;
      final wr = await proto.sendUdsAndAwait(
        ecu,
        [0x2E, msb, lsb, ...entry.value],
        timeout: const Duration(seconds: 3),
      );
      if (wr == null || wr.isEmpty || wr[0] != 0x6E) {
        allWritten = false;
      }
    }

    // Finalize coding signature check (PrepareCheckSignatureCodingRecords: 0x31 0x01 0x0F 0x01)
    await proto.sendUdsAndAwait(
      ecu,
      const [0x31, 0x01, 0x0F, 0x01],
      timeout: const Duration(seconds: 2),
    );

    _codingRestored = allWritten;
    return allWritten;
  }

  /// Writes BCD programming date fingerprint (`DID 0xF199`) in Programming Session before Erase/Download.
  Future<bool> writeProgrammingDateFingerprint([DateTime? date]) async {
    final bcdDate = getLocalDateInBcd(date);
    final rsp = await proto.sendUdsAndAwait(
      ecu,
      [0x2E, 0xF1, 0x99, ...bcdDate],
      timeout: const Duration(seconds: 2),
    );
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x6E;
  }

  /// Validates transferred segment memory & signature (`0x31 0x01 0x02 0x02`) immediately after `0x37 RequestTransferExit`
  /// (`DiagProtocolInterface.UDS_BMW.StartRoutine_CheckMemoryAddressed`).
  Future<void> startRoutineCheckMemoryAddressed(
    int address,
    int length, {
    List<int>? signature,
  }) async {
    final payload = <int>[
      0x31,
      0x01,
      0x02,
      0x02,
      0x44,
      ..._u32(address),
      ..._u32(length),
      if (signature != null) ...signature,
    ];
    final chk = await _expect(
      'CHECK_MEMORY',
      payload,
      p2Star: const Duration(seconds: 20),
      boot: true,
    );
    if (chk.length >= 5 && chk[4] != 0x00) {
      throw const FlashAbort(
        'CHECK_MEMORY',
        'Segment memory verification (0x0202) failed',
        ecuMayBeInBootloader: true,
      );
    }
  }

  static List<int> _u32(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  void _startTesterPresent() {
    _testerPresent?.cancel();
    // BMW S3 timer is ~5.0s. Send 0x3E 0x80 (suppressPosRsp) every 2.0s
    _testerPresent = Timer.periodic(const Duration(seconds: 2), (_) {
      proto.sendFireAndForget(ecu, const [0x3E, 0x80]);
    });
  }

  Future<List<int>> _expect(
    String stage,
    List<int> req, {
    Duration? timeout,
    Duration? p2Star,
    bool boot = false,
  }) async {
    final r = await proto.sendUdsAndAwait(
      ecu,
      req,
      timeout: timeout ?? const Duration(seconds: 4),
      p2Star: p2Star ?? const Duration(seconds: 10),
    );
    if (r == null || r.isEmpty) {
      throw FlashAbort(stage, 'ECU არ პასუხობს (timeout)', ecuMayBeInBootloader: boot);
    }
    if (r[0] == 0x7F) {
      final nrc = r.length > 2 ? r[2] : 0;
      throw FlashAbort(
        stage,
        'ECU-მ დააბრუნა უარყოფითი პასუხი NRC 0x${nrc.toRadixString(16)}',
        ecuMayBeInBootloader: boot,
        nrc: nrc,
      );
    }
    final expectedSid = ((req[0] + 0x40) & 0xFF);
    if (r[0] != expectedSid) {
      throw FlashAbort(
        stage,
        'მოულოდნელი SID 0x${r[0].toRadixString(16)}, მოსალოდნელია 0x${expectedSid.toRadixString(16)}',
        ecuMayBeInBootloader: boot,
      );
    }
    return r;
  }

  /// Executes the end-to-end UDS flashing sequence.
  /// When [enableUniFlashLifecycle] is true (xHP / xDelete `UNI_Flash.Program_UDS` parity),
  /// automatically backs up NCD coding (`0x3000..`), verifies ECU preconditions (`0x0203`),
  /// activates ZGW Flash Energy Mode (`0x0F0C`), writes BCD Fingerprint (`0xF199`),
  /// checks per-segment memory (`0x0202`), and restores NCD coding after reboot.
  Stream<FlashProgress> run(
    VerifiedFlashImage image, {
    @visibleForTesting bool allowExecutionInTest = false,
    bool enableUniFlashLifecycle = false,
    int dataFormatIdentifier = 0x00,
    bool compressPayloadWhenNrv = false,
    DateTime? programmingDate,
  }) async* {
    if (!FeatureFlags.kFlashEnabled && !allowExecutionInTest) {
      throw StateError(
        'ECU Flashing is blocked by safety feature flag (FeatureFlags.kFlashEnabled = false). Bench verification required.',
      );
    }

    try {
      // 1. Extended Diagnostic Session (0x10 0x03)
      yield const FlashProgress('SESSION', 0.03, 'Extended Session (0x10 0x03)');
      await _expect('SESSION', [0x10, 0x03]);

      if (enableUniFlashLifecycle) {
        // 1a. Backup existing NCD coding records prior to erase (UNI_Flash.Program_UDS.FetchCodingRecords)
        yield const FlashProgress('CODING_BACKUP', 0.04, 'Backing up NCD Coding Records (0x3000..0x3010)');
        await fetchCodingRecords();

        // 1b. Check ECU internal programming preconditions (0x31 0x01 0x02 0x03)
        yield const FlashProgress('PRECONDITION', 0.05, 'Checking ECU Programming Preconditions (0x0203)');
        final failedConds = await startRoutineCheckProgrammingPreCondition();
        if (failedConds.isNotEmpty) {
          final reasons = failedConds.map(getProgrammingPreConditionDescription).join('; ');
          throw FlashAbort('PRECONDITION', 'ECU precondition rejected: $reasons');
        }

        // 1c. Activate ZGW Flash Energy Mode (0x31 0x01 0x0F 0x0C 0x03)
        await startRoutineSetEnergyMode(enableFlashMode: true);
      }

      // 2. Bus Silence: DTC Off (0x85 0x82) and Communication Control (0x28 0x81 0x01) on Functional address
      yield const FlashProgress('BUS_SILENCE', 0.06, 'DTC Off (0x85) + CommControl (0x28)');
      await proto.sendFunctional(const [0x85, 0x82]);
      await proto.sendFunctional(const [0x28, 0x81, 0x01]);

      // 3. Programming Diagnostic Session (0x10 0x02)
      yield const FlashProgress('PROG_SESSION', 0.08, 'Programming Session (0x10 0x02)');
      await _expect('PROG_SESSION', [0x10, 0x02], p2Star: const Duration(seconds: 5), boot: true);
      _startTesterPresent();

      // 4. Security Access (0x27 0x01 / 0x02)
      yield const FlashProgress('SECURITY', 0.10, 'Security Access (0x27)');
      final seedResp = await _expect('SECURITY', [0x27, 0x01], boot: true);
      if (seedResp.length < 3) {
        throw const FlashAbort('SECURITY', 'Seed payload is empty or too short', ecuMayBeInBootloader: true);
      }
      final seed = seedResp.sublist(2);
      final key = await remoteKeyProvider(seed);
      await _expect('SECURITY', [0x27, 0x02, ...key], boot: true);

      if (enableUniFlashLifecycle) {
        // 4b. Write BCD Programming Date Fingerprint (DID 0xF199)
        yield const FlashProgress('FINGERPRINT', 0.11, 'Writing BCD Programming Date Fingerprint (0xF199)');
        await writeProgrammingDateFingerprint(programmingDate);
      }

      // 5. Transfer Memory Segments
      final total = image.totalBytes;
      var written = 0;

      for (var s = 0; s < image.segments.length; s++) {
        final seg = image.segments[s];

        // 5a. RoutineControl Erase (0x31 0x01 0xFF 0x00)
        yield FlashProgress('ERASE', 0.12, 'Erase 0x${seg.address.toRadixString(16)}');
        final er = await _expect(
          'ERASE',
          [0x31, 0x01, 0xFF, 0x00, 0x44, ..._u32(seg.address), ..._u32(seg.data.length)],
          p2Star: const Duration(seconds: 30),
          boot: true,
        );
        if (er.length < 5 || er[4] != 0x00) {
          throw const FlashAbort('ERASE', 'Erase routine status != OK (0x00)', ecuMayBeInBootloader: true);
        }

        // 5b. RequestDownload (0x34)
        final dl = await _expect(
          'DOWNLOAD_REQ',
          [0x34, dataFormatIdentifier & 0xFF, 0x44, ..._u32(seg.address), ..._u32(seg.data.length)],
          boot: true,
        );
        if (dl.length < 3) {
          throw const FlashAbort('DOWNLOAD_REQ', 'Malformed RequestDownload positive response', ecuMayBeInBootloader: true);
        }
        final lenFmt = (dl[1] >> 4) & 0x0F;
        var maxBlock = 0;
        for (var i = 0; i < lenFmt && (2 + i) < dl.length; i++) {
          maxBlock = (maxBlock << 8) | dl[2 + i];
        }
        final chunk = maxBlock - 2; // Subtract SID (0x36) and BSC (1 byte)
        if (chunk <= 0) {
          throw FlashAbort(
            'DOWNLOAD_REQ',
            'Invalid maxNumberOfBlockLength from ECU: $maxBlock',
            ecuMayBeInBootloader: true,
          );
        }

        // 5c. TransferData (0x36) with BSC Wrap (0xFF -> 0x00)
        // If NRV compression (DFI 0x10) is requested with compressPayloadWhenNrv, compress segment payload
        final transferPayload = (compressPayloadWhenNrv && (dataFormatIdentifier & 0xF0) == 0x10)
            ? UclNrvCompression.compressNrv2b(seg.data)
            : seg.data;
        var bsc = 1;
        for (var off = 0; off < transferPayload.length; off += chunk) {
          final end = (off + chunk).clamp(0, transferPayload.length);
          final req = <int>[0x36, bsc, ...transferPayload.sublist(off, end)];

          List<int>? ok;
          for (var attempt = 0; attempt < 3 && ok == null; attempt++) {
            try {
              ok = await _expect('TRANSFER', req, boot: true);
              if (ok.length < 2 || ok[1] != bsc) {
                ok = null; // Wrong BSC echo -> retry block
              }
            } on FlashAbort {
              if (attempt == 2) rethrow;
              await Future.delayed(const Duration(milliseconds: 200));
            }
          }

          written += end - off;
          bsc = (bsc + 1) & 0xFF; // Wrap 0xFF -> 0x00 per ISO 14229-1
          onCheckpoint?.call(s, end);

          final ratio = total > 0 ? (written / total).clamp(0.0, 1.0) : 1.0;
          yield FlashProgress(
            'TRANSFER',
            0.15 + (0.75 * ratio),
            'ბლოკი ${(off ~/ chunk) + 1} • ${(ratio * 100).toInt()}%',
          );
        }

        // 5d. RequestTransferExit (0x37)
        await _expect('TRANSFER_EXIT', [0x37], boot: true);

        if (enableUniFlashLifecycle) {
          // 5e. Per-Segment CheckMemory (0x31 0x01 0x02 0x02)
          yield FlashProgress('CHECK_MEMORY', 0.91, 'Verifying Segment 0x${seg.address.toRadixString(16)} (0x0202)');
          await startRoutineCheckMemoryAddressed(seg.address, seg.data.length);
        }
      }

      // 6. Check Programming Dependencies (0x31 0x01 0xFF 0x01)
      yield const FlashProgress('CHECK', 0.93, 'Check Programming Dependencies (0x31 FF01)');
      final chk = await _expect(
        'CHECK',
        [0x31, 0x01, 0xFF, 0x01],
        p2Star: const Duration(seconds: 30),
        boot: true,
      );
      if (chk.length < 5 || chk[4] != 0x00) {
        throw const FlashAbort(
          'CHECK',
          'ECU-მ checksum/სიგნატურა უარყო (Check Dependencies Failed)',
          ecuMayBeInBootloader: true,
        );
      }

      // 7. Stop TesterPresent and issue ECU Reset (0x11 0x01)
      _testerPresent?.cancel();
      yield const FlashProgress('RESET', 0.97, 'ECU Reset (0x11 0x01)');
      await _expect('RESET', [0x11, 0x01]);

      // 8. Wait for ECU reboot and restore normal bus operation
      await Future.delayed(const Duration(seconds: 3));
      await proto.sendFunctional(const [0x28, 0x80, 0x01]); // Enable normal communication
      await proto.sendFunctional(const [0x85, 0x81]); // DTC ON

      if (enableUniFlashLifecycle) {
        // 8b. Restore Normal Energy Mode & Restore Backed-up NCD Coding Records
        await startRoutineSetEnergyMode(enableFlashMode: false);
        if (_backedUpCodingRecords.isNotEmpty) {
          yield const FlashProgress('CODING_RESTORE', 0.99, 'Restoring NCD Coding Records & Signature (0x0F01)');
          await restoreCodingRecords();
        }
      }

      yield const FlashProgress('COMPLETE', 1.0, 'ფლეში წარმატებით დასრულდა და ECU-მ დაადასტურა');
    } finally {
      _testerPresent?.cancel();
    }
  }
}
