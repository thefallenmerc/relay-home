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
  final Map<(String, int), _RelayConnection> _connections = {};
  final Map<(String, int), Future<CommandResult>> _commands = {};
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
    if (_connections[(ip, port)]?.closed == false) return true;
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
  }) {
    final frame = relayFrame(channel, on);
    final key = (ip, port);
    final previous = _commands[key];
    final operation = () async {
      if (previous != null) await previous;
      return _sendFrame(key, frame);
    }();
    _commands[key] = operation;
    unawaited(
      operation.then((_) {
        if (identical(_commands[key], operation)) _commands.remove(key);
      }),
    );
    return operation;
  }

  Future<CommandResult> _sendFrame((String, int) key, Uint8List frame) async {
    _RelayConnection? connection;
    bool writing = false;
    if (_disposed) {
      return const CommandResult(
        success: false,
        message: 'Connection was closed.',
      );
    }
    try {
      connection = _connections[key];
      if (connection == null || connection.closed) {
        final socket = await Socket.connect(key.$1, key.$2, timeout: timeout);
        if (_disposed) {
          socket.destroy();
          throw const SocketException('Connection was closed.');
        }
        final opened = _RelayConnection(socket, (closed) {
          if (identical(_connections[key], closed)) _connections.remove(key);
        });
        connection = opened;
        _connections[key] = opened;
        socket.setOption(SocketOption.tcpNoDelay, true);
        // Only a newly opened ESP connection needs time to settle.
        await Future<void>.delayed(settle);
      }
      connection.idleTimer?.cancel();
      if (_disposed || connection.closed) {
        throw const SocketException('Connection interrupted before sending.');
      }
      writing = true;
      connection.socket.add(frame);
      await connection.socket.flush().timeout(timeout);
      if (_disposed || connection.closed) {
        throw const SocketException('Connection interrupted after sending.');
      }
      // Preserve the board's hold-open interval without blocking the UI.
      // Another command can reuse this settled connection and reset the timer.
      connection.idleTimer = Timer(linger, connection.close);
      return const CommandResult(
        success: true,
        message: 'Command sent. Physical relay state is not confirmed.',
      );
    } on Object {
      connection?.close();
      return CommandResult(
        success: false,
        uncertain: writing,
        message: writing
            ? 'Connection interrupted. The command may have arrived; state is uncertain.'
            : 'Could not connect. Check the board’s power, Wi-Fi and IP address.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final connection in _connections.values.toList()) {
      connection.close();
    }
    _connections.clear();
  }
}

class _RelayConnection {
  final Socket socket;
  final void Function(_RelayConnection) onClosed;
  late final StreamSubscription<List<int>> _listener;
  Timer? idleTimer;
  bool closed = false;

  _RelayConnection(this.socket, this.onClosed) {
    _listener = socket.listen(
      (_) {},
      onError: (Object _) => close(),
      onDone: close,
    );
    // A peer can close during the background hold-open interval. Evict the
    // connection; never replay an already sent command automatically.
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) => close()));
  }

  void close() {
    if (closed) return;
    closed = true;
    idleTimer?.cancel();
    socket.destroy();
    unawaited(_listener.cancel());
    onClosed(this);
  }
}
