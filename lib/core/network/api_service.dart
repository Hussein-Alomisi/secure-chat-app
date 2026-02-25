import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
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

  /// Upload an encrypted file to the relay server
  /// Returns fileId assigned by server
  Future<String> uploadEncryptedFile({
    required Uint8List encryptedBytes,
    required String recipientId,
    required String encryptedKey,
    required String iv,
    required String fileType,
    required String originalName,
    required String messageId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        encryptedBytes,
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

    final response = await _dio.post(
      '/files/upload',
      data: formData,
      onSendProgress: onProgress,
    );

    return response.data['fileId'] as String;
  }

  /// Download an encrypted file from the relay server
  /// Returns local path of saved encrypted file
  Future<Uint8List> downloadEncryptedFile({
    required String fileId,
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _dio.get<List<int>>(
      '/files/download/$fileId',
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgress,
    );

    return Uint8List.fromList(response.data!);
  }

  /// Get encrypted AES key and IV from download response headers
  Future<Map<String, String>> downloadFileWithMeta({
    required String fileId,
  }) async {
    final response = await _dio.get<List<int>>(
      '/files/download/$fileId',
      options: Options(responseType: ResponseType.bytes),
    );

    final headers = response.headers;
    return {
      'encryptedKey': headers.value('x-encrypted-key') ?? '',
      'iv': headers.value('x-iv') ?? '',
      'fileType': headers.value('x-file-type') ?? 'application/octet-stream',
      'originalName':
          Uri.decodeComponent(headers.value('x-original-name') ?? 'file'),
      'messageId': headers.value('x-message-id') ?? '',
      'bytes': String.fromCharCodes(response.data!),
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
}
