import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../utils/app_logger.dart';

typedef StatusCallback = void Function(String messageId, String status);
typedef PresenceCallback = void Function(
    String userId, bool isOnline, String? lastSeen);
typedef TypingCallback = void Function(String userId, bool isTyping);

class SocketService {
  static const _tag = 'SOCKET';

  // static const String _serverUrl = String.fromEnvironment(
  //   'SERVER_URL',
  //   defaultValue: 'http://192.168.0.183:3000',

  // );

  static const String _serverUrl = 'http://18.219.24.19:3000';

  IO.Socket? _socket;
  bool _isConnected = false;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  // Fires AFTER AuthNotifier has saved the message to DB — no race condition.
  final _processedController = StreamController<String>.broadcast(); // senderId

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// Emits the senderId after a message is fully processed and stored in DB.
  Stream<String> get processedMessageStream => _processedController.stream;

  /// Called by AuthNotifier after each message is decrypted + saved to DB.
  void notifyMessageProcessed(String senderId) {
    if (!_processedController.isClosed) {
      _processedController.add(senderId);
    }
  }

  StatusCallback? onMessageStatusChanged;
  PresenceCallback? onPresenceChanged;
  TypingCallback? onTypingChanged;

  bool get isConnected => _isConnected;

  void connect(String jwtToken) {
    // ── DIAG: Log current state before doing anything ─────────────────────────
    AppLogger.i(
      '╔══ CONNECT CALLED ══╗\n'
      '│ serverUrl   : $_serverUrl\n'
      '│ hasOldSocket: ${_socket != null}\n'
      '│ wasConnected: $_isConnected\n'
      '│ tokenPreview: ${jwtToken.length > 20 ? jwtToken.substring(0, 20) : jwtToken}...\n'
      '╚══════════════════════╝',
      tag: _tag,
    );

    // Close any existing connection before creating a new one
    if (_socket != null) {
      AppLogger.w('Old socket exists — disconnecting it first', tag: _tag);
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      AppLogger.d('Old socket disposed ✓', tag: _tag);
    }

    AppLogger.i('Creating new socket → $_serverUrl', tag: _tag);

    _socket = IO.io(
      _serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io/') // أضف هذا السطر
          .setAuth({'token': jwtToken})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .enableForceNew()
          .build(),
    );

    AppLogger.d('Socket instance created — registering event handlers',
        tag: _tag);

    _socket!.onConnect((_) {
      _isConnected = true;
      AppLogger.i(
        '✅ SOCKET CONNECTED — id: ${_socket?.id}',
        tag: _tag,
      );
    });

    _socket!.onDisconnect((reason) {
      _isConnected = false;
      AppLogger.w('❌ SOCKET DISCONNECTED — reason: $reason', tag: _tag);
    });

    _socket!.onConnectError((err) {
      AppLogger.e(
        '🔴 SOCKET CONNECT_ERROR\n'
        '│ error: $err\n'
        '│ serverUrl: $_serverUrl',
        tag: _tag,
        error: err is Exception ? err : null,
      );
    });

    _socket!.onError((err) {
      AppLogger.e('🔴 SOCKET ERROR: $err', tag: _tag);
    });

    _socket!.on('connect_error', (err) {
      AppLogger.e('🔴 connect_error event: $err', tag: _tag);
    });

    _socket!.onReconnect((attempt) {
      AppLogger.i('🔄 Reconnected after $attempt attempt(s)', tag: _tag);
    });

    _socket!.onReconnectAttempt((attempt) {
      AppLogger.d('🔄 Reconnect attempt #$attempt', tag: _tag);
    });

    _socket!.onReconnectError((err) {
      AppLogger.w('Reconnect error: $err', tag: _tag);
    });

    // ── message:receive ───────────────────────────────────────────────────────
    _socket!.on('message:receive', (data) {
      AppLogger.i(
        '📨 message:receive EVENT FIRED\n'
        '│ raw data type : ${data.runtimeType}\n'
        '│ raw data      : $data',
        tag: _tag,
      );
      if (data is Map<String, dynamic>) {
        AppLogger.d(
          'message:receive parsed OK\n'
          '│ from    : ${data['senderId']}\n'
          '│ to      : ${data['recipientId']}\n'
          '│ type    : ${data['type']}\n'
          '│ msgId   : ${data['messageId']}',
          tag: _tag,
        );
        _messageController.add(Map<String, dynamic>.from(data));
        AppLogger.d('Message added to Stream ✓', tag: _tag);
      } else {
        AppLogger.e(
          'message:receive — unexpected data type: ${data.runtimeType}',
          tag: _tag,
        );
      }
    });

    // ── message:status ────────────────────────────────────────────────────────
    _socket!.on('message:status', (data) {
      AppLogger.d(
        'message:status received — id:${data['messageId']} status:${data['status']}',
        tag: _tag,
      );
      if (data is Map<String, dynamic>) {
        final id = data['messageId'] as String;
        final status = data['status'] as String;
        onMessageStatusChanged?.call(id, status);
      }
    });

    // ── presence ──────────────────────────────────────────────────────────────
    _socket!.on('user:online', (data) {
      if (data is Map<String, dynamic>) {
        AppLogger.d('user:online — ${data['userId']}', tag: _tag);
        onPresenceChanged?.call(data['userId'] as String, true, null);
      }
    });

    _socket!.on('user:offline', (data) {
      if (data is Map<String, dynamic>) {
        AppLogger.d('user:offline — ${data['userId']}', tag: _tag);
        onPresenceChanged?.call(
          data['userId'] as String,
          false,
          data['lastSeen'] as String?,
        );
      }
    });

    // ── typing ────────────────────────────────────────────────────────────────
    _socket!.on('typing:start', (data) {
      if (data is Map<String, dynamic>) {
        onTypingChanged?.call(data['userId'] as String, true);
      }
    });

    _socket!.on('typing:stop', (data) {
      if (data is Map<String, dynamic>) {
        onTypingChanged?.call(data['userId'] as String, false);
      }
    });

    AppLogger.d(
        'All event handlers registered ✓ — socket is now auto-connecting',
        tag: _tag);
  }

  Future<String> sendMessage(Map<String, dynamic> messageData) async {
    final msgId = messageData['messageId'] ?? '?';
    final type = messageData['type'] ?? 'text';
    final to = messageData['recipientId'] ?? '?';

    AppLogger.d(
      '📤 sendMessage\n'
      '│ id    : $msgId\n'
      '│ type  : $type\n'
      '│ to    : $to\n'
      '│ connected: $_isConnected',
      tag: _tag,
    );

    if (_socket == null) {
      AppLogger.e('sendMessage — socket is NULL! Cannot send.', tag: _tag);
      return 'queued';
    }

    final completer = Completer<String>();

    _socket!.emitWithAck('message:send', messageData, ack: (response) {
      AppLogger.d(
        'message:send ACK received — response: $response',
        tag: _tag,
      );
      if (response is Map && response.containsKey('error')) {
        AppLogger.e('Send failed: ${response['error']}', tag: _tag);
        completer.completeError(response['error']);
      } else {
        final status = response['status'] as String? ?? 'sent';
        AppLogger.i('Message $msgId → $status', tag: _tag);
        completer.complete(status);
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        AppLogger.w(
          '⏱️ Message $msgId TIMED OUT — no ack from server after 10s\n'
          '│ connected: $_isConnected\n'
          '│ socketId : ${_socket?.id}',
          tag: _tag,
        );
        return 'queued';
      },
    );
  }

  void sendDeliveredAck(String messageId, String senderId) {
    AppLogger.v('Delivered ack → msgId:$messageId sender:$senderId', tag: _tag);
    _socket?.emit('message:delivered', {
      'messageId': messageId,
      'senderId': senderId,
    });
  }

  void sendReadAck(String messageId, String senderId) {
    AppLogger.v('Read ack → msgId:$messageId sender:$senderId', tag: _tag);
    _socket?.emit('message:read', {
      'messageId': messageId,
      'senderId': senderId,
    });
  }

  void sendTypingStart(String recipientId) {
    _socket?.emit('typing:start', {'recipientId': recipientId});
  }

  void sendTypingStop(String recipientId) {
    _socket?.emit('typing:stop', {'recipientId': recipientId});
  }

  void disconnect() {
    AppLogger.i('disconnect() called — socketId:${_socket?.id}', tag: _tag);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }

  void dispose() {
    AppLogger.d('SocketService.dispose()', tag: _tag);
    _messageController.close();
    _processedController.close();
    disconnect();
  }
}
