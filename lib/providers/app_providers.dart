import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../core/encryption/encryption_service.dart';
import '../core/network/api_service.dart';
import '../core/network/socket_service.dart';
import '../core/database/local_database.dart';
import '../core/models/chat_message.dart';
import '../core/utils/app_logger.dart';
import 'package:drift/drift.dart';

// ─── Service Providers (Singletons) ──────────────────────────────────────────

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final db = LocalDatabase();
  ref.onDispose(db.close);
  return db;
});

// ─── Auth State ───────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoggedIn;
  final String? userId;
  final String? userName;
  final String? avatarColor;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.userId,
    this.userName,
    this.avatarColor,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? userId,
    String? userName,
    String? avatarColor,
    bool? isLoading,
    String? error,
  }) =>
      AuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        avatarColor: avatarColor ?? this.avatarColor,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;
  final EncryptionService _enc;
  final SocketService _socket;
  final LocalDatabase _db;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  AuthNotifier(this._api, this._enc, this._socket, this._db)
      : super(const AuthState());

  Future<void> tryAutoLogin() async {
    AppLogger.i('Checking stored credentials...', tag: 'AUTH');
    final token = await _storage.read(key: 'jwt_token');
    final userId = await _storage.read(key: 'user_id');
    final userName = await _storage.read(key: 'user_name');
    final avatarColor = await _storage.read(key: 'avatar_color');

    if (token != null && userId != null) {
      AppLogger.i('Found saved session — userId: $userId', tag: 'AUTH');
      _api.setToken(token);
      AppLogger.d('API token set', tag: 'AUTH');
      await _enc.initialize();
      AppLogger.d('Encryption keys loaded from secure storage', tag: 'AUTH');
      _socket.connect(token);
      state = AuthState(
        isLoggedIn: true,
        userId: userId,
        userName: userName,
        avatarColor: avatarColor,
      );
      AppLogger.i('Auto-login successful — welcome back $userName',
          tag: 'AUTH');
    } else {
      AppLogger.i('No saved session found — showing login screen', tag: 'AUTH');
    }
  }

  Future<void> login(String userId, String password) async {
    AppLogger.i('Login attempt — userId: $userId', tag: 'AUTH');
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Step 1: init encryption & get public key
      AppLogger.d('Initializing encryption service...', tag: 'AUTH');
      await _enc.initialize();
      final publicKey = await _enc.getPublicKeyBase64();
      AppLogger.d('X25519 public key ready (${publicKey.substring(0, 12)}...)',
          tag: 'AUTH');

      // Step 2: API login
      AppLogger.d('Sending login request to server...', tag: 'AUTH');
      final result = await _api.login(
        userId: userId,
        password: password,
        publicKey: publicKey,
      );

      final token = result['token'] as String;
      final user = result['user'] as Map<String, dynamic>;
      AppLogger.i('Server responded OK — user: ${user['name']}', tag: 'AUTH');

      // Step 3: persist credentials
      AppLogger.d('Saving credentials to secure storage...', tag: 'AUTH');
      await _storage.write(key: 'jwt_token', value: token);
      await _storage.write(key: 'user_id', value: user['id'] as String);
      await _storage.write(key: 'user_name', value: user['name'] as String);
      await _storage.write(
          key: 'avatar_color',
          value: user['avatarColor'] as String? ?? '#6C63FF');

      // Step 4: connect socket
      _api.setToken(token);
      AppLogger.d('JWT token applied to API service', tag: 'AUTH');
      _socket.connect(token);

      state = state.copyWith(
        isLoggedIn: true,
        userId: user['id'] as String,
        userName: user['name'] as String,
        avatarColor: user['avatarColor'] as String?,
        isLoading: false,
      );
      AppLogger.i('Login complete — welcome ${user['name']}!', tag: 'AUTH');
    } catch (e) {
      AppLogger.e('Login failed', tag: 'AUTH', error: e);
      state = state.copyWith(
        isLoading: false,
        error: 'بيانات الدخول غير صحيحة',
      );
    }
  }

  Future<void> logout() async {
    AppLogger.i('Logging out user: ${state.userId}', tag: 'AUTH');
    _socket.disconnect();
    _api.clearToken();
    await _storage.deleteAll();
    state = const AuthState();
    AppLogger.i('Logout complete — all credentials cleared', tag: 'AUTH');
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(apiServiceProvider),
    ref.watch(encryptionServiceProvider),
    ref.watch(socketServiceProvider),
    ref.watch(localDatabaseProvider),
  );
});

// ─── Users Provider ───────────────────────────────────────────────────────────

final usersProvider = FutureProvider<List<AppUserModel>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final rawUsers = await api.getUsers();
  return rawUsers.map((u) => AppUserModel.fromJson(u)).toList();
});

// ─── Chat Provider ────────────────────────────────────────────────────────────

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final String peerId;
  final String myId;
  final ApiService _api;
  final EncryptionService _enc;
  final SocketService _socket;
  final LocalDatabase _db;
  String? _peerPublicKey;
  String? _conversationId;

  ChatNotifier({
    required this.peerId,
    required this.myId,
    required ApiService api,
    required EncryptionService enc,
    required SocketService socket,
    required LocalDatabase db,
  })  : _api = api,
        _enc = enc,
        _socket = socket,
        _db = db,
        super([]);

  Future<void> initialize() async {
    AppLogger.i('Initializing chat with peer: $peerId', tag: 'CHAT');

    AppLogger.d('Fetching peer public key from server...', tag: 'CHAT');
    _peerPublicKey = await _api.getUserPublicKey(peerId);
    if (_peerPublicKey != null) {
      AppLogger.d(
          'Peer public key received (${_peerPublicKey!.substring(0, 12)}...)',
          tag: 'CHAT');
    } else {
      AppLogger.w(
          'Peer public key not found — E2EE will not work until peer logs in',
          tag: 'CHAT');
    }

    _conversationId = await _db.getOrCreateConversation(peerId);
    AppLogger.d('Conversation ready: $_conversationId', tag: 'CHAT');
    await _db.clearUnread(_conversationId!);

    _socket.onMessageReceived = _handleIncomingMessage;
    AppLogger.i('Chat initialized ✓', tag: 'CHAT');
  }

  Future<void> _handleIncomingMessage(ChatMessage raw) async {
    if (raw.senderId != peerId) return;

    AppLogger.d('Incoming message — id:${raw.id} type:${raw.type.name}',
        tag: 'CHAT');
    ChatMessage message = raw.copyWith();

    if (raw.type == MessageType.text && _peerPublicKey != null) {
      AppLogger.d('Decrypting text message...', tag: 'CHAT');
      try {
        final decrypted = await _enc.decryptText(
          ciphertextBase64: raw.encryptedContent!,
          ivBase64: raw.iv!,
          senderPublicKeyBase64: _peerPublicKey!,
        );
        message = raw.copyWith(
          status: MessageStatus.delivered,
          decryptedText: decrypted,
        );
        AppLogger.d('Decryption successful ✓', tag: 'CHAT');
      } catch (e) {
        AppLogger.e('Decryption failed for msg:${raw.id}',
            tag: 'CHAT', error: e);
        message = raw.copyWith(status: MessageStatus.failed);
      }
    }

    AppLogger.v('Saving message to local DB...', tag: 'CHAT');
    await _saveMessageToDb(message);
    state = [...state, message];

    _socket.sendDeliveredAck(raw.id, raw.senderId);
    AppLogger.v('Delivered ack sent for msg:${raw.id}', tag: 'CHAT');
  }

  Future<void> sendText(String text) async {
    if (_peerPublicKey == null) {
      AppLogger.w('Cannot send — peer public key not available', tag: 'CHAT');
      return;
    }

    final msgId = const Uuid().v4();
    AppLogger.d('Encrypting text message — id:$msgId', tag: 'CHAT');

    final encrypted = await _enc.encryptText(
      plaintext: text,
      recipientPublicKeyBase64: _peerPublicKey!,
    );
    AppLogger.d('Encryption done ✓ iv:${encrypted['iv']?.substring(0, 8)}...',
        tag: 'CHAT');

    final msg = ChatMessage(
      id: msgId,
      conversationId: _conversationId ?? '',
      senderId: myId,
      recipientId: peerId,
      type: MessageType.text,
      encryptedContent: encrypted['ciphertext'],
      iv: encrypted['iv'],
      decryptedText: text,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
    );

    state = [...state, msg];
    AppLogger.v('Message added to UI state (status: sending)', tag: 'CHAT');
    await _saveMessageToDb(msg);

    try {
      AppLogger.d('Relaying message via socket...', tag: 'CHAT');
      final status = await _socket.sendMessage(msg.toSocketJson());
      final newStatus =
          status == 'delivered' ? MessageStatus.delivered : MessageStatus.sent;
      AppLogger.i('Message $msgId → $status', tag: 'CHAT');
      await _db.updateMessageStatus(msgId, newStatus.name);
      await _db.updateConversationLastMessage(
        _conversationId!,
        '🔒 رسالة مشفرة',
        DateTime.now().toIso8601String(),
      );
      state = state
          .map((m) => m.id == msgId ? m.copyWith(status: newStatus) : m)
          .toList();
    } catch (e) {
      AppLogger.e('Failed to send message $msgId', tag: 'CHAT', error: e);
      await _db.updateMessageStatus(msgId, MessageStatus.failed.name);
      state = state
          .map((m) =>
              m.id == msgId ? m.copyWith(status: MessageStatus.failed) : m)
          .toList();
    }
  }

  Future<void> sendFile({
    required Uint8List fileBytes,
    required String fileName,
    required String fileType,
  }) async {
    if (_peerPublicKey == null) {
      AppLogger.w('Cannot send file — peer public key not available',
          tag: 'CHAT');
      return;
    }

    final msgId = const Uuid().v4();
    final messageType = _getMessageType(fileType);
    final sizeKb = (fileBytes.length / 1024).toStringAsFixed(1);
    AppLogger.i('Sending file: $fileName ($sizeKb KB) type:$fileType id:$msgId',
        tag: 'CHAT');

    final msg = ChatMessage(
      id: msgId,
      conversationId: _conversationId ?? '',
      senderId: myId,
      recipientId: peerId,
      type: messageType,
      fileName: fileName,
      fileType: fileType,
      fileSize: fileBytes.length,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
    );
    state = [...state, msg];

    try {
      AppLogger.d('Encrypting file...', tag: 'CHAT');
      final encrypted = await _enc.encryptFile(
        fileBytes: fileBytes,
        recipientPublicKeyBase64: _peerPublicKey!,
      );
      AppLogger.d(
          'File encrypted ✓ (${(encrypted.encryptedBytes.length / 1024).toStringAsFixed(1)} KB)',
          tag: 'CHAT');

      AppLogger.d('Uploading encrypted file to relay server...', tag: 'CHAT');
      final fileId = await _api.uploadEncryptedFile(
        encryptedBytes: encrypted.encryptedBytes,
        recipientId: peerId,
        encryptedKey: encrypted.encryptedKeyBase64,
        iv: encrypted.ivBase64,
        fileType: fileType,
        originalName: fileName,
        messageId: msgId,
      );
      AppLogger.i('File uploaded ✓ fileId:$fileId', tag: 'CHAT');

      final msgWithFile =
          msg.copyWith(fileId: fileId, status: MessageStatus.sent);

      AppLogger.d('Saving original file locally...', tag: 'CHAT');
      final localPath = await _api.saveFileLocally(
        bytes: fileBytes,
        fileName: fileName,
        subFolder: _getFolderForType(messageType),
      );
      AppLogger.d('Saved locally: $localPath', tag: 'CHAT');

      final msgFinal = msgWithFile.copyWith(localFilePath: localPath);
      await _saveMessageToDb(msgFinal);

      AppLogger.d('Notifying recipient via socket...', tag: 'CHAT');
      await _socket.sendMessage(msgFinal.toSocketJson());

      state = state.map((m) => m.id == msgId ? msgFinal : m).toList();
      AppLogger.i('File message complete ✓', tag: 'CHAT');
    } catch (e) {
      AppLogger.e('Failed to send file $fileName', tag: 'CHAT', error: e);
      state = state
          .map((m) =>
              m.id == msgId ? m.copyWith(status: MessageStatus.failed) : m)
          .toList();
    }
  }

  Future<void> downloadFile(ChatMessage msg) async {
    if (msg.fileId == null || msg.localFilePath != null) return;

    AppLogger.i('Downloading file: ${msg.fileName} (fileId:${msg.fileId})',
        tag: 'CHAT');

    try {
      AppLogger.d('Fetching encrypted bytes from relay server...', tag: 'CHAT');
      final encryptedBytes = await _api.downloadEncryptedFile(
        fileId: msg.fileId!,
      );
      AppLogger.d(
          'Downloaded ${(encryptedBytes.length / 1024).toStringAsFixed(1)} KB encrypted',
          tag: 'CHAT');

      AppLogger.d('Decrypting file...', tag: 'CHAT');
      final peerPubKey = _peerPublicKey!;
      final decryptedBytes = await _enc.decryptFile(
        encryptedBytes: encryptedBytes,
        ivBase64: msg.iv ?? '',
        encryptedKeyBase64: msg.encryptedKey ?? '',
        senderPublicKeyBase64: peerPubKey,
      );
      AppLogger.d(
          'File decrypted ✓ (${(decryptedBytes.length / 1024).toStringAsFixed(1)} KB)',
          tag: 'CHAT');

      AppLogger.d('Saving file locally...', tag: 'CHAT');
      final localPath = await _api.saveFileLocally(
        bytes: decryptedBytes,
        fileName: msg.fileName ?? 'file',
        subFolder: _getFolderForType(msg.type),
      );

      await _db.updateMessageLocalPath(msg.id, localPath);
      state = state
          .map((m) => m.id == msg.id ? m.copyWith(localFilePath: localPath) : m)
          .toList();
      AppLogger.i('File downloaded and saved: $localPath', tag: 'CHAT');
    } catch (e) {
      AppLogger.e('Failed to download file ${msg.fileName}',
          tag: 'CHAT', error: e);
    }
  }

  Future<void> _saveMessageToDb(ChatMessage msg) async {
    final convId = _conversationId ?? await _db.getOrCreateConversation(peerId);
    await _db.insertMessage(MessagesCompanion(
      id: Value(msg.id),
      conversationId: Value(convId),
      senderId: Value(msg.senderId),
      recipientId: Value(msg.recipientId),
      type: Value(msg.type.name),
      encryptedContent: Value(msg.encryptedContent),
      iv: Value(msg.iv),
      fileId: Value(msg.fileId),
      localFilePath: Value(msg.localFilePath),
      fileName: Value(msg.fileName),
      fileType: Value(msg.fileType),
      fileSize: Value(msg.fileSize),
      encryptedKey: Value(msg.encryptedKey),
      status: Value(msg.status.name),
      timestamp: Value(msg.timestamp.toIso8601String()),
    ));
  }

  MessageType _getMessageType(String mimeType) {
    if (mimeType.startsWith('image/')) return MessageType.image;
    if (mimeType.startsWith('video/')) return MessageType.video;
    return MessageType.file;
  }

  String _getFolderForType(MessageType type) {
    switch (type) {
      case MessageType.image:
        return 'images';
      case MessageType.video:
        return 'videos';
      default:
        return 'files';
    }
  }
}

final chatProvider =
    StateNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>(
  (ref, peerId) {
    final auth = ref.watch(authProvider);
    return ChatNotifier(
      peerId: peerId,
      myId: auth.userId ?? '',
      api: ref.watch(apiServiceProvider),
      enc: ref.watch(encryptionServiceProvider),
      socket: ref.watch(socketServiceProvider),
      db: ref.watch(localDatabaseProvider),
    );
  },
);
