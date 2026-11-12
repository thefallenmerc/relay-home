import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../models.dart';

Uint8List relayFrame(int channel, bool on) {
  if (channel < 1 || channel > 4) {
    throw ArgumentError.value(channel, 'channel', 'Must be 1–4');
  }
  final state = on ? 1 : 0;
  return Uint8List.fromList([
    0xa0,
    channel,
    state,
    (0xa0 + channel + state) & 0xff,
  ]);
}

abstract class RelayTransport {
  Future<bool> check(
    String ip, {
    int port = 8080,
    Duration timeout = const Duration(seconds: 2),
  });
  Future<CommandResult> send(
    String ip,
    int channel,
    bool on, {
    int port = 8080,
  });
  void dispose();
}

class TcpRelayTransport implements RelayTransport {
  final Duration settle, linger, timeout;
  final Set<Socket> _sockets = {};
  bool _disposed = false;
  TcpRelayTransport({
    this.settle = const Duration(milliseconds: 500),
    this.linger = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 3),
  });

  @override
  Future<bool> check(
    String ip, {
    int port = 8080,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    Socket? socket;
    if (_disposed) return false;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      if (_disposed) return false;
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<CommandResult> send(
    String ip,
    int channel,
    bool on, {
    int port = 8080,
  }) async {
    final frame = relayFrame(channel, on);
    Socket? socket;
    StreamSubscription<List<int>>? listener;
    Object? streamError;
    bool remoteClosed = false;
    bool writing = false;
    if (_disposed) {
      return const CommandResult(
        success: false,
        message: 'Connection was closed.',
      );
    }
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      _sockets.add(socket);
      listener = socket.listen(
        (_) {},
        onError: (Object error) {
          streamError = error;
        },
        onDone: () {
          remoteClosed = true;
        },
      );
      await Future<void>.delayed(settle);
      if (_disposed || streamError != null || remoteClosed) {
        throw const SocketException('Connection interrupted before sending.');
      }
      writing = true;
      socket.add(frame);
      await socket.flush().timeout(timeout);
      await Future<void>.delayed(linger);
      if (_disposed || streamError != null || remoteClosed) {
        throw const SocketException('Connection interrupted after sending.');
      }
      return const CommandResult(
        success: true,
        message: 'Command sent. Physical relay state is not confirmed.',
      );
    } on Object {
      return CommandResult(
        success: false,
        uncertain: writing,
        message: writing
            ? 'Connection interrupted. The command may have arrived; state is uncertain.'
            : 'Could not connect. Check the board’s power, Wi-Fi and IP address.',
      );
    } finally {
      socket?.destroy();
      if (socket != null) _sockets.remove(socket);
      await listener?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final socket in _sockets) {
      socket.destroy();
    }
    _sockets.clear();
  }
}
