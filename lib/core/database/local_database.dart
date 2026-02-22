import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

// ─── Tables ───────────────────────────────────────────────────────────────────

class AppUsers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get avatarColor => text()();
  TextColumn get publicKey => text().nullable()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  TextColumn get lastSeen => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get peerId => text().references(AppUsers, #id)();
  TextColumn get lastMessagePreview => text().nullable()();
  TextColumn get lastMessageTime => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(Conversations, #id)();
  TextColumn get senderId => text()();
  TextColumn get recipientId => text()();
  TextColumn get type => text()(); // 'text' | 'image' | 'video' | 'file'
  TextColumn get encryptedContent => text().nullable()(); // for text messages
  TextColumn get iv => text().nullable()(); // AES IV, base64
  TextColumn get fileId => text().nullable()(); // server file ID after upload
  TextColumn get localFilePath => text().nullable()(); // local path after download
  TextColumn get fileName => text().nullable()();
  TextColumn get fileType => text().nullable()(); // MIME type
  IntColumn get fileSize => integer().nullable()();
  TextColumn get encryptedKey => text().nullable()(); // encrypted AES key for file
  TextColumn get status => text().withDefault(const Constant('sending'))();
  // 'sending' | 'sent' | 'delivered' | 'read' | 'failed'
  TextColumn get timestamp => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [AppUsers, Conversations, Messages])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'securechat_db');
  }

  // ── Users ──────────────────────────────────────────────────────────────────

  Future<void> upsertUser(AppUsersCompanion user) async {
    await into(appUsers).insertOnConflictUpdate(user);
  }

  Future<List<AppUser>> getAllUsers() => select(appUsers).get();

  Future<AppUser?> getUserById(String id) {
    return (select(appUsers)..where((u) => u.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> setUserOnlineStatus(String userId, bool isOnline, String? lastSeen) {
    return (update(appUsers)..where((u) => u.id.equals(userId))).write(
      AppUsersCompanion(
        isOnline: Value(isOnline),
        lastSeen: Value(lastSeen),
      ),
    );
  }

  // ── Conversations ──────────────────────────────────────────────────────────

  Future<List<Conversation>> getAllConversations() {
    return (select(conversations)
          ..orderBy([
            (c) => OrderingTerm(
                  expression: c.lastMessageTime,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  Stream<List<Conversation>> watchConversations() {
    return (select(conversations)
          ..orderBy([
            (c) => OrderingTerm(
                  expression: c.lastMessageTime,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  Future<Conversation?> getConversationByPeer(String peerId) {
    return (select(conversations)..where((c) => c.peerId.equals(peerId)))
        .getSingleOrNull();
  }

  Future<String> getOrCreateConversation(String peerId) async {
    final existing = await getConversationByPeer(peerId);
    if (existing != null) return existing.id;

    final id = 'conv_${peerId}';
    await into(conversations).insert(ConversationsCompanion(
      id: Value(id),
      peerId: Value(peerId),
    ));
    return id;
  }

  Future<void> updateConversationLastMessage(
    String conversationId,
    String preview,
    String timestamp,
  ) {
    return (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      lastMessagePreview: Value(preview),
      lastMessageTime: Value(timestamp),
    ));
  }

  Future<void> incrementUnread(String conversationId) {
    return customUpdate(
      'UPDATE conversations SET unread_count = unread_count + 1 WHERE id = ?',
      variables: [Variable.withString(conversationId)],
    );
  }

  Future<void> clearUnread(String conversationId) {
    return (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(const ConversationsCompanion(unreadCount: Value(0)));
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Stream<List<Message>> watchMessages(String conversationId) {
    return (select(messages)
          ..where((m) => m.conversationId.equals(conversationId))
          ..orderBy([
            (m) => OrderingTerm(expression: m.timestamp),
          ]))
        .watch();
  }

  Future<void> insertMessage(MessagesCompanion message) async {
    await into(messages).insertOnConflictUpdate(message);
  }

  Future<void> updateMessageStatus(String messageId, String status) {
    return (update(messages)..where((m) => m.id.equals(messageId)))
        .write(MessagesCompanion(status: Value(status)));
  }

  Future<void> updateMessageLocalPath(String messageId, String localPath) {
    return (update(messages)..where((m) => m.id.equals(messageId)))
        .write(MessagesCompanion(localFilePath: Value(localPath)));
  }

  Future<Message?> getMessageById(String id) {
    return (select(messages)..where((m) => m.id.equals(id))).getSingleOrNull();
  }
}
