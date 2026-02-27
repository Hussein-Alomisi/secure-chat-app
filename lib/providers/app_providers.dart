import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
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

// ─── Theme Mode Provider ──────────────────────────────────────────────────────

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

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
          AppLogger.d(
            'STEP 2: senderExists=${senderExists != null}',
            tag: 'AUTH',
          );
          if (senderExists == null) {
            AppLogger.w(
              'STEP 2: sender ${msg.senderId} not in local DB — fetching users from API',
              tag: 'AUTH',
            );
            try {
              final users = await _api.getUsers();
              AppLogger.d(
                'STEP 2: API returned ${users.length} users',
                tag: 'AUTH',
              );
              for (final u in users) {
                await _db.upsertUser(
                  AppUsersCompanion(
                    id: Value(u['id'] as String),
                    name: Value(u['name'] as String),
                    avatarColor: Value(
                      u['avatarColor'] as String? ?? '#6C63FF',
                    ),
                    publicKey: Value(u['publicKey'] as String?),
                  ),
                );
              }
              AppLogger.d(
                'STEP 2 ✓ All users upserted to local DB',
                tag: 'AUTH',
              );
            } catch (e) {
              AppLogger.e(
                'STEP 2: getUsers failed — inserting placeholder',
                tag: 'AUTH',
                error: e,
              );
              await _db.upsertUser(
                AppUsersCompanion(
                  id: Value(msg.senderId),
                  name: Value(msg.senderId),
                  avatarColor: const Value('#6C63FF'),
                ),
              );
              AppLogger.w(
                'STEP 2 ✓ placeholder inserted for ${msg.senderId}',
                tag: 'AUTH',
              );
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
                tag: 'AUTH',
              );
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
                  tag: 'AUTH',
                );
              } else {
                AppLogger.w(
                  'STEP 3: sender public key is null — storing encrypted',
                  tag: 'AUTH',
                );
                processed = msg.copyWith(status: MessageStatus.delivered);
              }
            } catch (e) {
              AppLogger.e('STEP 3: decryption FAILED', tag: 'AUTH', error: e);
              processed = msg.copyWith(status: MessageStatus.delivered);
            }
          } else {
            AppLogger.d(
              'STEP 3: skipped (non-text type: ${msg.type.name})',
              tag: 'AUTH',
            );
          }

          // STEP 4: Save to DB
          AppLogger.d(
            'STEP 4: getOrCreateConversation(${msg.senderId})...',
            tag: 'AUTH',
          );
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
          AppLogger.d(
            'STEP 4 ✓ conversation last-message updated',
            tag: 'AUTH',
          );

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
    await _db.insertMessage(
      MessagesCompanion(
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
      ),
    );
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
      AppLogger.i(
        'Auto-login successful — welcome back $userName',
        tag: 'AUTH',
      );
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
      AppLogger.d(
        'X25519 public key ready (${publicKey.substring(0, 12)}...)',
        tag: 'AUTH',
      );

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
        value: user['avatarColor'] as String? ?? '#6C63FF',
      );

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

class UsersNotifier extends StateNotifier<AsyncValue<List<AppUserModel>>> {
  final ApiService _api;
  final SocketService _socket;

  UsersNotifier(this._api, this._socket) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final rawUsers = await _api.getUsers();
      final users = rawUsers.map((u) => AppUserModel.fromJson(u)).toList();
      state = AsyncValue.data(users);

      _socket.onPresenceChanged = (userId, isOnline, lastSeen) {
        if (state is AsyncData<List<AppUserModel>>) {
          final currentUsers = state.value!;
          state = AsyncValue.data(
            currentUsers.map((u) {
              if (u.id == userId) {
                return u.copyWith(isOnline: isOnline, lastSeen: lastSeen);
              }
              return u;
            }).toList(),
          );
        }
      };
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _init();
  }
}

final usersProvider =
    StateNotifierProvider<UsersNotifier, AsyncValue<List<AppUserModel>>>((ref) {
  return UsersNotifier(
    ref.watch(apiServiceProvider),
    ref.watch(socketServiceProvider),
  );
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
        tag: 'CHAT',
      );
    } else {
      AppLogger.w(
        'Peer public key not found — E2EE unavailable until peer logs in',
        tag: 'CHAT',
      );
    }

    _conversationId = await _db.getOrCreateConversation(peerId);
    AppLogger.d('Conversation ready: $_conversationId', tag: 'CHAT');

    // ⚠️ Subscribe BEFORE loading from DB to avoid missing events that fire
    // while we're awaiting the initial DB read (race-condition prevention).
    _msgSub?.cancel();
    _msgSub = _socket.processedMessageStream
        .where((senderId) => senderId == peerId)
        .listen((_) => _refreshFromDb());
    AppLogger.d('processedMessageStream subscribed ✓', tag: 'CHAT');

    // Load existing messages from local DB into UI state
    await _refreshFromDb();

    await _db.clearUnread(_conversationId!);
    AppLogger.i('Chat initialized ✓', tag: 'CHAT');
  }

  Future<void> _refreshFromDb() async {
    if (_conversationId == null) return;
    AppLogger.d('Refreshing UI from DB for conv:$_conversationId', tag: 'CHAT');
    final msgs = await _db.getMessages(_conversationId!);
    // Sort by the original send timestamp so pending messages from
    // offline senders appear in the correct chronological position.
    final sorted = msgs.map((r) => ChatMessage.fromDb(r)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = sorted;
    AppLogger.d('UI refreshed — ${sorted.length} messages', tag: 'CHAT');
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

    // Insert in timestamp order (not just append) so the list stays sorted
    // even if offline-queued messages from the peer were received first.
    final updatedState = [...state, msg]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = updatedState;
    AppLogger.v('Message added to UI state (status: sending)', tag: 'CHAT');
    await _saveMessageToDb(msg);

    try {
      AppLogger.d('Relaying message via socket...', tag: 'CHAT');
      final serverAck = await _socket.sendMessage(msg.toSocketJson());
      // Server ACK means "message received by relay server" only.
      // "delivered" here means server forwarded to recipient's socket
      // (which may still be a stale/dead socket — not a real device receipt).
      // We always set status to 'sent' here; true 'delivered' arrives later
      // via the message:status socket event when the recipient device acks.
      const newStatus = MessageStatus.sent;
      AppLogger.i(
        'Message $msgId → server:$serverAck (status: sent)',
        tag: 'CHAT',
      );
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
          .map(
            (m) => m.id == msgId ? m.copyWith(status: MessageStatus.failed) : m,
          )
          .toList();
    }
  }

  Future<void> sendFile({
    required String filePath,
    required String fileName,
    required String fileType,
  }) async {
    if (_peerPublicKey == null) {
      AppLogger.w(
        'Cannot send file — peer public key not available',
        tag: 'CHAT',
      );
      return;
    }

    final msgId = const Uuid().v4();
    final messageType = _getMessageType(fileType);
    final sourceFile = File(filePath);
    final fileSize = await sourceFile.length();
    final sizeMb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
    AppLogger.i(
      'Sending file: $fileName ($sizeMb MB) type:$fileType id:$msgId',
      tag: 'CHAT',
    );

    final msg = ChatMessage(
      id: msgId,
      conversationId: _conversationId ?? '',
      senderId: myId,
      recipientId: peerId,
      type: messageType,
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
    );
    state = [...state, msg];

    try {
      AppLogger.d('Encrypting file...', tag: 'CHAT');

      // Write encrypted bytes to a temp file so upload streams from disk
      final tempDir = await getTemporaryDirectory();
      final tempEncPath = '${tempDir.path}/${const Uuid().v4()}.enc.tmp';

      final encrypted = await _enc.encryptFile(
        inputFilePath: filePath,
        outputFilePath: tempEncPath,
        recipientPublicKeyBase64: _peerPublicKey!,
      );

      AppLogger.d(
        'File encrypted ✓',
        tag: 'CHAT',
      );

      AppLogger.d('Uploading encrypted file to relay server...', tag: 'CHAT');
      final fileId = await _api.uploadEncryptedFile(
        encryptedFilePath: tempEncPath,
        recipientId: peerId,
        encryptedKey: encrypted.encryptedKeyBase64,
        iv: encrypted.ivBase64,
        fileType: fileType,
        originalName: fileName,
        messageId: msgId,
      );

      // Clean up temp encrypted file after successful upload
      await File(tempEncPath).delete().catchError((_) => File(tempEncPath));
      AppLogger.i('File uploaded ✓ fileId:$fileId', tag: 'CHAT');

      final msgWithFile = msg.copyWith(
        fileId: fileId,
        status: MessageStatus.sent,
      );

      // Copy original file to local storage (file → file, no extra RAM)
      AppLogger.d('Saving original file locally...', tag: 'CHAT');
      final localPath = await _api.saveFileFromPath(
        sourceFilePath: filePath,
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
          .map(
            (m) => m.id == msgId ? m.copyWith(status: MessageStatus.failed) : m,
          )
          .toList();
    }
  }

  Future<void> downloadFile(ChatMessage msg) async {
    if (msg.fileId == null || msg.localFilePath != null) return;

    AppLogger.i(
      'Downloading file: ${msg.fileName} (fileId:${msg.fileId})',
      tag: 'CHAT',
    );

    try {
      if (_peerPublicKey == null) {
        throw Exception(
          'Peer public key not loaded — cannot decrypt file for peer $peerId',
        );
      }

      AppLogger.d(
        'Fetching encrypted file + metadata from relay server...',
        tag: 'CHAT',
      );
      // Use downloadFileWithMeta to always get encryptedKey & iv from server
      // headers, which is the authoritative source (msg fields may be null if
      // the socket event didn't carry them or they weren't persisted to DB).
      final meta = await _api.downloadFileWithMeta(fileId: msg.fileId!);

      final encryptedKey = meta['encryptedKey'];
      final iv = meta['iv'];

      if (encryptedKey == null || encryptedKey.isEmpty) {
        throw Exception(
          'Server did not return encryptedKey header for file ${msg.fileId}',
        );
      }
      if (iv == null || iv.isEmpty) {
        throw Exception(
          'Server did not return iv header for file ${msg.fileId}',
        );
      }

      // meta['encryptedFilePath'] is a local temp file path streamed from server.
      final encryptedFilePath = meta['encryptedFilePath'] as String;

      AppLogger.d('Decrypting file...', tag: 'CHAT');
      final tempDir = await getTemporaryDirectory();
      final tempDecPath = '${tempDir.path}/${const Uuid().v4()}.dec.tmp';

      await _enc.decryptFile(
        inputFilePath: encryptedFilePath,
        outputFilePath: tempDecPath,
        ivBase64: iv,
        encryptedKeyBase64: encryptedKey,
        senderPublicKeyBase64: _peerPublicKey!,
      );

      // Delete temp encrypted file immediately after reading
      await File(encryptedFilePath)
          .delete()
          .catchError((_) => File(encryptedFilePath));

      AppLogger.d(
        'File decrypted ✓',
        tag: 'CHAT',
      );

      AppLogger.d('Saving file locally...', tag: 'CHAT');
      final localPath = await _api.saveFileFromPath(
        sourceFilePath: tempDecPath,
        fileName: msg.fileName ?? 'file',
        subFolder: _getFolderForType(msg.type),
      );

      // Clean up temp decrypted file
      await File(tempDecPath).delete().catchError((_) => File(tempDecPath));

      await _db.updateMessageLocalPath(msg.id, localPath);
      state = state
          .map((m) => m.id == msg.id ? m.copyWith(localFilePath: localPath) : m)
          .toList();
      AppLogger.i('File downloaded and saved: $localPath', tag: 'CHAT');
    } catch (e) {
      AppLogger.e(
        'Failed to download file ${msg.fileName}',
        tag: 'CHAT',
        error: e,
      );
    }
  }

  Future<void> _saveMessageToDb(ChatMessage msg) async {
    final convId = _conversationId ?? await _db.getOrCreateConversation(peerId);
    await _db.insertMessage(
      MessagesCompanion(
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
      ),
    );
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
    StateNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>((
  ref,
  peerId,
) {
  final auth = ref.watch(authProvider);
  return ChatNotifier(
    peerId: peerId,
    myId: auth.userId ?? '',
    api: ref.watch(apiServiceProvider),
    enc: ref.watch(encryptionServiceProvider),
    socket: ref.watch(socketServiceProvider),
    db: ref.watch(localDatabaseProvider),
  );
});
