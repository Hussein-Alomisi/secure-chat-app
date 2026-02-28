import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../utils/app_logger.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _biometricEnabledKey = 'biometric_enabled';
  static const _biometricUserIdKey = 'biometric_user_id';
  static const _biometricPasswordKey = 'biometric_password';

  /// Checks if the device supports biometric auth and has hardware available.
  Future<bool> isBiometricAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (e) {
      AppLogger.e('Error checking biometric availability',
          tag: 'BIOMETRIC', error: e);
      return false;
    }
  }

  /// Checks if the user has previously enabled biometric login for the app.
  Future<bool> isBiometricEnabled() async {
    final enabled = await _storage.read(key: _biometricEnabledKey);
    return enabled == 'true';
  }

  /// Prompts the user to authenticate using biometrics.
  Future<bool> authenticate(String localizedReason) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true, // Force biometric or pin
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      AppLogger.e('Error during biometric authentication',
          tag: 'BIOMETRIC', error: e);
      return false;
    }
  }

  /// Saves credentials securely and marks biometric as enabled.
  Future<void> enableBiometric(String userId, String password) async {
    await _storage.write(key: _biometricUserIdKey, value: userId);
    await _storage.write(key: _biometricPasswordKey, value: password);
    await _storage.write(key: _biometricEnabledKey, value: 'true');
    AppLogger.i('Biometric login enabled for user $userId', tag: 'BIOMETRIC');
  }

  /// Removes biometric credentials.
  Future<void> disableBiometric() async {
    await _storage.delete(key: _biometricUserIdKey);
    await _storage.delete(key: _biometricPasswordKey);
    await _storage.write(key: _biometricEnabledKey, value: 'false');
    AppLogger.i('Biometric login disabled', tag: 'BIOMETRIC');
  }

  /// Retrieves saved credentials if biometric is enabled.
  Future<Map<String, String>?> getSavedCredentials() async {
    final enabled = await isBiometricEnabled();
    if (!enabled) return null;

    final userId = await _storage.read(key: _biometricUserIdKey);
    final password = await _storage.read(key: _biometricPasswordKey);

    if (userId != null && password != null) {
      return {'userId': userId, 'password': password};
    }
    return null;
  }
}
