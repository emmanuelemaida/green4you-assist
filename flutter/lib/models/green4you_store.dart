import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage cifrato OS-native per le credenziali Green4You Assist:
/// Keychain su macOS, DPAPI/Credential Manager su Windows (spec §7.4).
/// Mai plaintext, mai SharedPreferences/localStorage.
class Green4YouStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _kDeviceToken = 'g4y_device_token';
  static const String _kPassword = 'g4y_password_permanente';
  static const String _kUserName = 'g4y_nome_da_mostrare';

  /// device_token presente => dispositivo registrato (schermata B vs A).
  static Future<String?> deviceToken() => _storage.read(key: _kDeviceToken);

  static Future<bool> isRegistered() async =>
      (await deviceToken())?.isNotEmpty ?? false;

  /// Nome da mostrare ("Ciao [nome]"), da utente_kairos.nome_da_mostrare.
  static Future<String?> userName() => _storage.read(key: _kUserName);

  static Future<void> saveCredentials({
    required String deviceToken,
    String? password,
    String? userName,
  }) async {
    await _storage.write(key: _kDeviceToken, value: deviceToken);
    if (password != null && password.isNotEmpty) {
      await _storage.write(key: _kPassword, value: password);
    }
    if (userName != null && userName.isNotEmpty) {
      await _storage.write(key: _kUserName, value: userName);
    }
  }

  static Future<String?> password() => _storage.read(key: _kPassword);

  /// "Esci da questo account": rimuove le credenziali locali.
  static Future<void> clear() async {
    await _storage.delete(key: _kDeviceToken);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kUserName);
  }
}
