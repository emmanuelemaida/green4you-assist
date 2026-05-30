import 'dart:convert';
import 'package:http/http.dart' as http;

/// Esito del polling di recupera-credenziali (HTTP 200/202/410).
class RecuperaResult {
  /// 'confirmed' (creds pronte) | 'pending' (in attesa conferma) | 'expired'.
  final String stato;
  final Map<String, dynamic>? creds;
  final int? secondiAllaScadenza;
  const RecuperaResult(this.stato, {this.creds, this.secondiAllaScadenza});
}

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

  /// Lancia un errore descrittivo (status + body del server) se non è 2xx,
  /// così il messaggio mostrato all'utente è leggibile/copiabile per un admin.
  static void _checkOk(http.Response r, String op) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String detail = r.body;
    try {
      final j = jsonDecode(r.body);
      if (j is Map && (j['errore'] ?? j['messaggio'] ?? j['message']) != null) {
        detail = '${j['errore'] ?? j['messaggio'] ?? j['message']}';
      }
    } catch (_) {}
    throw '$op: HTTP ${r.statusCode}\n$detail';
  }

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
    _checkOk(r, 'genera-nonce');
    return (jsonDecode(r.body) as Map<String, dynamic>)['nonce'] as String;
  }

  /// 1c. Polling post-conferma. Distingue i 3 stati HTTP del backend v4128:
  /// 200 = confermato (creds), 202 = pending (in attesa conferma browser),
  /// 410 = scaduto/consumato/inesistente (molla).
  static Future<RecuperaResult> recuperaCredenziali(String nonce) async {
    final r = await http
        .get(_u('registra-dispositivo/recupera-credenziali.php?nonce=$nonce'));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body);
      return RecuperaResult('confirmed',
          creds: j is Map<String, dynamic> ? j : null);
    } else if (r.statusCode == 202) {
      int? sec;
      try {
        sec = (jsonDecode(r.body) as Map<String, dynamic>)[
            'secondi_alla_scadenza_nonce'] as int?;
      } catch (_) {}
      return RecuperaResult('pending', secondiAllaScadenza: sec);
    }
    return const RecuperaResult('expired'); // 410 o altro
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
    _checkOk(r, 'richiedi-assistenza');
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
    _checkOk(r, 'richiedi-assistenza-anonima');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Polling stato. Ritorna la mappa completa:
  /// {stato, admin_nome, ts_inizio_sessione, durata_secondi, ts_fine_sessione}.
  /// stato ∈ in_attesa | attiva | completata | annullata.
  static Future<Map<String, dynamic>> statoRichiesta(
      String richiestaToken) async {
    final r =
        await http.get(_u('stato-richiesta.php?richiesta_token=$richiestaToken'));
    _checkOk(r, 'stato-richiesta');
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
  // Lato admin — coda assistenza (§6.10)
  // ---------------------------------------------------------------------------

  /// Coda delle richieste in attesa che l'admin può accettare. Ritorna la lista
  /// (eventualmente vuota) dal campo `richieste`. Ogni elemento (contratto E2E):
  /// {richiesta_id, tipo_richiesta, utente:{nome_da_mostrare}, hostname,
  ///  note_collaboratore, ts}.
  static Future<List<Map<String, dynamic>>> richiesteInAttesa(
      String deviceToken) async {
    final r = await http.get(
      _u('admin/richieste-in-attesa.php'),
      headers: _json(deviceToken),
    );
    _checkOk(r, 'richieste-in-attesa');
    final j = jsonDecode(r.body);
    final list = (j is Map ? j['richieste'] : j) as List<dynamic>?;
    return (list ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// L'admin avvia la sessione per una richiesta: il backend crea il binding e
  /// ritorna {session_token, deep_link}. Il session_token va poi scambiato con
  /// prelevaCredenzialiSessione per ottenere le credenziali del target.
  static Future<Map<String, dynamic>> avviaSessione({
    required String deviceToken,
    required int richiestaId,
  }) async {
    final r = await http.get(
      _u('admin/avvia-sessione.php?richiesta_id=$richiestaId&format=json'),
      headers: _json(deviceToken),
    );
    _checkOk(r, 'avvia-sessione');
    return jsonDecode(r.body) as Map<String, dynamic>;
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
    _checkOk(r, 'preleva-credenziali-sessione');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
