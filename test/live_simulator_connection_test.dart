import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';

Future<ServerSocket?> _ensureMockSimulatorOnPort(int port, {required bool isDoip}) async {
  // Check if an external simulator is already listening on 127.0.0.1:port
  try {
    final probe = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(milliseconds: 150),
    );
    await probe.close();
    return null; // External simulator already running
  } catch (_) {}

  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: true);
  server.listen((client) {
    final rx = <int>[];
    client.listen((chunk) {
      rx.addAll(chunk);
      if (isDoip) {
        while (rx.length >= 8) {
          final bd = ByteData.sublistView(Uint8List.fromList(rx));
          final payloadType = bd.getUint16(2, Endian.big);
          final len = bd.getUint32(4, Endian.big);
          if (rx.length < 8 + len) break;
          final payload = rx.sublist(8, 8 + len);
          rx.removeRange(0, 8 + len);

          if (payloadType == 0x0005) {
            // Routing Activation Response (0x0006): [testerSA 2B][entitySA 2B][0x10][4B reserved]
            final resp = <int>[
              0x02, 0xFD, 0x00, 0x06,
              0x00, 0x00, 0x00, 0x09,
              0x0E, 0xF4, 0x10, 0x10,
              0x10,
              0x00, 0x00, 0x00, 0x00,
            ];
            client.add(resp);
          } else if (payloadType == 0x8001 && payload.length >= 4) {
            final ta = payload[3];
            final uds = payload.sublist(4);
            final udsResp = _buildUdsResponse(uds);
            if (udsResp != null) {
              final bodyLen = 4 + udsResp.length;
              final header = ByteData(8);
              header.setUint8(0, 0x02);
              header.setUint8(1, 0xFD);
              header.setUint16(2, 0x8001, Endian.big);
              header.setUint32(4, bodyLen, Endian.big);
              client.add([
                ...header.buffer.asUint8List(),
                0x00, ta,
                0x0E, 0xF4,
                ...udsResp,
              ]);
            }
          }
        }
      } else {
        while (rx.length >= 6) {
          final bd = ByteData.sublistView(Uint8List.fromList(rx));
          final bodyLen = bd.getUint32(0, Endian.big);
          final msgType = bd.getUint16(4, Endian.big);
          if (rx.length < 6 + bodyLen) break;
          final body = rx.sublist(6, 6 + bodyLen);
          rx.removeRange(0, 6 + bodyLen);

          if (msgType == 0x0001 && body.length >= 2) {
            final src = body[0];
            final dst = body[1];
            final uds = body.sublist(2);
            final udsResp = _buildUdsResponse(uds);
            if (udsResp != null) {
              final outLen = 2 + udsResp.length;
              final header = ByteData(6);
              header.setUint32(0, outLen, Endian.big);
              header.setUint16(4, 0x0001, Endian.big);
              client.add([
                ...header.buffer.asUint8List(),
                dst,
                src,
                ...udsResp,
              ]);
            }
          }
        }
      }
    });
  });
  return server;
}

List<int>? _buildUdsResponse(List<int> uds) {
  if (uds.length >= 3 && uds[0] == 0x22 && uds[1] == 0xF1 && uds[2] == 0x90) {
    return [0x62, 0xF1, 0x90, ...'WBA3A5C50DF123456'.codeUnits];
  }
  if (uds.length >= 3 && uds[0] == 0x19 && uds[1] == 0x02) {
    // 0x59 0x02 <statusMask> <DTC 3B> <status 1B>
    return [0x59, 0x02, 0xFF, 0x12, 0x04, 0x08, 0x2F];
  }
  return null;
}

void main() {
  test('EnetHsfzProtocol connects and reads VIN from local or LAN IP', () async {
    final startedServers = <ServerSocket>[];
    addTearDown(() async {
      for (final s in startedServers) {
        await s.close();
      }
    });

    for (final port in [35000, 6801, 13400]) {
      final server = await _ensureMockSimulatorOnPort(port, isDoip: port == 13400);
      if (server != null) startedServers.add(server);

      final protocol = EnetHsfzProtocol();
      var connected = await protocol.connect(
        host: '127.0.0.1',
        port: port,
        useDoip: port == 13400,
      );
      if (!connected) {
        connected = await protocol.connect(
          host: '192.168.1.10',
          port: port,
          useDoip: port == 13400,
        );
      }
      expect(connected, isTrue, reason: 'Must connect to port $port on LAN');

      final vin = await protocol.readVin(0x12);
      expect(vin, equals('WBA3A5C50DF123456'), reason: 'Port $port must return BMW VIN');

      final dtcs = await protocol.readDtcCodes(0x12);
      expect(dtcs, isNotEmpty, reason: 'Port $port must read active DTCs');

      await protocol.disconnect();
    }
  });
}
