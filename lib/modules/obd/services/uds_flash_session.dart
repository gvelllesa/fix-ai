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

  UdsFlashSession({
    required this.proto,
    this.ecu = 0x12, // Default: BMW DME/DDE
    required this.remoteKeyProvider,
    this.onCheckpoint,
  });

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
  Stream<FlashProgress> run(
    VerifiedFlashImage image, {
    @visibleForTesting bool allowExecutionInTest = false,
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
          [0x34, 0x00, 0x44, ..._u32(seg.address), ..._u32(seg.data.length)],
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
        var bsc = 1;
        for (var off = 0; off < seg.data.length; off += chunk) {
          final end = (off + chunk).clamp(0, seg.data.length);
          final req = <int>[0x36, bsc, ...seg.data.sublist(off, end)];

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

          final ratio = total > 0 ? (written / total) : 1.0;
          yield FlashProgress(
            'TRANSFER',
            0.15 + (0.75 * ratio),
            'ბლოკი ${(off ~/ chunk) + 1} • ${(ratio * 100).toInt()}%',
          );
        }

        // 5d. RequestTransferExit (0x37)
        await _expect('TRANSFER_EXIT', [0x37], boot: true);
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

      yield const FlashProgress('COMPLETE', 1.0, 'ფლეში წარმატებით დასრულდა და ECU-მ დაადასტურა');
    } finally {
      _testerPresent?.cancel();
    }
  }
}
