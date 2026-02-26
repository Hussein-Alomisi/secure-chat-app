import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// How long to allow for upload/download: supports up to 4.2 GB files.
const Duration _kFileTransferTimeout = Duration(hours: 12);

class ApiService {
  // static const String _serverUrl = String.fromEnvironment(
  //   'SERVER_URL',
  //   defaultValue: 'http://192.168.0.183:3000',
  // );
  static const String _serverUrl = 'http://18.219.24.19:3000';

  late final Dio _dio;
  String? _jwtToken;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: '$_serverUrl/api',
      connectTimeout: const Duration(seconds: 30),
      // Upload/download of up to 4.2 GB needs generous timeouts.
      // These apply per-request and are overridden per-call where needed.
      receiveTimeout: _kFileTransferTimeout,
      sendTimeout: _kFileTransferTimeout,
    ));

    // Interceptor: add Bearer token to all requests
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_jwtToken != null) {
          options.headers['Authorization'] = 'Bearer $_jwtToken';
        }
        handler.next(options);
      },
      onError: (err, handler) {
        debugPrint('[API] Error: ${err.message}');
        handler.next(err);
      },
    ));
  }

  void setToken(String token) {
    _jwtToken = token;
  }

  void clearToken() {
    _jwtToken = null;
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login({
    required String userId,
    required String password,
    required String publicKey,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'userId': userId,
      'password': password,
      'publicKey': publicKey,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _dio.get('/auth/users');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['users'] as List);
  }

  Future<String?> getUserPublicKey(String userId) async {
    try {
      final response = await _dio.get('/auth/publicKey/$userId');
      return response.data['publicKey'] as String?;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> updatePublicKey(String publicKey) async {
    await _dio.post('/auth/publicKey', data: {'publicKey': publicKey});
  }

  // ── File Upload / Download ─────────────────────────────────────────────────

  /// Upload an encrypted file to the relay server using streaming (disk → network).
  /// [encryptedFilePath] must be the path of the already-encrypted file on disk.
  /// Returns the fileId assigned by server.
  Future<String> uploadEncryptedFile({
    required String encryptedFilePath, // ← path on disk, NOT bytes in memory
    required String recipientId,
    required String encryptedKey,
    required String iv,
    required String fileType,
    required String originalName,
    required String messageId,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(encryptedFilePath);
    final fileLength = await file.length();

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        encryptedFilePath,
        filename: '${const Uuid().v4()}.enc',
        contentType: DioMediaType.parse('application/octet-stream'),
      ),
      'recipientId': recipientId,
      'encryptedKey': encryptedKey,
      'iv': iv,
      'fileType': fileType,
      'originalName': originalName,
      'messageId': messageId,
    });

    debugPrint(
        '[API] Uploading ${(fileLength / 1024 / 1024).toStringAsFixed(1)} MB from disk');

    final response = await _dio.post(
      '/files/upload',
      data: formData,
      cancelToken: cancelToken,
      options: Options(
        sendTimeout: _kFileTransferTimeout,
        receiveTimeout: const Duration(seconds: 30),
      ),
      onSendProgress: onProgress,
    );

    return response.data['fileId'] as String;
  }

  /// Download an encrypted file from the relay server, streaming it directly
  /// to a temp file on disk. Returns metadata + the local path of the saved file.
  /// The CALLER is responsible for deleting the temp file after decryption.
  Future<Map<String, dynamic>> downloadFileWithMeta({
    required String fileId,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final savePath = '${tempDir.path}/${const Uuid().v4()}.enc.tmp';

    debugPrint('[API] Streaming download → $savePath');

    final response = await _dio.download(
      '/files/download/$fileId',
      savePath,
      cancelToken: cancelToken,
      options: Options(
        receiveTimeout: _kFileTransferTimeout,
        headers: {
          if (_jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
        },
      ),
      onReceiveProgress: onProgress,
    );

    final headers = response.headers;
    return {
      'encryptedKey': headers.value('x-encrypted-key') ?? '',
      'iv': headers.value('x-iv') ?? '',
      'fileType': headers.value('x-file-type') ?? 'application/octet-stream',
      'originalName':
          Uri.decodeComponent(headers.value('x-original-name') ?? 'file'),
      'messageId': headers.value('x-message-id') ?? '',
      'encryptedFilePath': savePath, // ← path on disk, NOT bytes in memory
    };
  }

  // ── Local File Saving ──────────────────────────────────────────────────────

  Future<String> saveFileLocally({
    required Uint8List bytes,
    required String fileName,
    required String subFolder,
  }) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/securechat/$subFolder');
    await dir.create(recursive: true);

    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Copy a file from [sourceFilePath] to local storage without loading
  /// the entire file into memory — suitable for large files.
  Future<String> saveFileFromPath({
    required String sourceFilePath,
    required String fileName,
    required String subFolder,
  }) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/securechat/$subFolder');
    await dir.create(recursive: true);

    final destPath = '${dir.path}/$fileName';
    await File(sourceFilePath).copy(destPath);
    return destPath;
  }
}
