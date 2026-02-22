import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/chat_message.dart';
import '../utils/app_logger.dart';

typedef MessageCallback = void Function(ChatMessage message);
typedef StatusCallback = void Function(String messageId, String status);
typedef PresenceCallback = void Function(
    String userId, bool isOnline, String? lastSeen);
typedef TypingCallback = void Function(String userId, bool isTyping);

class SocketService {
  static const _tag = 'SOCKET';

  static const String _serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://192.168.0.100:3000',
  );

  IO.Socket? _socket;
  bool _isConnected = false;

  MessageCallback? onMessageReceived;
  StatusCallback? onMessageStatusChanged;
  PresenceCallback? onPresenceChanged;
  TypingCallback? onTypingChanged;

  bool get isConnected => _isConnected;

  void connect(String jwtToken) {
    AppLogger.i('Connecting to $_serverUrl ...', tag: _tag);

    _socket = IO.io(
      _serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': jwtToken})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      AppLogger.i('Connected ✓  (id: ${_socket?.id})', tag: _tag);
    });

    _socket!.onDisconnect((reason) {
      _isConnected = false;
      AppLogger.w('Disconnected — reason: $reason', tag: _tag);
    });

    _socket!.onConnectError((err) {
      AppLogger.e('Connection error', tag: _tag, error: err);
    });

    _socket!.onReconnect((attempt) {
      AppLogger.i('Reconnected after $attempt attempt(s)', tag: _tag);
    });

    _socket!.onReconnectAttempt((attempt) {
      AppLogger.d('Reconnect attempt #$attempt', tag: _tag);
    });

    // Receive message
    _socket!.on('message:receive', (data) {
      if (data is Map<String, dynamic>) {
        final msg = ChatMessage.fromJson(data);
        AppLogger.d(
          'Message received — type:${msg.type.name} from:${msg.senderId}',
          tag: _tag,
        );
        onMessageReceived?.call(msg);
      }
    });

    // Message status (delivered / read)
    _socket!.on('message:status', (data) {
      if (data is Map<String, dynamic>) {
        final id = data['messageId'] as String;
        final status = data['status'] as String;
        AppLogger.d('Status update — msg:$id → $status', tag: _tag);
        onMessageStatusChanged?.call(id, status);
      }
    });

    // User online
    _socket!.on('user:online', (data) {
      if (data is Map<String, dynamic>) {
        final userId = data['userId'] as String;
        AppLogger.d('User online: $userId', tag: _tag);
        onPresenceChanged?.call(userId, true, null);
      }
    });

    // User offline
    _socket!.on('user:offline', (data) {
      if (data is Map<String, dynamic>) {
        final userId = data['userId'] as String;
        AppLogger.d('User offline: $userId', tag: _tag);
        onPresenceChanged?.call(userId, false, data['lastSeen'] as String?);
      }
    });

    // Typing indicators
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
  }

  /// Send an encrypted text/file message
  Future<String> sendMessage(Map<String, dynamic> messageData) async {
    final msgId = messageData['messageId'] ?? '?';
    final type = messageData['type'] ?? 'text';
    AppLogger.d('Sending $type message — id:$msgId', tag: _tag);

    final completer = Completer<String>();

    _socket!.emitWithAck('message:send', messageData, ack: (response) {
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
        AppLogger.w('Message $msgId timed out — queued', tag: _tag);
        return 'queued';
      },
    );
  }

  void sendDeliveredAck(String messageId, String senderId) {
    AppLogger.v('Delivered ack → $messageId', tag: _tag);
    _socket!.emit('message:delivered', {
      'messageId': messageId,
      'senderId': senderId,
    });
  }

  void sendReadAck(String messageId, String senderId) {
    AppLogger.v('Read ack → $messageId', tag: _tag);
    _socket!.emit('message:read', {
      'messageId': messageId,
      'senderId': senderId,
    });
  }

  void sendTypingStart(String recipientId) {
    _socket!.emit('typing:start', {'recipientId': recipientId});
  }

  void sendTypingStop(String recipientId) {
    _socket!.emit('typing:stop', {'recipientId': recipientId});
  }

  void disconnect() {
    AppLogger.i('Disconnecting...', tag: _tag);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }
}
