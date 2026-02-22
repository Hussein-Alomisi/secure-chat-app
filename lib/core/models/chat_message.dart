import 'dart:convert';

enum MessageType { text, image, video, file }
enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final MessageType type;

  // Text messages
  final String? encryptedContent;
  final String? iv;
  final String? decryptedText; // in-memory only, never stored decrypted

  // File messages
  final String? fileId;
  final String? localFilePath;
  final String? fileName;
  final String? fileType;
  final int? fileSize;
  final String? encryptedKey;

  final MessageStatus status;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.type,
    this.encryptedContent,
    this.iv,
    this.decryptedText,
    this.fileId,
    this.localFilePath,
    this.fileName,
    this.fileType,
    this.fileSize,
    this.encryptedKey,
    required this.status,
    required this.timestamp,
  });

  bool get isFromMe => false; // Will be set with context

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['messageId'] as String,
      conversationId: '',
      senderId: json['senderId'] as String,
      recipientId: json['recipientId'] as String,
      type: _typeFromString(json['type'] as String? ?? 'text'),
      encryptedContent: json['encryptedContent'] as String?,
      iv: json['iv'] as String?,
      fileId: json['fileId'] as String?,
      fileName: json['originalName'] as String?,
      fileType: json['fileType'] as String?,
      encryptedKey: json['encryptedKey'] as String?,
      status: MessageStatus.delivered,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toSocketJson() {
    return {
      'messageId': id,
      'recipientId': recipientId,
      'type': type.name,
      if (encryptedContent != null) 'encryptedContent': encryptedContent,
      if (iv != null) 'iv': iv,
      if (fileId != null) 'fileId': fileId,
      if (encryptedKey != null) 'encryptedKey': encryptedKey,
      if (fileType != null) 'fileType': fileType,
      if (fileName != null) 'originalName': fileName,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  ChatMessage copyWith({
    MessageStatus? status,
    String? decryptedText,
    String? localFilePath,
    String? fileId,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      recipientId: recipientId,
      type: type,
      encryptedContent: encryptedContent,
      iv: iv,
      decryptedText: decryptedText ?? this.decryptedText,
      fileId: fileId ?? this.fileId,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
      encryptedKey: encryptedKey,
      status: status ?? this.status,
      timestamp: timestamp,
    );
  }

  static MessageType _typeFromString(String s) {
    switch (s) {
      case 'image': return MessageType.image;
      case 'video': return MessageType.video;
      case 'file': return MessageType.file;
      default: return MessageType.text;
    }
  }
}

class AppUserModel {
  final String id;
  final String name;
  final String avatarColor;
  final String? publicKey;
  final bool isOnline;
  final String? lastSeen;

  const AppUserModel({
    required this.id,
    required this.name,
    required this.avatarColor,
    this.publicKey,
    this.isOnline = false,
    this.lastSeen,
  });

  factory AppUserModel.fromJson(Map<String, dynamic> json) {
    return AppUserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarColor: json['avatarColor'] as String? ?? '#6C63FF',
      publicKey: json['publicKey'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(1, 2)).toUpperCase();
  }

  AppUserModel copyWith({bool? isOnline, String? lastSeen, String? publicKey}) {
    return AppUserModel(
      id: id,
      name: name,
      avatarColor: avatarColor,
      publicKey: publicKey ?? this.publicKey,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
