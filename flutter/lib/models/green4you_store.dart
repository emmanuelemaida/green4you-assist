import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage cifrato OS-native per le credenziali Green4You Assist:
/// Keychain su macOS, DPAPI/Credential Manager su Windows (spec §7.4).
/// Mai plaintext, mai SharedPreferences/localStorage.
class Green4YouStore {
  // useDataProtectionKeyChain:false → usa il keychain legacy (login). Su app
  // NON sandboxed funziona senza l'entitlement keychain-access-groups, che la
  // firma ad-hoc non ha: evita errSecMissingEntitlement (-34018).
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  static const String _kDeviceToken = 'g4y_device_token';
  static const String _kPassword = 'g4y_password_permanente';
  static const String _kUserName = 'g4y_nome_da_mostrare';
  // Ruolo dell'utente associato al device (da utente_kairos.is_admin, v4131).
  // Determina se la home mostra anche la sezione "Coda assistenza" (admin).
  static const String _kIsAdmin = 'g4y_is_admin';
  // Flag developer (utente_kairos.is_developer, v4131). Oggi NON cambia UI né
  // permessi (decisione Emmanuele, risposta #004): lo conserviamo per sbloccare
  // strumenti diagnostici/feature dev in futuro senza tornare a chiedere al server.
  static const String _kIsDeveloper = 'g4y_is_developer';

  /// device_token presente => dispositivo registrato (schermata B vs A).
  static Future<String?> deviceToken() => _storage.read(key: _kDeviceToken);

  static Future<bool> isRegistered() async =>
      (await deviceToken())?.isNotEmpty ?? false;

  /// Nome da mostrare ("Ciao [nome]"), da utente_kairos.nome_da_mostrare.
  static Future<String?> userName() => _storage.read(key: _kUserName);

  /// true se l'utente associato a questo device è un admin Green4You: la home
  /// mostra allora anche la sezione "Coda assistenza". Default false (anche per
  /// device registrati prima di v4131, finché non rigenerano le credenziali).
  static Future<bool> isAdmin() async =>
      (await _storage.read(key: _kIsAdmin)) == 'true';

  /// true se l'utente è un developer (vedi nota su _kIsDeveloper). Oggi non
  /// usato dalla UI; esposto per usi futuri.
  static Future<bool> isDeveloper() async =>
      (await _storage.read(key: _kIsDeveloper)) == 'true';

  static Future<void> saveCredentials({
    required String deviceToken,
    String? password,
    String? userName,
    bool? isAdmin,
    bool? isDeveloper,
  }) async {
    await _storage.write(key: _kDeviceToken, value: deviceToken);
    if (password != null && password.isNotEmpty) {
      await _storage.write(key: _kPassword, value: password);
    }
    if (userName != null && userName.isNotEmpty) {
      await _storage.write(key: _kUserName, value: userName);
    }
    if (isAdmin != null) {
      await _storage.write(key: _kIsAdmin, value: isAdmin ? 'true' : 'false');
    }
    if (isDeveloper != null) {
      await _storage.write(
          key: _kIsDeveloper, value: isDeveloper ? 'true' : 'false');
    }
  }

  static Future<String?> password() => _storage.read(key: _kPassword);

  /// "Esci da questo account": rimuove le credenziali locali.
  static Future<void> clear() async {
    await _storage.delete(key: _kDeviceToken);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kUserName);
    await _storage.delete(key: _kIsAdmin);
    await _storage.delete(key: _kIsDeveloper);
  }
}
