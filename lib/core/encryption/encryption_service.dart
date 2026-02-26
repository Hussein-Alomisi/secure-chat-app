import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─── Top-level isolate functions ────────────────────────────────────────────
// These MUST be top-level (not instance methods) so they can run in Isolate.run

Future<Map<String, Uint8List>> _isolateEncryptFile(
    Map<String, dynamic> args) async {
  final fileBytes = args['fileBytes'] as Uint8List;
  final privateKeyBytes = args['privateKeyBytes'] as Uint8List;
  final recipientPubKeyBase64 = args['recipientPubKeyBase64'] as String;

  final x25519 = X25519();
  final aesGcm = AesGcm.with256bits();
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // Rebuild key pair inside isolate
  final publicKey = await x25519.newKeyPairFromSeed(privateKeyBytes);
  final recipientPubKey = SimplePublicKey(
    base64Decode(recipientPubKeyBase64),
    type: KeyPairType.x25519,
  );

  // Derive shared key
  final sharedSecret = await x25519.sharedSecretKey(
    keyPair: publicKey,
    remotePublicKey: recipientPubKey,
  );
  final sharedKey = await hkdf.deriveKey(
    secretKey: sharedSecret,
    nonce: Uint8List(32),
    info: Uint8List.fromList(utf8.encode('SecureChat-AES256GCM-v1')),
  );

  // Encrypt file with random key
  final fileKey = await aesGcm.newSecretKey();
  final secretBox = await aesGcm.encrypt(fileBytes, secretKey: fileKey);
  final fileKeyBytes = await fileKey.extractBytes();
  final cipherBytes = Uint8List.fromList(
    secretBox.cipherText + secretBox.mac.bytes,
  );

  // Encrypt file key with shared key
  final keyBox = await aesGcm.encrypt(fileKeyBytes, secretKey: sharedKey);
  final encryptedKeyBytes = Uint8List.fromList(
    keyBox.nonce + keyBox.cipherText + keyBox.mac.bytes,
  );

  return {
    'encryptedBytes': cipherBytes,
    'iv': Uint8List.fromList(secretBox.nonce),
    'encryptedKey': encryptedKeyBytes,
  };
}

Future<Uint8List> _isolateDecryptFile(Map<String, dynamic> args) async {
  final encryptedBytes = args['encryptedBytes'] as Uint8List;
  final ivBase64 = args['ivBase64'] as String;
  final encryptedKeyBase64 = args['encryptedKeyBase64'] as String;
  final privateKeyBytes = args['privateKeyBytes'] as Uint8List;
  final senderPubKeyBase64 = args['senderPubKeyBase64'] as String;

  final x25519 = X25519();
  final aesGcm = AesGcm.with256bits();
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // Rebuild key pair inside isolate
  final keyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
  final senderPubKey = SimplePublicKey(
    base64Decode(senderPubKeyBase64),
    type: KeyPairType.x25519,
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

  // Decrypt file key
  final encKeyBytes = base64Decode(encryptedKeyBase64);
  final keyNonce = encKeyBytes.sublist(0, 12);
  final keyCipherText = encKeyBytes.sublist(12, encKeyBytes.length - 16);
  final keyMac = Mac(encKeyBytes.sublist(encKeyBytes.length - 16));
  final keyBox = SecretBox(keyCipherText, nonce: keyNonce, mac: keyMac);
  final fileKeyBytes = await aesGcm.decrypt(keyBox, secretKey: sharedKey);
  final fileKey = SecretKey(fileKeyBytes);

  // Decrypt file
  final iv = base64Decode(ivBase64);
  final cipherText = encryptedBytes.sublist(0, encryptedBytes.length - 16);
  final mac = Mac(encryptedBytes.sublist(encryptedBytes.length - 16));
  final fileBox = SecretBox(cipherText, nonce: iv, mac: mac);
  final decryptedBytes = await aesGcm.decrypt(fileBox, secretKey: fileKey);
  return Uint8List.fromList(decryptedBytes);
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

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _keyPair;

  /// Initialize: load or generate X25519 key pair
  Future<void> initialize() async {
    final storedPrivate = await _storage.read(key: _privateKeyKey);
    final storedPublic = await _storage.read(key: _publicKeyKey);

    if (storedPrivate != null && storedPublic != null) {
      // Load existing key pair
      final privateBytes = base64Decode(storedPrivate);
      final publicBytes = base64Decode(storedPublic);

      _keyPair = SimpleKeyPairData(
        privateBytes,
        publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
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
  Future<SecretKey> _deriveSharedKey(String recipientPublicKeyBase64) async {
    final recipientPubKeyBytes = base64Decode(recipientPublicKeyBase64);
    final recipientPublicKey = SimplePublicKey(
      recipientPubKeyBytes,
      type: KeyPairType.x25519,
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
    final mac = Mac(rawBytes.sublist(rawBytes.length - 16));
    final nonce = base64Decode(ivBase64);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final decrypted = await _aesGcm.decryptString(secretBox, secretKey: aesKey);
    return decrypted;
  }

  /// Encrypt a file in a background isolate (UI stays responsive).
  Future<EncryptedFile> encryptFile({
    required Uint8List fileBytes,
    required String recipientPublicKeyBase64,
  }) async {
    final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();

    final result = await Isolate.run(() => _isolateEncryptFile({
          'fileBytes': fileBytes,
          'privateKeyBytes': Uint8List.fromList(privateKeyBytes),
          'recipientPubKeyBase64': recipientPublicKeyBase64,
        }));

    return EncryptedFile(
      encryptedBytes: result['encryptedBytes']!,
      ivBase64: base64Encode(result['iv']!),
      encryptedKeyBase64: base64Encode(result['encryptedKey']!),
    );
  }

  /// Decrypt a file in a background isolate (UI stays responsive).
  Future<Uint8List> decryptFile({
    required Uint8List encryptedBytes,
    required String ivBase64,
    required String encryptedKeyBase64,
    required String senderPublicKeyBase64,
  }) async {
    final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();

    return Isolate.run(() => _isolateDecryptFile({
          'encryptedBytes': encryptedBytes,
          'ivBase64': ivBase64,
          'encryptedKeyBase64': encryptedKeyBase64,
          'privateKeyBytes': Uint8List.fromList(privateKeyBytes),
          'senderPubKeyBase64': senderPublicKeyBase64,
        }));
  }
}

class EncryptedFile {
  final Uint8List encryptedBytes;
  final String ivBase64;
  final String encryptedKeyBase64;

  EncryptedFile({
    required this.encryptedBytes,
    required this.ivBase64,
    required this.encryptedKeyBase64,
  });
}
