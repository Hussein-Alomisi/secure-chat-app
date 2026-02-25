import 'dart:async';
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
  final s = SocketService();
  ref.onDispose(s.dispose);
  return s;
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

  // Global subscription — saves ALL incoming messages to DB immediately,
  // regardless of which screen is open.
  StreamSubscription<Map<String, dynamic>>? _globalMsgSub;

  AuthNotifier(this._api, this._enc, this._socket, this._db)
      : super(const AuthState());

  /// Called after connecting. Listens to ALL messages globally.
  void _startGlobalMessageListener(String myUserId) {
    _globalMsgSub?.cancel();
    AppLogger.i(
      '╔══ GLOBAL LISTENER STARTED ══╗\n'
      '│ myUserId: $myUserId\n'
      '╚═════════════════════════════╝',
      tag: 'AUTH',
    );
    _globalMsgSub = _socket.messageStream.listen(
      (data) async {
        AppLogger.i(
          '╔══ GLOBAL: MESSAGE RECEIVED ══╗\n'
          '│ from  : ${data['senderId']}\n'
          '│ to    : ${data['recipientId']}\n'
          '│ type  : ${data['type']}\n'
          '│ msgId : ${data['messageId']}\n'
          '╚══════════════════════════════╝',
          tag: 'AUTH',
        );
        try {
          // STEP 1: Parse
          final msg = ChatMessage.fromJson(data);
          AppLogger.d('STEP 1 ✓ fromJson — id:${msg.id}', tag: 'AUTH');

          // STEP 2: Ensure sender in AppUsers (FK)
          final senderExists = await _db.getUserById(msg.senderId);
          AppLogger.d('STEP 2: senderExists=${senderExists != null}',
              tag: 'AUTH');
          if (senderExists == null) {
            AppLogger.w(
              'STEP 2: sender ${msg.senderId} not in local DB — fetching users from API',
              tag: 'AUTH',
            );
            try {
              final users = await _api.getUsers();
              AppLogger.d('STEP 2: API returned ${users.length} users',
                  tag: 'AUTH');
              for (final u in users) {
                await _db.upsertUser(AppUsersCompanion(
                  id: Value(u['id'] as String),
                  name: Value(u['name'] as String),
                  avatarColor: Value(u['avatarColor'] as String? ?? '#6C63FF'),
                  publicKey: Value(u['publicKey'] as String?),
                ));
              }
              AppLogger.d('STEP 2 ✓ All users upserted to local DB',
                  tag: 'AUTH');
            } catch (e) {
              AppLogger.e('STEP 2: getUsers failed — inserting placeholder',
                  tag: 'AUTH', error: e);
              await _db.upsertUser(AppUsersCompanion(
                id: Value(msg.senderId),
                name: Value(msg.senderId),
                avatarColor: const Value('#6C63FF'),
              ));
              AppLogger.w('STEP 2 ✓ placeholder inserted for ${msg.senderId}',
                  tag: 'AUTH');
            }
          }

          // STEP 3: Decrypt
          ChatMessage processed = msg;
          if (msg.type == MessageType.text) {
            AppLogger.d('STEP 3: decrypting text message...', tag: 'AUTH');
            try {
              final senderKey = await _api.getUserPublicKey(msg.senderId);
              AppLogger.d(
                  'STEP 3: senderKey=${senderKey != null ? senderKey.substring(0, 12) + "..." : "NULL"}',
                  tag: 'AUTH');
              if (senderKey != null) {
                final decrypted = await _enc.decryptText(
                  ciphertextBase64: msg.encryptedContent!,
                  ivBase64: msg.iv!,
                  senderPublicKeyBase64: senderKey,
                );
                processed = msg.copyWith(
                  status: MessageStatus.delivered,
                  decryptedText: decrypted,
                );
                AppLogger.d(
                    'STEP 3 ✓ decrypted: "${decrypted.substring(0, decrypted.length.clamp(0, 30))}..."',
                    tag: 'AUTH');
              } else {
                AppLogger.w(
                    'STEP 3: sender public key is null — storing encrypted',
                    tag: 'AUTH');
                processed = msg.copyWith(status: MessageStatus.delivered);
              }
            } catch (e) {
              AppLogger.e('STEP 3: decryption FAILED', tag: 'AUTH', error: e);
              processed = msg.copyWith(status: MessageStatus.delivered);
            }
          } else {
            AppLogger.d('STEP 3: skipped (non-text type: ${msg.type.name})',
                tag: 'AUTH');
          }

          // STEP 4: Save to DB
          AppLogger.d('STEP 4: getOrCreateConversation(${msg.senderId})...',
              tag: 'AUTH');
          final convId = await _db.getOrCreateConversation(msg.senderId);
          AppLogger.d('STEP 4: convId=$convId', tag: 'AUTH');
          final msgWithConv = processed.copyWith(conversationId: convId);
          await _saveToDb(msgWithConv);
          AppLogger.d('STEP 4 ✓ message saved to DB', tag: 'AUTH');

          await _db.updateConversationLastMessage(
            convId,
            msg.type == MessageType.text ? '🔒 رسالة مشفرة' : '📎 ملف',
            msg.timestamp.toIso8601String(),
          );
          AppLogger.d('STEP 4 ✓ conversation last-message updated',
              tag: 'AUTH');

          // STEP 5: Ack + notify ChatNotifier the DB is ready
          _socket.sendDeliveredAck(msg.id, msg.senderId);
          _socket.notifyMessageProcessed(msg.senderId);
          AppLogger.i(
            '╔══ GLOBAL: msg ${msg.id} COMPLETE ✓ ══╗\n'
            '│ saved to DB, ack sent, UI notified\n'
            '╚════════════════════════════════════╝',
            tag: 'AUTH',
          );
        } catch (e, stack) {
          AppLogger.e(
            '╔══ GLOBAL LISTENER ERROR ══╗\n'
            '│ $e\n'
            '╚═══════════════════════════╝',
            tag: 'AUTH',
            error: e,
          );
          AppLogger.e('Stack: $stack', tag: 'AUTH');
        }
      },
      onError: (e) {
        AppLogger.e('GLOBAL LISTENER stream error: $e', tag: 'AUTH');
      },
      onDone: () {
        AppLogger.w('GLOBAL LISTENER stream DONE (closed?)', tag: 'AUTH');
      },
    );
    AppLogger.i('Global message listener registered ✓', tag: 'AUTH');
  }

  Future<void> _saveToDb(ChatMessage msg) async {
    await _db.insertMessage(MessagesCompanion(
      id: Value(msg.id),
      conversationId: Value(msg.conversationId),
      senderId: Value(msg.senderId),
      recipientId: Value(msg.recipientId),
      type: Value(msg.type.name),
      encryptedContent: Value(msg.encryptedContent),
      iv: Value(msg.iv),
      decryptedText: Value(msg.decryptedText),
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

  // ─── Auth actions ─────────────────────────────────────────────────────────

  Future<void> tryAutoLogin() async {
    AppLogger.i('Checking stored credentials...', tag: 'AUTH');
    final token = await _storage.read(key: 'jwt_token');
    final userId = await _storage.read(key: 'user_id');
    final userName = await _storage.read(key: 'user_name');
    final avatarColor = await _storage.read(key: 'avatar_color');

    if (token != null && userId != null) {
      AppLogger.i('Found saved session — userId: $userId', tag: 'AUTH');
      _api.setToken(token);
      await _enc.initialize();
      AppLogger.d('Encryption keys loaded', tag: 'AUTH');
      _socket.connect(token);
      _startGlobalMessageListener(userId);
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
      AppLogger.d('Initializing encryption service...', tag: 'AUTH');
      await _enc.initialize();
      final publicKey = await _enc.getPublicKeyBase64();
      AppLogger.d('X25519 public key ready (${publicKey.substring(0, 12)}...)',
          tag: 'AUTH');

      AppLogger.d('Sending login request to server...', tag: 'AUTH');
      final result = await _api.login(
        userId: userId,
        password: password,
        publicKey: publicKey,
      );

      final token = result['token'] as String;
      final user = result['user'] as Map<String, dynamic>;
      AppLogger.i('Server responded OK — user: ${user['name']}', tag: 'AUTH');

      await _storage.write(key: 'jwt_token', value: token);
      await _storage.write(key: 'user_id', value: user['id'] as String);
      await _storage.write(key: 'user_name', value: user['name'] as String);
      await _storage.write(
          key: 'avatar_color',
          value: user['avatarColor'] as String? ?? '#6C63FF');

      _api.setToken(token);
      AppLogger.d('JWT token applied to API service', tag: 'AUTH');

      _socket.connect(token);
      _startGlobalMessageListener(user['id'] as String);

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
    await _globalMsgSub?.cancel();
    _globalMsgSub = null;
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
  StreamSubscription<String>? _msgSub;

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
          'Peer public key not found — E2EE unavailable until peer logs in',
          tag: 'CHAT');
    }

    _conversationId = await _db.getOrCreateConversation(peerId);
    AppLogger.d('Conversation ready: $_conversationId', tag: 'CHAT');

    // Load existing messages from local DB into UI state
    final existing = await _db.getMessages(_conversationId!);
    state = existing.map((r) => ChatMessage.fromDb(r)).toList();
    AppLogger.d('Loaded ${existing.length} messages from local DB',
        tag: 'CHAT');

    await _db.clearUnread(_conversationId!);

    // Subscribe to the PROCESSED stream (fires after AuthNotifier saves to DB)
    // This eliminates the race condition — no delay needed.
    _msgSub?.cancel();
    _msgSub = _socket.processedMessageStream
        .where((senderId) => senderId == peerId)
        .listen((_) => _refreshFromDb());

    AppLogger.i('Chat initialized ✓', tag: 'CHAT');
  }

  Future<void> _refreshFromDb() async {
    if (_conversationId == null) return;
    AppLogger.d('Refreshing UI from DB for conv:$_conversationId', tag: 'CHAT');
    final msgs = await _db.getMessages(_conversationId!);
    state = msgs.map((r) => ChatMessage.fromDb(r)).toList();
    AppLogger.d('UI refreshed — ${msgs.length} messages', tag: 'CHAT');
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
    AppLogger.d('Encryption done ✓', tag: 'CHAT');

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
      decryptedText: Value(msg.decryptedText),
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

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
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
