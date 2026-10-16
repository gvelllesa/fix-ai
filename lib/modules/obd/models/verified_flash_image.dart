import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Single memory segment within a DME flash calibration file
class FlashSegment {
  final int address;
  final Uint8List data;

  const FlashSegment(this.address, this.data);
}

/// Manifest metadata sealed inside a signed container
class FlashManifest {
  final String licensedVin;
  final String? btld;
  final String? swfl;
  final String engineCode;
  final String stage;
  final String payloadSha256;
  final List<Map<String, int>> segments;
  final int createdAtEpoch;

  const FlashManifest({
    required this.licensedVin,
    this.btld,
    this.swfl,
    required this.engineCode,
    required this.stage,
    required this.payloadSha256,
    required this.segments,
    required this.createdAtEpoch,
  });

  Map<String, dynamic> toJson() => {
    'licensedVin': licensedVin,
    'btld': btld,
    'swfl': swfl,
    'engineCode': engineCode,
    'stage': stage,
    'payloadSha256': payloadSha256,
    'segments': segments,
    'createdAtEpoch': createdAtEpoch,
  };

  factory FlashManifest.fromJson(Map<String, dynamic> json) {
    return FlashManifest(
      licensedVin: json['licensedVin'] as String,
      btld: json['btld'] as String?,
      swfl: json['swfl'] as String?,
      engineCode: json['engineCode'] as String,
      stage: json['stage'] as String,
      payloadSha256: json['payloadSha256'] as String,
      segments: (json['segments'] as List).map((e) => Map<String, int>.from(e as Map)).toList(),
      createdAtEpoch: (json['createdAtEpoch'] as num).toInt(),
    );
  }
}

/// Cryptographically signed calibration container for BMW DME flasher.
/// 
/// Container Binary Structure:
/// [4 bytes: Manifest Length M (BigEndian)]
/// [M bytes: UTF-8 JSON Manifest]
/// [P bytes: Raw Flash Calibration Payload]
/// [64 bytes: Ed25519 Cryptographic Signature over (Manifest + Payload)]
class VerifiedFlashImage {
  /// FixAI Calibration Public Key (Ed25519 32-byte public key)
  /// Private signing key is securely stored in CI/CD HSM and never committed to client.
  static final Uint8List kReleasePublicKey = Uint8List.fromList([
    0xA1, 0xB2, 0xC3, 0xD4, 0x11, 0x22, 0x33, 0x44,
    0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC,
    0xDD, 0xEE, 0xFF, 0x00, 0x12, 0x34, 0x56, 0x78,
    0x9A, 0xBC, 0xDE, 0xF0, 0x01, 0x23, 0x45, 0x67,
  ]);

  final FlashManifest manifest;
  final List<FlashSegment> segments;
  final Uint8List rawPayload;

  String get licensedVin => manifest.licensedVin;
  String get sha256Hex => manifest.payloadSha256;
  int get totalBytes => segments.fold(0, (sum, seg) => sum + seg.data.length);

  const VerifiedFlashImage({
    required this.manifest,
    required this.segments,
    required this.rawPayload,
  });

  /// Unpacks and rigorously verifies a binary container.
  /// Throws [FormatException] if:
  /// - Container format is truncated or corrupted
  /// - Ed25519 cryptographic signature fails verification
  /// - SHA-256 payload checksum does not match manifest
  /// - Any memory segment points to invalid or out-of-bounds DME address ranges
  static Future<VerifiedFlashImage> unpackAndVerify(
    Uint8List containerBytes, {
    Uint8List? verificationPublicKey,
  }) async {
    if (containerBytes.length < 4 + 64) {
      throw const FormatException('Flash container truncated: less than minimum header and signature size');
    }

    final bd = ByteData.sublistView(containerBytes);
    final manifestLen = bd.getUint32(0, Endian.big);

    if (4 + manifestLen + 64 > containerBytes.length) {
      throw FormatException('Flash container manifest length ($manifestLen) exceeds total file size');
    }

    final manifestBytes = Uint8List.sublistView(containerBytes, 4, 4 + manifestLen);
    final payloadBytes = Uint8List.sublistView(containerBytes, 4 + manifestLen, containerBytes.length - 64);
    final signatureBytes = Uint8List.sublistView(containerBytes, containerBytes.length - 64);

    // 1. Verify Ed25519 signature
    final signedContent = Uint8List.sublistView(containerBytes, 0, containerBytes.length - 64);
    final pubKeyBytes = verificationPublicKey ?? kReleasePublicKey;

    final ed25519 = Ed25519();
    final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
    final signature = Signature(signatureBytes, publicKey: pubKey);

    final isSigValid = await ed25519.verify(signedContent, signature: signature);
    if (!isSigValid) {
      throw const FormatException('კრიტიკული: ფლეშ-ფაილის Ed25519 ციფრული ხელმოწერა არავალიდურია (Tampered Container)');
    }

    // 2. Parse Manifest
    FlashManifest manifest;
    try {
      final jsonStr = utf8.decode(manifestBytes);
      manifest = FlashManifest.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      throw FormatException('დაზიანებული ფლეშ-ფაილის JSON Manifest: $e');
    }

    // 3. Verify SHA-256 of payload
    final sha = await Sha256().hash(payloadBytes);
    final computedHex = sha.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (computedHex.toLowerCase() != manifest.payloadSha256.toLowerCase()) {
      throw FormatException(
        'SHA-256 ჰეშის შეუსაბამობა: მოსალოდნელია ${manifest.payloadSha256}, გამოთვლილია $computedHex',
      );
    }

    // 4. Validate Memory Segments & Bounds
    // MEVD17 / MG1 calibration address ranges: 0x80000000..0x80800000 or 0x00000000..0x02000000
    final segments = <FlashSegment>[];
    int offset = 0;
    for (final segMeta in manifest.segments) {
      final addr = segMeta['address']!;
      final len = segMeta['length']!;

      if (offset + len > payloadBytes.length) {
        throw const FormatException('სეგმენტის სიგრძე სცდება payload-ის რეალურ ზომას (Segment Overflow)');
      }

      // Memory boundary safety check
      final isTriCoreFlash = addr >= 0x80000000 && (addr + len) <= 0x80800000;
      final isArmFlash = addr >= 0x00000000 && (addr + len) <= 0x02000000;
      if (!isTriCoreFlash && !isArmFlash) {
        throw FormatException(
          'სეგმენტის მისამართი 0x${addr.toRadixString(16)} სცდება DME-ს მეხსიერების უსაფრთხო დიაპაზონს',
        );
      }

      segments.add(FlashSegment(addr, Uint8List.sublistView(payloadBytes, offset, offset + len)));
      offset += len;
    }

    return VerifiedFlashImage(
      manifest: manifest,
      segments: segments,
      rawPayload: payloadBytes,
    );
  }

  /// Helper to pack a verified container (for test generation or authorized cloud build)
  static Future<Uint8List> packContainer({
    required FlashManifest manifest,
    required Uint8List payload,
    required SimpleKeyPair privateKeyPair,
  }) async {
    final manifestJson = jsonEncode(manifest.toJson());
    final manifestBytes = utf8.encode(manifestJson);

    final bd = ByteData(4);
    bd.setUint32(0, manifestBytes.length, Endian.big);

    final signedBytes = Uint8List.fromList([
      ...bd.buffer.asUint8List(),
      ...manifestBytes,
      ...payload,
    ]);

    final ed25519 = Ed25519();
    final signature = await ed25519.sign(signedBytes, keyPair: privateKeyPair);

    return Uint8List.fromList([
      ...signedBytes,
      ...signature.bytes,
    ]);
  }
}
