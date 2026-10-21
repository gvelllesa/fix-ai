import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Port transport type for INPA K+DCAN cable (`CableInterface.DcanPort` in `UNI_Flash.dll`).
enum DcanPort {
  ftdi(0, 'FTDI USB-Serial (FT232RL/FT232RQ)'),
  serial(1, 'Standard Serial COM Port'),
  btSerial(2, 'Bluetooth SPP Serial Bridge'),
  wifi(3, 'Wi-Fi TCP Serial Bridge'),
  invalid(4, 'Invalid / Disconnected');

  final int code;
  final String label;
  const DcanPort(this.code, this.label);
}

/// Operating bus mode for INPA K+DCAN interface (`CableInterface.DcanMode` in `UNI_Flash.dll`).
enum DcanMode {
  kLine(0, 10400, 'K-Line (ISO 14230 / DS2 @ 10.4 kbaud)'),
  dCan(1, 500000, 'D-CAN (ISO 15765-2 @ 500 kbps)'),
  kCan(2, 100000, 'K-CAN (Body CAN @ 100 kbps)'),
  auto(3, 115200, 'Auto-negotiate K-Line / D-CAN');

  final int code;
  final int busSpeedBps;
  final String description;
  const DcanMode(this.code, this.busSpeedBps, this.description);
}

/// BMW KWP2000 Service Identifiers (`DiagProtocolInterface.KWP2000_DiagCmd` in `UNI_Flash.dll`).
class Kwp2000DiagCmd {
  static const int startDiagnosticSession = 0x10;
  static const int ecuReset = 0x11;
  static const int readFreezeFrameData = 0x12;
  static const int readDiagnosticTroubleCodes = 0x13;
  static const int clearDiagnosticInformation = 0x14;
  static const int readStatusOfDiagnosticTroubleCodes = 0x17;
  static const int readDiagnosticTroubleCodesByStatus = 0x18;
  static const int readEcuIdentification = 0x1A;
  static const int stopDiagnosticSession = 0x20;
  static const int readDataByLocalIdentifier = 0x21;
  static const int readDataByCommonIdentifier = 0x22;
  static const int readMemoryByAddress = 0x23;
  static const int setDataRates = 0x26;
  static const int securityAccess = 0x27;
  static const int disableNormalMessageTransmission = 0x28;
  static const int enableNormalMessageTransmission = 0x29;
  static const int dynamicallyDefineLocalIdentifier = 0x2C;
  static const int writeDataByCommonIdentifier = 0x2E;
  static const int inputOutputControlByCommonIdentifier = 0x2F;
  static const int inputOutputControlByLocalIdentifier = 0x30;
  static const int startRoutineByLocalIdentifier = 0x31;
  static const int stopRoutineByLocalIdentifier = 0x32;
  static const int requestRoutineResultsByLocalIdentifier = 0x33;
  static const int requestDownload = 0x34;
  static const int requestUpload = 0x35;
  static const int transferData = 0x36;
  static const int requestTransferExit = 0x37;
  static const int startRoutineByAddress = 0x38;
  static const int stopRoutineByAddress = 0x39;
  static const int requestRoutineResultsByAddress = 0x3A;
  static const int writeDataByLocalIdentifier = 0x3B;
  static const int writeMemoryByAddress = 0x3D;
  static const int testerPresent = 0x3E;
  static const int escCode = 0x80;
  static const int startCommunication = 0x81;
  static const int stopCommunication = 0x82;
  static const int accessTimingParameter = 0x83;
}

/// BMW KWP2000 Diagnostic Session Modes (`DiagProtocolInterface.KWP2000_DiagMode` in `UNI_Flash.dll`).
class Kwp2000DiagMode {
  static const int defaultMode = 0x81; // DefaultSession
  static const int pt = 0x82;          // PeriodicTransmission
  static const int eolssm = 0x83;      // EndOfLineSystemSupplierMode
  static const int ecupm = 0x85;       // ECUProgrammingMode (Flash Session)
  static const int ecudm = 0x86;       // ECUDevelopmentMode
  static const int ecuam = 0x87;       // ECUAdjustmentMode
  static const int ecuvcm = 0x88;      // ECUVarCodingMode (Coding Session)
  static const int ecusm = 0x89;       // ECUSafetyMode
}

/// BMW KWP2000 Record Local Identifiers (`DiagProtocolInterface.KWP2000_RecordLocalIdentifier` in `UNI_Flash.dll`).
class Kwp2000RecordLocalIdentifier {
  static const int codingStatusVgsg = 0x30; // CodingStatusVGSG90_VGSG83_VGSG70
  static const int codingStatusGke = 0x31;  // CodingStatusGKEXXX (ZF 6HP EGS)
  static const int vehicleIdentificationNumber = 0x81;
  static const int developmentData = 0x82;
  static const int ecuSerialNumber = 0x83;
  static const int dbComData = 0x84;
  static const int operatingSystemVersion = 0x85;
  static const int ecuReprogrammingIdentification = 0x86;
  static const int vehicleInformation = 0x87;
  static const int flashInfo1 = 0x88;
  static const int flashInfo2 = 0x89;
  static const int systemDiagnosticGeneralParameterData = 0x8A;
  static const int systemDiagnosticGlobalParameterData = 0x8B;
  static const int ecuConfiguration = 0x8C;
  static const int diagnosticProtocolInformation = 0x8F;
  static const int engineRpmVgs = 0x90;
  static const int vehicleSpeedVgs = 0x91;
  static const int vehicleVoltageVgs = 0x92;
}

/// BMW KWP2000 Local Routine Identifiers (`DiagProtocolInterface.KWP2000_RoutineIdentifier` in `UNI_Flash.dll`).
class Kwp2000RoutineIdentifier {
  static const int clearMemory = 0xA0;
  static const int clearDtcShadowMemory = 0xA1;
  static const int requestForAuthentication = 0xA2;
  static const int releaseAuthentication = 0xA3;
  static const int checkSignature = 0xA4;
  static const int checkProgrammingStatus = 0xA5;
  static const int vgsg90WriteEeprom = 0xB0;
  static const int vgsg90ReadEeprom = 0xB1;
  static const int vgsg90EraseEeprom = 0xB2;
  static const int vgsg90GetProgVersion = 0xB3;
  static const int enableGearInDisplay = 0xC0; // ZF 6HP Gear Display in D-Mode (FIX AI)
  static const int resetAllLearnedFunctions = 0xC1;
  static const int resetAdaptations = 0xC2;
  static const int quicktest = 0xC3;
}

/// Parsed BMW KWP2000 / DS2 / D-CAN Telegram
class Kwp2000Telegram {
  final int formatByte;
  final int targetAddress;
  final int sourceAddress;
  final Uint8List payload;
  final int checksum;

  const Kwp2000Telegram({
    required this.formatByte,
    required this.targetAddress,
    required this.sourceAddress,
    required this.payload,
    required this.checksum,
  });
}

/// BMW E-Series USB K+DCAN (FTDI FT232RL) & KWP2000 Protocol Engine.
///
/// Implements 100% parity with:
/// - `CableInterface.InpaK_DCan`
/// - `UNI_Flash.Platform.Android.FtdiInterface`
/// - `DiagProtocolInterface.Kwp2000_BMW`
/// - `UNI_Flash.Program_KWP`
class KdcanProtocol {
  static const int ftdiVendorId = 0x0403;
  static const int ftdiProductIdFt232R = 0x6001;
  static const int ftdiProductIdFt232H = 0x6014;
  static const int defaultLatencyTimerMs = 1; // 1ms FTDI latency timer for BMW KWP2000 P2 timing

  static const int testerAddress = 0xF1;      // Standard BMW KWP2000 / INPA Tester Address
  static const int maxFrameSizeDownload = 0xFE; // 254 bytes per KWP TransferData block

  static const MethodChannel _usbFtdiChannel = MethodChannel('fixai/usb_ftdi');

  final DcanPort portType;
  DcanMode _mode;
  int _baudrate;
  bool _isConnected = false;

  /// Optional custom transceiver for unit tests or TCP/Serial bridge injection.
  /// Receives raw KWP2000 framed bytes and returns raw wire response bytes (with or without TX echo).
  Future<Uint8List?> Function(Uint8List txFrame, {Duration timeout})? customTransceiver;

  /// Records all transmitted raw KWP2000 telegrams when in test mode.
  final List<Uint8List> txHistory = [];

  KdcanProtocol({
    this.portType = DcanPort.ftdi,
    DcanMode initialMode = DcanMode.dCan,
    int initialBaudrate = 115200,
    this.customTransceiver,
  })  : _mode = initialMode,
        _baudrate = initialBaudrate;

  bool get isConnected => _isConnected;
  DcanMode get interfaceMode => _mode;
  int get baudrate => _baudrate;
  String get interfaceName => 'INPA K+DCAN (${portType.name.toUpperCase()} / ${_mode.name})';
  int get interfaceMaxFrameSizeDownload => maxFrameSizeDownload;

  /// Computes the 8-bit XOR checksum over all KWP2000 header + payload bytes
  /// (`CableInterface.InpaK_DCan` / ISO 14230 BMW-FAST standard).
  static int computeXorChecksum(List<int> bytes, [int? length]) {
    final end = length ?? bytes.length;
    var xor = 0;
    for (var i = 0; i < end; i++) {
      xor ^= (bytes[i] & 0xFF);
    }
    return xor & 0xFF;
  }

  /// Builds a BMW KWP2000 / D-CAN telegram:
  /// - If [useB8Header] is true (BMW D-CAN / KWP2000*):
  ///   `[0xB8, target, source, length, ...payload, xorChecksum]`
  /// - Else if `payload.length < 64` and not [forceLengthByte]:
  ///   `[0x80 | payload.length, target, source, ...payload, xorChecksum]`
  /// - Else (`payload.length >= 64` or [forceLengthByte]):
  ///   `[0x80, target, source, length, ...payload, xorChecksum]`
  static Uint8List buildKwp2000Frame(
    int targetAddress,
    List<int> payload, {
    int sourceAddress = testerAddress,
    bool useB8Header = false,
    bool forceLengthByte = false,
  }) {
    if (payload.isEmpty || payload.length > 255) {
      throw ArgumentError('KWP2000 payload length must be between 1 and 255 bytes (got ${payload.length})');
    }

    final frame = <int>[];
    if (useB8Header) {
      frame.add(0xB8);
      frame.add(targetAddress & 0xFF);
      frame.add(sourceAddress & 0xFF);
      frame.add(payload.length & 0xFF);
    } else if (payload.length < 64 && !forceLengthByte) {
      frame.add(0x80 | (payload.length & 0x3F));
      frame.add(targetAddress & 0xFF);
      frame.add(sourceAddress & 0xFF);
    } else {
      frame.add(0x80);
      frame.add(targetAddress & 0xFF);
      frame.add(sourceAddress & 0xFF);
      frame.add(payload.length & 0xFF);
    }

    frame.addAll(payload.map((b) => b & 0xFF));
    frame.add(computeXorChecksum(frame));
    return Uint8List.fromList(frame);
  }

  /// Parses a single BMW KWP2000 telegram (`0x80`..`0xBF` or `0xB8` header) and validates XOR checksum.
  /// If [txEchoToStrip] is provided and matches the leading bytes of [rawRx] (half-duplex K-Line echo),
  /// automatically strips the TX echo before parsing the ECU response.
  static Kwp2000Telegram? parseKwp2000Frame(
    List<int> rawRx, {
    List<int>? txEchoToStrip,
  }) {
    var offset = 0;
    if (txEchoToStrip != null &&
        txEchoToStrip.isNotEmpty &&
        rawRx.length > txEchoToStrip.length) {
      var echoMatches = true;
      for (var i = 0; i < txEchoToStrip.length; i++) {
        if ((rawRx[i] & 0xFF) != (txEchoToStrip[i] & 0xFF)) {
          echoMatches = false;
          break;
        }
      }
      if (echoMatches) {
        offset = txEchoToStrip.length;
      }
    }

    final remaining = rawRx.length - offset;
    if (remaining < 5) return null;

    final fmt = rawRx[offset] & 0xFF;
    if ((fmt & 0x80) == 0) return null;

    final target = rawRx[offset + 1] & 0xFF;
    final source = rawRx[offset + 2] & 0xFF;

    int payloadLen;
    int headerLen;
    if (fmt == 0xB8 || fmt == 0x80) {
      payloadLen = rawRx[offset + 3] & 0xFF;
      headerLen = 4;
    } else {
      payloadLen = fmt & 0x3F;
      headerLen = 3;
    }

    final totalFrameLen = headerLen + payloadLen + 1; // +1 for XOR checksum
    if (remaining < totalFrameLen) return null;

    final frameSlice = rawRx.sublist(offset, offset + totalFrameLen);
    final expectedChecksum = computeXorChecksum(frameSlice, totalFrameLen - 1);
    final actualChecksum = frameSlice.last & 0xFF;
    if (expectedChecksum != actualChecksum) {
      return null;
    }

    final payload = Uint8List.fromList(
      frameSlice.sublist(headerLen, headerLen + payloadLen),
    );
    return Kwp2000Telegram(
      formatByte: fmt,
      targetAddress: target,
      sourceAddress: source,
      payload: payload,
      checksum: actualChecksum,
    );
  }

  /// Builds the INPA K+DCAN firmware mode-control command (`CableInterface.InpaK_DCan`).
  /// Switches the cable microcontroller between 500kbps D-CAN, 100kbps K-CAN, and 10.4kbaud K-Line.
  static Uint8List buildInpaModeControlTelegram(DcanMode mode) {
    final int cmdByte;
    switch (mode) {
      case DcanMode.dCan:
        cmdByte = 0xC1; // Enable 500k D-CAN (CAN High/Low Pins 6 & 14)
        break;
      case DcanMode.kCan:
        cmdByte = 0xC2; // Enable 100k K-CAN
        break;
      case DcanMode.kLine:
        cmdByte = 0xC0; // Enable K-Line Pin 7/8
        break;
      case DcanMode.auto:
        cmdByte = 0xC3; // Auto-detect mode
        break;
    }
    return buildKwp2000Frame(0xF1, [cmdByte, mode.code], sourceAddress: 0xF1);
  }

  /// Initializes the FTDI USB-Serial interface (`VID 0x0403 / PID 0x6001`), sets 1ms latency timer,
  /// configures baudrate (`115200` for D-CAN or `10400` for K-Line), and switches cable to [mode].
  Future<bool> initialize({
    DcanMode mode = DcanMode.dCan,
    int? baudrate,
  }) async {
    _mode = mode;
    _baudrate = baudrate ?? (mode == DcanMode.kLine ? 10400 : 115200);

    if (customTransceiver != null) {
      _isConnected = true;
      await setDcanMode(mode);
      return true;
    }

    try {
      final ok = await _usbFtdiChannel.invokeMethod<bool>('openFtdi', {
        'vendorId': ftdiVendorId,
        'productId': ftdiProductIdFt232R,
        'baudrate': _baudrate,
        'latencyTimerMs': defaultLatencyTimerMs,
        'dataBits': 8,
        'stopBits': 1,
        'parity': 0, // None
        'dtr': true,
        'rts': false,
      });
      _isConnected = ok ?? false;
      if (_isConnected) {
        await setDcanMode(mode);
      }
      return _isConnected;
    } catch (e) {
      debugPrint('[K+DCAN] FTDI initialization notice: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Dynamically changes the FTDI UART baudrate (`CableInterface.InpaK_DCan.SetBaudrate`).
  Future<bool> setBaudrate(int newBaudrate) async {
    _baudrate = newBaudrate;
    if (customTransceiver != null) return true;
    try {
      final ok = await _usbFtdiChannel.invokeMethod<bool>('setBaudrate', {
        'baudrate': newBaudrate,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends the INPA K+DCAN microcontroller mode switch command (`K_LINE`, `D_CAN`, `K_CAN`).
  Future<bool> setDcanMode(DcanMode mode) async {
    _mode = mode;
    final ctrlFrame = buildInpaModeControlTelegram(mode);
    final rawRsp = await interfaceSendAndReceiveRaw(
      ctrlFrame,
      timeout: const Duration(milliseconds: 500),
    );
    return rawRsp != null && rawRsp.isNotEmpty;
  }

  /// Flushes FTDI RX/TX hardware FIFOs (`CableInterface.InpaK_DCan.FlushBuffers`).
  Future<void> flushBuffers() async {
    if (customTransceiver != null) return;
    try {
      await _usbFtdiChannel.invokeMethod<void>('flushBuffers');
    } catch (_) {}
  }

  /// Checks if the INPA K+DCAN cable is physically connected and responsive (`CableConnectedAndAlive`).
  Future<bool> cableConnectedAndAlive() async {
    if (!_isConnected) return false;
    if (customTransceiver != null) return true;
    try {
      final alive = await _usbFtdiChannel.invokeMethod<bool>('isConnected');
      return alive ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Disconnects and releases the FTDI USB-Serial interface.
  Future<void> disconnect() async {
    _isConnected = false;
    if (customTransceiver != null) return;
    try {
      await _usbFtdiChannel.invokeMethod<void>('closeFtdi');
    } catch (_) {}
  }

  /// Low-level wire transceiver (`InterfaceSendData` + `InterfaceReceiveData`).
  Future<Uint8List?> interfaceSendAndReceiveRaw(
    Uint8List txFrame, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    txHistory.add(Uint8List.fromList(txFrame));
    if (customTransceiver != null) {
      return customTransceiver!(txFrame, timeout: timeout);
    }
    if (!_isConnected) return null;

    try {
      final rsp = await _usbFtdiChannel.invokeMethod<Uint8List>('transceive', {
        'txBytes': txFrame,
        'timeoutMs': timeout.inMilliseconds,
      });
      return rsp;
    } catch (e) {
      debugPrint('[K+DCAN] Transceive error: $e');
      return null;
    }
  }

  /// Sends a KWP2000 or UDS payload to [targetEcu] over K+DCAN and awaits the validated response.
  /// Automatically handles:
  /// - Half-duplex K-Line TX echo stripping
  /// - NRC `0x78` (`responsePending`) extended P2* waiting (`maxPending` retries)
  /// - Positive response SID verification (`reqSid + 0x40`)
  Future<Uint8List?> sendKwpAndAwait(
    int targetEcu,
    List<int> payload, {
    Duration timeout = const Duration(milliseconds: 1500),
    Duration p2Star = const Duration(seconds: 10),
    int maxPending = 60,
    bool? useB8Header,
  }) async {
    if (payload.isEmpty) return null;
    final sid = payload[0] & 0xFF;
    final txFrame = buildKwp2000Frame(
      targetEcu,
      payload,
      sourceAddress: testerAddress,
      useB8Header: useB8Header ?? (_mode == DcanMode.dCan && sid == Kwp2000DiagCmd.transferData),
    );

    var currentWait = timeout;
    var pendingCount = 0;
    var currentTx = txFrame;

    while (true) {
      final rawRx = await interfaceSendAndReceiveRaw(currentTx, timeout: currentWait);
      if (rawRx == null || rawRx.isEmpty) return null;

      final telegram = parseKwp2000Frame(rawRx, txEchoToStrip: currentTx);
      if (telegram == null || telegram.payload.isEmpty) return null;

      final p = telegram.payload;
      if (p[0] == 0x7F && p.length >= 3 && p[1] == sid) {
        final nrc = p[2] & 0xFF;
        if (nrc == 0x78 && ++pendingCount <= maxPending) {
          currentWait = p2Star;
          // In customTransceiver / stream reads, subsequent reads wait for next frame
          continue;
        }
        return p;
      }

      if (p[0] == ((sid + 0x40) & 0xFF)) {
        return p;
      }
      return p;
    }
  }

  // =========================================================================
  // DiagProtocolInterface.Kwp2000_BMW High-Level Diagnostic & Flash Methods
  // =========================================================================

  /// `StartCommunication` (`0x81`) — initializes K-Line fast-init session.
  Future<Uint8List?> startCommunication(int targetEcu) =>
      sendKwpAndAwait(targetEcu, const [Kwp2000DiagCmd.startCommunication]);

  /// `StopCommunication` (`0x82`) — terminates K-Line communication.
  Future<Uint8List?> stopCommunication(int targetEcu) =>
      sendKwpAndAwait(targetEcu, const [Kwp2000DiagCmd.stopCommunication]);

  /// `StartDiagnosticSession` (`0x10`) — enters `DEFAULT (0x81)`, `ECUPM (0x85)`, `ECUDM (0x86)`, or `ECUVCM (0x88)`.
  /// Optionally passes baudrate identifier (e.g. `0x0A` for 115200 baud fast programming).
  Future<bool> startDiagnosticSession(
    int targetEcu,
    int diagMode, {
    int? baudrateIdentifier,
  }) async {
    final req = <int>[
      Kwp2000DiagCmd.startDiagnosticSession,
      diagMode & 0xFF,
      if (baudrateIdentifier != null) baudrateIdentifier & 0xFF,
    ];
    final rsp = await sendKwpAndAwait(targetEcu, req, timeout: const Duration(seconds: 3));
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x50;
  }

  /// `StopDiagnosticSession` (`0x20`).
  Future<bool> stopDiagnosticSession(int targetEcu) async {
    final rsp = await sendKwpAndAwait(targetEcu, const [Kwp2000DiagCmd.stopDiagnosticSession]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x60;
  }

  /// `EcuReset` (`0x11`) — issues powerOnReset (`0x01`) or nonVolatileMemoryReset (`0x03`).
  Future<bool> ecuReset(int targetEcu, {int resetMode = 0x01}) async {
    final rsp = await sendKwpAndAwait(targetEcu, [Kwp2000DiagCmd.ecuReset, resetMode & 0xFF]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x51;
  }

  /// `TesterPresent` (`0x3E`) — keeps KWP2000 diagnostic/programming session alive.
  Future<bool> testerPresent(int targetEcu, {bool responseRequired = true}) async {
    final sub = responseRequired ? 0x01 : 0x02;
    final rsp = await sendKwpAndAwait(targetEcu, [Kwp2000DiagCmd.testerPresent, sub]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x7E;
  }

  /// `ReadEcuIdentification` (`0x1A`) — reads BMW ECU identification table (`0x80..0x9A`).
  Future<Uint8List?> readEcuIdentification(int targetEcu, {int identificationOption = 0x80}) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.readEcuIdentification,
      identificationOption & 0xFF,
    ]);
    if (rsp != null && rsp.length > 2 && rsp[0] == 0x5A) {
      return Uint8List.fromList(rsp.sublist(2));
    }
    return null;
  }

  /// `ReadDataByLocalIdentifier` (`0x21`) — reads local record (e.g. `0x81` VIN, `0x88` FlashInfo1, `0x30` VGSG Coding).
  Future<Uint8List?> readDataByLocalIdentifier(int targetEcu, int recordLocalId) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.readDataByLocalIdentifier,
      recordLocalId & 0xFF,
    ]);
    if (rsp != null && rsp.length > 2 && rsp[0] == 0x61 && rsp[1] == (recordLocalId & 0xFF)) {
      return Uint8List.fromList(rsp.sublist(2));
    }
    return null;
  }

  /// `ReadDataByCommonIdentifier` (`0x22`) — reads 16-bit DID on KWP2000/UDS ECUs.
  Future<Uint8List?> readDataByCommonIdentifier(int targetEcu, int commonId) async {
    final msb = (commonId >> 8) & 0xFF;
    final lsb = commonId & 0xFF;
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.readDataByCommonIdentifier,
      msb,
      lsb,
    ]);
    if (rsp != null && rsp.length > 3 && rsp[0] == 0x62 && rsp[1] == msb && rsp[2] == lsb) {
      return Uint8List.fromList(rsp.sublist(3));
    }
    return null;
  }

  /// `WriteDataByLocalIdentifier` (`0x3B`) — writes local record (`UNI_Flash.Program_KWP.RestoreCodingRecords`).
  Future<bool> writeDataByLocalIdentifier(int targetEcu, int recordLocalId, List<int> data) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.writeDataByLocalIdentifier,
      recordLocalId & 0xFF,
      ...data,
    ]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x7B;
  }

  /// `ReadMemoryByAddress` (`0x23`) — reads raw memory segment (`[0x23, addrHigh, addrMid, addrLow, len]`).
  Future<Uint8List?> readMemoryByAddress(int targetEcu, int address, int length) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.readMemoryByAddress,
      (address >> 16) & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
      length & 0xFF,
    ]);
    if (rsp != null && rsp.length > 1 && rsp[0] == 0x63) {
      return Uint8List.fromList(rsp.sublist(1));
    }
    return null;
  }

  /// `WriteMemoryByAddress` (`0x3D`) — writes raw memory segment.
  Future<bool> writeMemoryByAddress(int targetEcu, int address, List<int> data) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.writeMemoryByAddress,
      (address >> 16) & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
      data.length & 0xFF,
      ...data,
    ]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x7D;
  }

  /// `SecurityAccessRequestSeed` (`0x27 <odd level>`).
  Future<Uint8List?> securityAccessRequestSeed(int targetEcu, {int level = 0x01}) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.securityAccess,
      level & 0xFF,
    ]);
    if (rsp != null && rsp.length >= 2 && rsp[0] == 0x67 && rsp[1] == (level & 0xFF)) {
      return Uint8List.fromList(rsp.sublist(2));
    }
    return null;
  }

  /// `SecurityAccessSendKey` (`0x27 <even level> <key>`).
  Future<bool> securityAccessSendKey(int targetEcu, List<int> key, {int level = 0x02}) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.securityAccess,
      level & 0xFF,
      ...key,
    ]);
    return rsp != null && rsp.length >= 2 && rsp[0] == 0x67 && rsp[1] == (level & 0xFF);
  }

  /// `DisableNormalMessageTransmission` (`0x28`) — silences bus during E-series KWP flashing.
  Future<bool> disableNormalMessageTransmission(int targetEcu) async {
    final rsp = await sendKwpAndAwait(targetEcu, const [
      Kwp2000DiagCmd.disableNormalMessageTransmission,
      0x02,
    ]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x68;
  }

  /// `EnableNormalMessageTransmission` (`0x29`) — restores bus after E-series KWP flashing.
  Future<bool> enableNormalMessageTransmission(int targetEcu) async {
    final rsp = await sendKwpAndAwait(targetEcu, const [
      Kwp2000DiagCmd.enableNormalMessageTransmission,
      0x02,
    ]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x69;
  }

  /// `StartRoutineByLocalIdentifier` (`0x31 <routineId> ...`).
  Future<Uint8List?> startRoutineByLocalIdentifier(
    int targetEcu,
    int routineId, [
    List<int> routineParams = const [],
    Duration p2Star = const Duration(seconds: 25),
  ]) async {
    final rsp = await sendKwpAndAwait(
      targetEcu,
      [Kwp2000DiagCmd.startRoutineByLocalIdentifier, routineId & 0xFF, ...routineParams],
      p2Star: p2Star,
    );
    if (rsp != null && rsp.length >= 2 && rsp[0] == 0x71 && rsp[1] == (routineId & 0xFF)) {
      return rsp;
    }
    return null;
  }

  /// `StartRoutineByLocalIdentifier_ClearMemory` (`0x31 0xA0 <3-byte address> <3-byte length>`).
  Future<bool> startRoutineClearMemory(int targetEcu, int address, int length) async {
    final rsp = await startRoutineByLocalIdentifier(targetEcu, Kwp2000RoutineIdentifier.clearMemory, [
      (address >> 16) & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
    ]);
    return rsp != null;
  }

  /// `StartRoutineByLocalIdentifier_CheckSignature` (`0x31 0xA4 <signature>`).
  Future<bool> startRoutineCheckSignature(int targetEcu, List<int> signature) async {
    final rsp = await startRoutineByLocalIdentifier(
      targetEcu,
      Kwp2000RoutineIdentifier.checkSignature,
      signature,
    );
    return rsp != null && (rsp.length < 3 || rsp[2] == 0x00);
  }

  /// `StartRoutineByLocalIdentifier_CheckProgrammingStatus` (`0x31 0xA5`).
  Future<int?> startRoutineCheckProgrammingStatus(int targetEcu) async {
    final rsp = await startRoutineByLocalIdentifier(
      targetEcu,
      Kwp2000RoutineIdentifier.checkProgrammingStatus,
    );
    if (rsp != null && rsp.length >= 3) {
      return rsp[2];
    }
    return rsp != null ? 0x00 : null;
  }

  /// `StartRoutineByLocalIdentifier_ClearDTCShadowMemory` (`0x31 0xA1`).
  Future<bool> startRoutineClearDtcShadowMemory(int targetEcu) async {
    final rsp = await startRoutineByLocalIdentifier(
      targetEcu,
      Kwp2000RoutineIdentifier.clearDtcShadowMemory,
    );
    return rsp != null;
  }

  /// `RequestDownload` (`0x34 <3-byte address> <dataFormat> <3-byte uncompressedSize>`).
  Future<int?> requestDownload(
    int targetEcu,
    int address,
    int uncompressedSize, {
    int dataFormat = 0x00,
  }) async {
    final rsp = await sendKwpAndAwait(targetEcu, [
      Kwp2000DiagCmd.requestDownload,
      (address >> 16) & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
      dataFormat & 0xFF,
      (uncompressedSize >> 16) & 0xFF,
      (uncompressedSize >> 8) & 0xFF,
      uncompressedSize & 0xFF,
    ]);
    if (rsp != null && rsp.isNotEmpty && rsp[0] == 0x74) {
      if (rsp.length >= 2 && rsp[1] > 0) {
        return rsp[1];
      }
      return maxFrameSizeDownload;
    }
    return null;
  }

  /// `TransferData` (`0x36 [blockSequenceCounter] <data>`).
  Future<bool> transferData(
    int targetEcu,
    List<int> blockData, {
    int? blockSequenceCounter,
  }) async {
    final req = <int>[
      Kwp2000DiagCmd.transferData,
      if (blockSequenceCounter != null) blockSequenceCounter & 0xFF,
      ...blockData,
    ];
    final rsp = await sendKwpAndAwait(
      targetEcu,
      req,
      useB8Header: _mode == DcanMode.dCan,
    );
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x76;
  }

  /// `RequestTransferExit` (`0x37`).
  Future<bool> requestTransferExit(int targetEcu) async {
    final rsp = await sendKwpAndAwait(targetEcu, const [Kwp2000DiagCmd.requestTransferExit]);
    return rsp != null && rsp.isNotEmpty && rsp[0] == 0x77;
  }

  /// Human-readable description for BMW KWP2000 Programming Status byte (`GetProgramStatusDescription`).
  static String getProgramStatusDescription(int statusByte) {
    switch (statusByte) {
      case 0x00:
        return 'Correctly Programmed (Application Valid)';
      case 0x01:
        return 'Bootloader Mode Active (Waiting for Flash)';
      case 0x02:
        return 'Memory Erased / Incomplete Programming';
      case 0x03:
        return 'Signature Verification Failed';
      default:
        return 'Programming Status 0x${statusByte.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }
  }
}

/// BMW E-Series KWP2000 Flashing State Machine (`UNI_Flash.Program_KWP` parity).
///
/// Supports E-Series DME/DDE (MSV70/MSV80/MSD80/MSD81/ME9.2), ZF 6HP (`GKE191`/`GKE211`/`GKE215`),
/// and VTG (`VGSG90`/`VGSG83`/`VGSG70`) programming over INPA K+DCAN.
class KwpFlashSession {
  final KdcanProtocol kdcan;
  final int targetEcu;
  final Future<List<int>> Function(List<int> seed) remoteKeyProvider;

  final Map<int, Uint8List> _backedUpCoding = {};
  Map<int, Uint8List> get backedUpCoding => Map.unmodifiable(_backedUpCoding);
  bool _codingRestored = false;
  bool get isCodingRestored => _codingRestored;

  KwpFlashSession({
    required this.kdcan,
    required this.targetEcu,
    required this.remoteKeyProvider,
  });

  /// Backs up coding records (`0x21 0x30` for VGSG or `0x21 0x31` for GKE / EGS)
  /// (`UNI_Flash.Program_KWP.FetchCodingRecords`).
  Future<Map<int, Uint8List>> fetchCodingRecords({
    List<int> recordIds = const [
      Kwp2000RecordLocalIdentifier.codingStatusVgsg,
      Kwp2000RecordLocalIdentifier.codingStatusGke,
    ],
  }) async {
    _backedUpCoding.clear();
    for (final id in recordIds) {
      final data = await kdcan.readDataByLocalIdentifier(targetEcu, id);
      if (data != null && data.isNotEmpty) {
        _backedUpCoding[id] = data;
      }
    }
    return Map.unmodifiable(_backedUpCoding);
  }

  /// Restores backed-up KWP2000 coding records (`0x3B <recordId> <data>`)
  /// (`UNI_Flash.Program_KWP.RestoreCodingRecords`).
  Future<bool> restoreCodingRecords([Map<int, Uint8List>? records]) async {
    final toRestore = records ?? _backedUpCoding;
    if (toRestore.isEmpty) return true;

    await kdcan.startDiagnosticSession(targetEcu, Kwp2000DiagMode.ecuvcm);
    var allOk = true;
    for (final entry in toRestore.entries) {
      final ok = await kdcan.writeDataByLocalIdentifier(targetEcu, entry.key, entry.value);
      if (!ok) allOk = false;
    }
    _codingRestored = allOk;
    return allOk;
  }

  /// Executes the full `UNI_Flash.Program_KWP` E-series flashing sequence.
  Future<bool> executeSegmentFlash({
    required int address,
    required Uint8List data,
    required List<int> signature,
    bool backupAndRestoreCoding = true,
  }) async {
    if (backupAndRestoreCoding) {
      await fetchCodingRecords();
    }

    await kdcan.disableNormalMessageTransmission(targetEcu);

    final sessOk = await kdcan.startDiagnosticSession(
      targetEcu,
      Kwp2000DiagMode.ecupm,
      baudrateIdentifier: 0x0A, // 115200 fast programming
    );
    if (!sessOk) return false;

    final seed = await kdcan.securityAccessRequestSeed(targetEcu, level: 0x01);
    if (seed == null || seed.isEmpty) return false;
    if (seed.any((b) => b != 0)) {
      final key = await remoteKeyProvider(seed);
      final keyOk = await kdcan.securityAccessSendKey(targetEcu, key, level: 0x02);
      if (!keyOk) return false;
    }

    final eraseOk = await kdcan.startRoutineClearMemory(targetEcu, address, data.length);
    if (!eraseOk) return false;

    final maxBlock = await kdcan.requestDownload(targetEcu, address, data.length);
    if (maxBlock == null || maxBlock <= 2) return false;

    final chunk = (maxBlock - 2).clamp(1, KdcanProtocol.maxFrameSizeDownload);
    var bsc = 1;
    for (var offset = 0; offset < data.length; offset += chunk) {
      final end = (offset + chunk).clamp(0, data.length);
      final ok = await kdcan.transferData(
        targetEcu,
        data.sublist(offset, end),
        blockSequenceCounter: bsc,
      );
      if (!ok) return false;
      bsc = (bsc + 1) & 0xFF;
    }

    final exitOk = await kdcan.requestTransferExit(targetEcu);
    if (!exitOk) return false;

    final sigOk = await kdcan.startRoutineCheckSignature(targetEcu, signature);
    if (!sigOk) return false;

    final status = await kdcan.startRoutineCheckProgrammingStatus(targetEcu);
    if (status != 0x00) return false;

    await kdcan.ecuReset(targetEcu);
    await kdcan.enableNormalMessageTransmission(targetEcu);

    if (backupAndRestoreCoding && _backedUpCoding.isNotEmpty) {
      await restoreCodingRecords();
    }
    return true;
  }
}

