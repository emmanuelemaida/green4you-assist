import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client HTTP per le API v2 del modulo Kairos "assistenza_remota" (Fase 4).
/// Contratti dal playbook E2E-SMOKE-TEST-FASE-4.md.
class Green4YouApi {
  static const String base =
      'https://crm.green4you.cloud/kairos/modules/assistenza_remota/api/v2';

  static Uri _u(String path) => Uri.parse('$base/$path');

  static Map<String, String> _json([String? deviceToken]) => {
        'Content-Type': 'application/json',
        if (deviceToken != null) 'X-Device-Token': deviceToken,
      };

  // ---------------------------------------------------------------------------
  // Registrazione dispositivo (§4.1)
  // ---------------------------------------------------------------------------

  /// 1a. L'app chiede un nonce monouso (TTL 5 min). Ritorna il nonce.
  static Future<String> generaNonce({
    required String peerId,
    required String hostname,
    required String sistemaOperativo,
    required String versioneApp,
  }) async {
    final r = await http.post(
      _u('registra-dispositivo/genera-nonce.php'),
      headers: _json(),
      body: jsonEncode({
        'peer_id_rustdesk_dispositivo': peerId,
        'hostname': hostname,
        'sistema_operativo': sistemaOperativo,
        'versione_app': versioneApp,
      }),
    );
    return (jsonDecode(r.body) as Map<String, dynamic>)['nonce'] as String;
  }

  /// 1c. Dopo che l'utente ha confermato nel browser, l'app preleva (UNA volta)
  /// device_token + password permanente. Ritorna null se il nonce non è ancora
  /// confermato / già consumato.
  static Future<Map<String, dynamic>?> recuperaCredenziali(String nonce) async {
    final r = await http
        .get(_u('registra-dispositivo/recupera-credenziali.php?nonce=$nonce'));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    return j is Map<String, dynamic> ? j : null;
  }

  // ---------------------------------------------------------------------------
  // Richiesta di assistenza (§4.2 / §4.3)
  // ---------------------------------------------------------------------------

  /// Collaboratore registrato. Ritorna {richiesta_id, richiesta_token}.
  static Future<Map<String, dynamic>> richiediAssistenza({
    required String deviceToken,
    String? note,
  }) async {
    final r = await http.post(
      _u('richiedi-assistenza.php'),
      headers: _json(deviceToken),
      body: jsonEncode({'note_collaboratore': note ?? ''}),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Collaboratore non registrato (anonima). Ritorna {richiesta_id, richiesta_token}.
  static Future<Map<String, dynamic>> richiediAssistenzaAnonima({
    required String peerId,
    required String hostname,
    required String sistemaOperativo,
    required String versioneApp,
    String? note,
  }) async {
    final r = await http.post(
      _u('richiedi-assistenza-anonima.php'),
      headers: _json(),
      body: jsonEncode({
        'peer_id_rustdesk_dispositivo': peerId,
        'hostname': hostname,
        'sistema_operativo': sistemaOperativo,
        'versione_app': versioneApp,
        'note_collaboratore': note ?? '',
      }),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Polling stato. Ritorna la mappa completa:
  /// {stato, admin_nome, ts_inizio_sessione, durata_secondi, ts_fine_sessione}.
  /// stato ∈ in_attesa | attiva | completata | annullata.
  static Future<Map<String, dynamic>> statoRichiesta(
      String richiestaToken) async {
    final r =
        await http.get(_u('stato-richiesta.php?richiesta_token=$richiestaToken'));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Annulla una richiesta in_attesa.
  static Future<void> annullaRichiesta(String richiestaToken) async {
    await http.post(
      _u('annulla-richiesta.php'),
      headers: _json(),
      body: jsonEncode({'richiesta_token': richiestaToken}),
    );
  }

  // ---------------------------------------------------------------------------
  // Lato admin — deep-link connect (§6.10.1)
  // ---------------------------------------------------------------------------

  /// L'app admin, ricevuto il deep-link connect, scambia il session_token opaco
  /// con le credenziali del target. Ritorna:
  /// {target_peer_id_rustdesk, password_target, collaboratore_nome, session_id_correlazione_uuid}.
  static Future<Map<String, dynamic>> prelevaCredenzialiSessione({
    required String deviceToken,
    required String sessionToken,
  }) async {
    final r = await http.post(
      _u('admin/preleva-credenziali-sessione.php'),
      headers: _json(deviceToken),
      body: jsonEncode({'session_token': sessionToken}),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
