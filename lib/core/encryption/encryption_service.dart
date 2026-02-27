import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─── Top-level isolate functions ────────────────────────────────────────────
// These MUST be top-level (not instance methods) so they can run in Isolate.run

import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/stream/ctr.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha256.dart';

Future<Map<String, dynamic>> _isolateEncryptFileStream(
    Map<String, dynamic> args) async {
  final inputPath = args['inputPath'] as String;
  final outputPath = args['outputPath'] as String;
  final privateKeyBytes = args['privateKeyBytes'] as Uint8List;
  final recipientPubKeyBase64 = args['recipientPubKeyBase64'] as String;

  final x25519 = cryptography.X25519();
  final hkdf =
      cryptography.Hkdf(hmac: cryptography.Hmac.sha256(), outputLength: 32);

  // Rebuild key pair inside isolate
  final publicKey = await x25519.newKeyPairFromSeed(privateKeyBytes);
  final recipientPubKey = cryptography.SimplePublicKey(
    base64Decode(recipientPubKeyBase64),
    type: cryptography.KeyPairType.x25519,
  );

  // Derive shared key
  final sharedSecret = await x25519.sharedSecretKey(
    keyPair: publicKey,
    remotePublicKey: recipientPubKey,
  );
  final sharedAesGcmKey = await hkdf.deriveKey(
    secretKey: sharedSecret,
    nonce: Uint8List(32),
    info: Uint8List.fromList(utf8.encode('SecureChat-AES256GCM-v1')),
  );

  final random = cryptography.SecureRandom.safe;
  // Encrypt file with random key (AES-256 requires a 32-byte key)
  final fileKeyBytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    fileKeyBytes[i] = random.nextInt(256);
  }

  // AES-CTR uses 16-byte IV
  final iv = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    iv[i] = random.nextInt(256);
  }

  // Encrypt the file key itself with the shared key (using cryptography AES-GCM as before)
  final aesGcm = cryptography.AesGcm.with256bits();
  final keyBox = await aesGcm.encrypt(fileKeyBytes, secretKey: sharedAesGcmKey);
  final encryptedKeyBytes = Uint8List.fromList(
    keyBox.nonce + keyBox.cipherText + keyBox.mac.bytes,
  );

  // Set up PointyCastle AES-CTR
  final ctrParams = ParametersWithIV(KeyParameter(fileKeyBytes), iv);
  final cipher = CTRStreamCipher(AESEngine())..init(true, ctrParams);

  // Generate a random HMAC key for authentication
  final hmacKeyBytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    hmacKeyBytes[i] = random.nextInt(256);
  }
  // We append this HMAC key to the encrypted file bytes, encrypted itself with the AES fileKey
  final hmacAuth = HMac(SHA256Digest(), 64)..init(KeyParameter(hmacKeyBytes));

  final inputFile = File(inputPath);
  final outputFile = File(outputPath);
  final sink = outputFile.openWrite();

  // First 32 bytes of the file are the AES-encrypted HMAC key
  final encryptedHmacKey = cipher.process(hmacKeyBytes);
  sink.add(encryptedHmacKey);
  hmacAuth.update(encryptedHmacKey, 0, encryptedHmacKey.length);

  // Stream chunk by chunk
  final stream = inputFile.openRead();
  await for (final chunk in stream) {
    // Ensuring it's a list since Dart's process takes Uint8List
    final uint8Chunk = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    final encryptedChunk = cipher.process(uint8Chunk);
    sink.add(encryptedChunk);
    hmacAuth.update(encryptedChunk, 0, encryptedChunk.length);
  }

  // Calculate HMAC of the entire ciphertext
  final mac = Uint8List(32);
  hmacAuth.doFinal(mac, 0);

  // Append MAC at the end (32 bytes)
  sink.add(mac);

  await sink.flush();
  await sink.close();

  return {
    'encryptedFilePath': outputPath,
    'ivBase64': base64Encode(iv),
    'encryptedKeyBase64': base64Encode(encryptedKeyBytes),
    'isStreamed': true,
  };
}

Future<void> _isolateDecryptFileStream(Map<String, dynamic> args) async {
  final inputPath = args['inputPath'] as String;
  final outputPath = args['outputPath'] as String;
  final ivBase64 = args['ivBase64'] as String;
  final encryptedKeyBase64 = args['encryptedKeyBase64'] as String;
  final privateKeyBytes = args['privateKeyBytes'] as Uint8List;
  final senderPubKeyBase64 = args['senderPubKeyBase64'] as String;

  final x25519 = cryptography.X25519();
  final hkdf =
      cryptography.Hkdf(hmac: cryptography.Hmac.sha256(), outputLength: 32);

  // Rebuild key pair inside isolate
  final keyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
  final senderPubKey = cryptography.SimplePublicKey(
    base64Decode(senderPubKeyBase64),
    type: cryptography.KeyPairType.x25519,
  );

  // Derive shared key
  final sharedSecret = await x25519.sharedSecretKey(
    keyPair: keyPair,
    remotePublicKey: senderPubKey,
  );
  final sharedKey = await hkdf.deriveKey(
    secretKey: sharedSecret,
    nonce: Uint8List(32),
    info: Uint8List.fromList(utf8.encode('SecureChat-AES256GCM-v1')),
  );

  // Decrypt file key with shared key
  final encKeyBytes = base64Decode(encryptedKeyBase64);
  final keyNonce = encKeyBytes.sublist(0, 12);
  final keyCipherText = encKeyBytes.sublist(12, encKeyBytes.length - 16);
  final keyMac = cryptography.Mac(encKeyBytes.sublist(encKeyBytes.length - 16));
  final keyBox =
      cryptography.SecretBox(keyCipherText, nonce: keyNonce, mac: keyMac);

  final aesGcm = cryptography.AesGcm.with256bits();
  final fileKeyBytes = await aesGcm.decrypt(keyBox, secretKey: sharedKey);

  // Decrypt file with file key
  final iv = base64Decode(ivBase64);
  final ctrParams =
      ParametersWithIV(KeyParameter(Uint8List.fromList(fileKeyBytes)), iv);
  final cipher = CTRStreamCipher(AESEngine())..init(false, ctrParams);

  final inputFile = File(inputPath);
  final fileLength = await inputFile.length();

  // The file format is: [Encrypted Hmac Key: 32 bytes] + [Ciphertext] + [MAC: 32 bytes]
  if (fileLength < 64) {
    throw Exception('File too short to be valid encrypted data');
  }

  final randomAccessFile = await inputFile.open(mode: FileMode.read);

  // 1. Read the encrypted HMAC key
  final encHmacKey = await randomAccessFile.read(32);

  // 2. Read the MAC from the end of the file
  await randomAccessFile.setPosition(fileLength - 32);
  final storedMac = await randomAccessFile.read(32);

  // 3. Verify HMAC
  await randomAccessFile.setPosition(0);
  final hmacAuth = HMac(SHA256Digest(), 64);
  final hmacKey = cipher.process(encHmacKey);
  hmacAuth.init(KeyParameter(hmacKey));

  // Read and authenticate everything up to the MAC
  int bytesToAuth = fileLength - 32;
  while (bytesToAuth > 0) {
    final toRead = bytesToAuth > 65536 ? 65536 : bytesToAuth;
    final chunk = await randomAccessFile.read(toRead);
    hmacAuth.update(chunk, 0, chunk.length);
    bytesToAuth -= chunk.length;
  }

  final computedMac = Uint8List(32);
  hmacAuth.doFinal(computedMac, 0);

  bool isValid = true;
  for (var i = 0; i < 32; i++) {
    if (computedMac[i] != storedMac[i]) {
      isValid = false;
      break;
    }
  }
  if (!isValid) {
    await randomAccessFile.close();
    throw Exception(
        'HMAC authentication failed. The file is corrupt or tampered with.');
  }

  // 4. Decrypt the actual content to output file
  await randomAccessFile.setPosition(32);
  final outputFile = File(outputPath);
  final sink = outputFile.openWrite();

  int bytesToDecrypt = fileLength - 64; // Without Hmac Key(32) and Mac(32)
  while (bytesToDecrypt > 0) {
    final toRead = bytesToDecrypt > 65536 ? 65536 : bytesToDecrypt;
    final chunk = await randomAccessFile.read(toRead);
    final decryptedChunk = cipher.process(chunk);
    sink.add(decryptedChunk);
    bytesToDecrypt -= chunk.length;
  }

  await sink.flush();
  await sink.close();
  await randomAccessFile.close();
}

// ─── EncryptionService ──────────────────────────────────────────────────────

/// Handles all E2EE operations using X25519 + AES-256-GCM
///
/// Key Exchange Protocol:
///   1. Each user generates an X25519 key pair on first launch
///   2. Public key is registered with the server
///   3. To send a message: generate shared secret with recipient's public key
///   4. Derive AES-256-GCM key from shared secret using HKDF
///   5. Encrypt message with AES-256-GCM
class EncryptionService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const _privateKeyKey = 'sc_private_key_x25519';
  static const _publicKeyKey = 'sc_public_key_x25519';

  final _x25519 = cryptography.X25519();
  final _aesGcm = cryptography.AesGcm.with256bits();
  final _hkdf =
      cryptography.Hkdf(hmac: cryptography.Hmac.sha256(), outputLength: 32);

  cryptography.SimpleKeyPair? _keyPair;

  /// Initialize: load or generate X25519 key pair
  Future<void> initialize() async {
    final storedPrivate = await _storage.read(key: _privateKeyKey);
    final storedPublic = await _storage.read(key: _publicKeyKey);

    if (storedPrivate != null && storedPublic != null) {
      // Load existing key pair
      final privateBytes = base64Decode(storedPrivate);
      final publicBytes = base64Decode(storedPublic);

      _keyPair = cryptography.SimpleKeyPairData(
        privateBytes,
        publicKey: cryptography.SimplePublicKey(publicBytes,
            type: cryptography.KeyPairType.x25519),
        type: cryptography.KeyPairType.x25519,
      );
    } else {
      // Generate new key pair
      _keyPair = await _x25519.newKeyPair();

      final privateBytes = await _keyPair!.extractPrivateKeyBytes();
      final publicKey = await _keyPair!.extractPublicKey();
      final publicBytes = publicKey.bytes;

      await _storage.write(
        key: _privateKeyKey,
        value: base64Encode(privateBytes),
      );
      await _storage.write(
        key: _publicKeyKey,
        value: base64Encode(publicBytes),
      );
    }
  }

  /// Get local user's public key (base64) to register with server
  Future<String> getPublicKeyBase64() async {
    final pk = await _keyPair!.extractPublicKey();
    return base64Encode(pk.bytes);
  }

  /// Derive shared AES key from our private key + recipient's public key
  Future<cryptography.SecretKey> _deriveSharedKey(
      String recipientPublicKeyBase64) async {
    final recipientPubKeyBytes = base64Decode(recipientPublicKeyBase64);
    final recipientPublicKey = cryptography.SimplePublicKey(
      recipientPubKeyBytes,
      type: cryptography.KeyPairType.x25519,
    );

    // X25519 ECDH
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: recipientPublicKey,
    );

    // HKDF to derive AES-256 key
    final secretKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: Uint8List(32), // static nonce; real impl uses per-session nonce
      info: Uint8List.fromList(utf8.encode('SecureChat-AES256GCM-v1')),
    );

    return secretKey;
  }

  /// Encrypt a text message for a recipient
  /// Returns: { 'ciphertext': base64, 'iv': base64 }
  Future<Map<String, String>> encryptText({
    required String plaintext,
    required String recipientPublicKeyBase64,
  }) async {
    final aesKey = await _deriveSharedKey(recipientPublicKeyBase64);
    final secretBox = await _aesGcm.encryptString(
      plaintext,
      secretKey: aesKey,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText + secretBox.mac.bytes),
      'iv': base64Encode(secretBox.nonce),
    };
  }

  /// Decrypt a text message from a sender
  Future<String> decryptText({
    required String ciphertextBase64,
    required String ivBase64,
    required String senderPublicKeyBase64,
  }) async {
    final aesKey = await _deriveSharedKey(senderPublicKeyBase64);
    final rawBytes = base64Decode(ciphertextBase64);

    // Split ciphertext and MAC (last 16 bytes)
    final cipherText = rawBytes.sublist(0, rawBytes.length - 16);
    final mac = cryptography.Mac(rawBytes.sublist(rawBytes.length - 16));
    final nonce = base64Decode(ivBase64);

    final secretBox =
        cryptography.SecretBox(cipherText, nonce: nonce, mac: mac);
    final decrypted = await _aesGcm.decryptString(secretBox, secretKey: aesKey);
    return decrypted;
  }

  /// Encrypt a file in a background isolate using streams (UI stays responsive).
  Future<EncryptedFile> encryptFile({
    required String inputFilePath,
    required String outputFilePath,
    required String recipientPublicKeyBase64,
  }) async {
    final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();

    final result = await Isolate.run(() => _isolateEncryptFileStream({
          'inputPath': inputFilePath,
          'outputPath': outputFilePath,
          'privateKeyBytes': Uint8List.fromList(privateKeyBytes),
          'recipientPubKeyBase64': recipientPublicKeyBase64,
        }));

    return EncryptedFile(
      encryptedFilePath: result['encryptedFilePath']!,
      ivBase64: result['ivBase64']!,
      encryptedKeyBase64: result['encryptedKeyBase64']!,
      isStreamed: true,
    );
  }

  /// Decrypt a file in a background isolate using streams (UI stays responsive).
  Future<String> decryptFile({
    required String inputFilePath,
    required String outputFilePath,
    required String ivBase64,
    required String encryptedKeyBase64,
    required String senderPublicKeyBase64,
  }) async {
    final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();

    await Isolate.run(() => _isolateDecryptFileStream({
          'inputPath': inputFilePath,
          'outputPath': outputFilePath,
          'ivBase64': ivBase64,
          'encryptedKeyBase64': encryptedKeyBase64,
          'privateKeyBytes': Uint8List.fromList(privateKeyBytes),
          'senderPubKeyBase64': senderPublicKeyBase64,
        }));
    return outputFilePath;
  }
}

class EncryptedFile {
  final String encryptedFilePath;
  final String ivBase64;
  final String encryptedKeyBase64;
  final bool isStreamed;

  EncryptedFile({
    required this.encryptedFilePath,
    required this.ivBase64,
    required this.encryptedKeyBase64,
    this.isStreamed = false,
  });
}
