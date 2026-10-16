import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/models/engine_safety_envelope.dart';
import 'package:ai_car_diagnostics/modules/obd/models/verified_flash_image.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_options.dart';

void main() {
  group('P1.5 - VerifiedFlashImage Integrity & Signatures', () {
    late SimpleKeyPair testKeyPair;
    late Uint8List testPublicKeyBytes;

    setUpAll(() async {
      final ed25519 = Ed25519();
      testKeyPair = await ed25519.newKeyPair();
      final pubKey = await testKeyPair.extractPublicKey();
      testPublicKeyBytes = Uint8List.fromList(pubKey.bytes);
    });

    test('Valid container unpacks and verifies successfully', () async {
      final segment1Data = Uint8List.fromList(List.generate(128, (i) => i & 0xFF));
      final segment2Data = Uint8List.fromList(List.generate(256, (i) => (255 - i) & 0xFF));
      final payload = Uint8List.fromList([...segment1Data, ...segment2Data]);

      final sha = await Sha256().hash(payload);
      final shaHex = sha.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final manifest = FlashManifest(
        licensedVin: 'WBA3A5C50DF123456',
        btld: 'BTLD_00001234_001_002',
        swfl: 'SWFL_00005678_003_004',
        engineCode: 'B58B30M0',
        stage: 'Stage 1 93 Oct',
        payloadSha256: shaHex,
        segments: [
          {'address': 0x80010000, 'length': 128},
          {'address': 0x80020000, 'length': 256},
        ],
        createdAtEpoch: 1776340000,
      );

      final container = await VerifiedFlashImage.packContainer(
        manifest: manifest,
        payload: payload,
        privateKeyPair: testKeyPair,
      );

      final unpacked = await VerifiedFlashImage.unpackAndVerify(
        container,
        verificationPublicKey: testPublicKeyBytes,
      );

      expect(unpacked.licensedVin, equals('WBA3A5C50DF123456'));
      expect(unpacked.sha256Hex, equals(shaHex));
      expect(unpacked.segments.length, equals(2));
      expect(unpacked.segments[0].address, equals(0x80010000));
      expect(unpacked.segments[0].data.length, equals(128));
      expect(unpacked.segments[1].address, equals(0x80020000));
      expect(unpacked.segments[1].data.length, equals(256));
    });

    test('Corrupted Ed25519 signature throws FormatException', () async {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final sha = await Sha256().hash(payload);
      final shaHex = sha.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final manifest = FlashManifest(
        licensedVin: 'WBA3A5C50DF123456',
        engineCode: 'N55',
        stage: 'Stage 1',
        payloadSha256: shaHex,
        segments: [
          {'address': 0x80010000, 'length': 8},
        ],
        createdAtEpoch: 1776340000,
      );

      final container = await VerifiedFlashImage.packContainer(
        manifest: manifest,
        payload: payload,
        privateKeyPair: testKeyPair,
      );

      // Flip 1 byte in the signature (last 64 bytes)
      container[container.length - 5] ^= 0xFF;

      expect(
        () => VerifiedFlashImage.unpackAndVerify(
          container,
          verificationPublicKey: testPublicKeyBytes,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('Tampered payload SHA-256 mismatch throws FormatException', () async {
      final payload = Uint8List.fromList([10, 20, 30, 40, 50]);
      final sha = await Sha256().hash(payload);
      final shaHex = sha.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final manifest = FlashManifest(
        licensedVin: 'WBA3A5C50DF123456',
        engineCode: 'N55',
        stage: 'Stage 1',
        payloadSha256: shaHex,
        segments: [
          {'address': 0x80010000, 'length': 5},
        ],
        createdAtEpoch: 1776340000,
      );

      // Pack container with correct payload
      final container = await VerifiedFlashImage.packContainer(
        manifest: manifest,
        payload: payload,
        privateKeyPair: testKeyPair,
      );

      // Modify payload byte without updating signature/manifest
      final manifestLen = ByteData.sublistView(container).getUint32(0, Endian.big);
      container[4 + manifestLen] = 99; // Corrupt payload byte

      // Signature verification fails first on tampered bytes
      expect(
        () => VerifiedFlashImage.unpackAndVerify(
          container,
          verificationPublicKey: testPublicKeyBytes,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('Segment address exceeding DME memory boundaries throws FormatException', () async {
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      final sha = await Sha256().hash(payload);
      final shaHex = sha.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Invalid segment address outside Tricore / ARM Flash
      final manifest = FlashManifest(
        licensedVin: 'WBA3A5C50DF123456',
        engineCode: 'N55',
        stage: 'Stage 1',
        payloadSha256: shaHex,
        segments: [
          {'address': 0x90000000, 'length': 4}, // Out of bounds!
        ],
        createdAtEpoch: 1776340000,
      );

      final container = await VerifiedFlashImage.packContainer(
        manifest: manifest,
        payload: payload,
        privateKeyPair: testKeyPair,
      );

      expect(
        () => VerifiedFlashImage.unpackAndVerify(
          container,
          verificationPublicKey: testPublicKeyBytes,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('P1.5 - EngineSafetyEnvelope Threshold Enforcement', () {
    test('N55 with boost over 22.5 PSI throws ArgumentError', () {
      final envelope = EngineSafetyEnvelope.forEngine('BMW N55B30');
      expect(envelope.maxBoostPsi, equals(22.5));

      final dangerousOptions = BmwFlashOptions(
        antiLag: RollingAntiLagConfig(
          enabled: true,
          boostTargetPsi: 30.0, // Dangerous: 30 PSI on N55 cast pistons!
        ),
      );

      expect(
        () => envelope.assertSafetyCompliance(dangerousOptions),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('N55 with excessive boost-by-gear limit throws ArgumentError', () {
      final envelope = EngineSafetyEnvelope.forEngine('N55');
      final dangerousOptions = BmwFlashOptions(
        boostByGear: BoostByGearConfig(
          enabled: true,
          gearLimitsPsi: [15.0, 18.0, 26.0, 22.0, 22.0, 22.0, 22.0, 22.0], // 3rd gear 26 > 22.5
        ),
      );

      expect(
        () => envelope.assertSafetyCompliance(dangerousOptions),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('B58 valid Stage 1 calibration passes envelope check', () {
      final envelope = EngineSafetyEnvelope.forEngine('B58B30O1');
      expect(envelope.maxBoostPsi, equals(25.0));

      final safeOptions = BmwFlashOptions(
        antiLag: RollingAntiLagConfig(
          enabled: true,
          boostTargetPsi: 20.0,
          ignitionRetardDeg: 12.0,
          maxDurationSeconds: 3,
        ),
        boostByGear: BoostByGearConfig(
          enabled: true,
          gearLimitsPsi: [16.0, 18.0, 22.0, 23.0, 23.0, 23.0, 23.0, 23.0],
        ),
      );

      // Must not throw
      expect(() => envelope.assertSafetyCompliance(safeOptions), returnsNormally);
    });

    test('Unknown engine architecture throws UnsupportedError', () {
      expect(
        () => EngineSafetyEnvelope.forEngine('M54B30'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('P1.5 - BmwFlashOptions PIN & Serialization Safety', () {
    test('Anti-Theft PIN validation rejects weak or default PINs', () {
      expect(BmwFlashOptions.isValidPin(null), isFalse);
      expect(BmwFlashOptions.isValidPin([]), isFalse);
      expect(BmwFlashOptions.isValidPin([1, 2, 3]), isFalse); // < 4 digits
      expect(BmwFlashOptions.isValidPin([1, 2, 3, 4]), isFalse); // Default 1234
      expect(BmwFlashOptions.isValidPin([0, 0, 0, 0]), isFalse); // All identical
      expect(BmwFlashOptions.isValidPin([7, 7, 7, 7]), isFalse); // All identical
      expect(BmwFlashOptions.isValidPin([1, 9, 8, 4]), isTrue); // Valid
      expect(BmwFlashOptions.isValidPin([4, 2, 1, 3]), isTrue); // Valid
    });

    test('Enabling Anti-Theft with invalid PIN throws ArgumentError on serialization', () {
      final optionsWithDefaultPin = BmwFlashOptions(
        antiTheftEnabled: true,
        antiTheftPin: [1, 2, 3, 4], // Weak
      );

      expect(
        () => optionsWithDefaultPin.serializeCustomRomBinaryTable(),
        throwsA(isA<ArgumentError>()),
      );

      final optionsWithEmptyPin = BmwFlashOptions(
        antiTheftEnabled: true,
        antiTheftPin: [],
      );

      expect(
        () => optionsWithEmptyPin.serializeCustomRomBinaryTable(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Enabling Anti-Theft with valid PIN serializes cleanly', () {
      final validOptions = BmwFlashOptions(
        antiTheftEnabled: true,
        antiTheftPin: [8, 3, 1, 7],
      );

      final bytes = validOptions.serializeCustomRomBinaryTable();
      expect(bytes.length, equals(103));
      // Byte 82 is antiTheftEnabled, followed by 4 pin digits
      expect(bytes[82], equals(0x01));
      expect(bytes[83], equals(8));
      expect(bytes[84], equals(3));
      expect(bytes[85], equals(1));
      expect(bytes[86], equals(7));
    });

    test('CRC32 round-trip verification', () {
      final options = BmwFlashOptions();
      final tableWithCrc = options.serializeWithCrc();

      expect(tableWithCrc.length, equals(103 + 4));
      expect(BmwFlashOptions.verifyCrc(tableWithCrc), isTrue);

      // Corrupt a single byte in the payload
      tableWithCrc[10] ^= 0x55;
      expect(BmwFlashOptions.verifyCrc(tableWithCrc), isFalse);
    });
  });
}
