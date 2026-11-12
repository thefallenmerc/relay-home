import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_home/models.dart';
import 'package:relay_home/services/network_service.dart';
import 'package:relay_home/services/relay_transport.dart';

void main() {
  test('all eight frames exactly match the stock four-relay protocol', () {
    final frames = {
      (1, false): [0xa0, 1, 0, 0xa1],
      (1, true): [0xa0, 1, 1, 0xa2],
      (2, false): [0xa0, 2, 0, 0xa2],
      (2, true): [0xa0, 2, 1, 0xa3],
      (3, false): [0xa0, 3, 0, 0xa3],
      (3, true): [0xa0, 3, 1, 0xa4],
      (4, false): [0xa0, 4, 0, 0xa4],
      (4, true): [0xa0, 4, 1, 0xa5],
    };
    for (final entry in frames.entries) {
      expect(relayFrame(entry.key.$1, entry.key.$2), entry.value);
    }
    expect(() => relayFrame(0, false), throwsArgumentError);
    expect(() => relayFrame(5, true), throwsArgumentError);
  });
  test(
    'TCP writes raw bytes after settling and lingers before closing',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final transport = TcpRelayTransport(
        settle: const Duration(milliseconds: 75),
        linger: const Duration(milliseconds: 100),
      );
      final connected = Completer<DateTime>();
      final received = Completer<(DateTime, List<int>)>();
      final closed = Completer<DateTime>();
      final peer = Completer<Socket>();
      final subscription = server.listen((socket) {
        peer.complete(socket);
        connected.complete(DateTime.now());
        socket.listen((data) {
          if (!received.isCompleted) received.complete((DateTime.now(), data));
        }, onDone: () => closed.complete(DateTime.now()));
      });
      final result = await transport.send(
        '127.0.0.1',
        3,
        true,
        port: server.port,
      );
      expect(result.success, true);
      expect(result.message, contains('not confirmed'));
      final packet = await received.future;
      expect(packet.$2, [0xa0, 3, 1, 0xa4]);
      expect(
        packet.$1.difference(await connected.future).inMilliseconds,
        greaterThanOrEqualTo(60),
      );
      expect(
        (await closed.future).difference(packet.$1).inMilliseconds,
        greaterThanOrEqualTo(85),
      );
      (await peer.future).destroy();
      transport.dispose();
      await subscription.cancel();
      await server.close();
    },
  );
  test('reachability probe sends no relay payload', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = <int>[];
    final closed = Completer<void>();
    final subscription = server.listen((s) {
      s.listen(
        bytes.addAll,
        onDone: () {
          s.destroy();
          closed.complete();
        },
      );
    });
    final transport = TcpRelayTransport();
    expect(await transport.check('127.0.0.1', port: server.port), true);
    await closed.future;
    expect(bytes, isEmpty);
    transport.dispose();
    await subscription.cancel();
    await server.close();
  });
  test('discovery uses the actual /28 and excludes self/broadcast', () {
    final hosts = localHosts(
      const NetworkSnapshot(
        isWifi: true,
        ipv4: '172.20.10.6',
        subnetMask: '255.255.255.240',
      ),
    );
    expect(hosts.length, 13);
    expect(hosts.first, '172.20.10.1');
    expect(hosts.last, '172.20.10.14');
    expect(hosts, isNot(contains('172.20.10.6')));
    expect(hosts, isNot(contains('172.20.10.15')));
  });
  test('discovery rejects public, missing, huge and noncontiguous subnets', () {
    for (final network in [
      const NetworkSnapshot(),
      const NetworkSnapshot(
        isWifi: true,
        ipv4: '8.8.8.8',
        subnetMask: '255.255.255.0',
      ),
      const NetworkSnapshot(
        isWifi: true,
        ipv4: '10.1.2.3',
        subnetMask: '255.0.0.0',
      ),
      const NetworkSnapshot(
        isWifi: true,
        ipv4: '192.168.1.3',
        subnetMask: '255.0.255.0',
      ),
    ]) {
      expect(() => localHosts(network), throwsStateError);
    }
  });
}
