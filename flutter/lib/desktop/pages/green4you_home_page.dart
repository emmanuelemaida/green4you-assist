import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/common.dart' show connect;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/green4you_api.dart';
import 'package:flutter_hbb/models/green4you_store.dart';

// Home page "appliance" di Green4You Assist (Fase 4 §7.1).
// PROTOTIPO UI: stati e dati sono stub locali; i bottoni puntano a callback
// noop con TODO. Il cablaggio alle API /api/v2/* arriva quando il backend
// Kairos è pronto. Il motore RustDesk (ID, connessione, sessione) non è toccato.

/// Verde ufficiale Green4You — la foglia del marchio (#4BA078), più sobrio del
/// lime #71dd37 del brand book web. Abbinato al teal scuro #1E3C43 della "G".
const Color kGreen4You = Color(0xFF4BA078);
const Color kGreen4YouDark = Color(0xFF1E3C43);

/// Un passo della mini-guida "Come funziona" (carosello §guida interna).
class _GuideStep {
  final IconData icon;
  final String title;
  final String text;
  const _GuideStep(this.icon, this.title, this.text);
}

const List<_GuideStep> _guideSteps = [
  _GuideStep(
    Icons.support_agent,
    'Hai un problema?',
    'Clicca "Richiedi assistenza": avvisi il supporto Green4You che ti serve aiuto.',
  ),
  _GuideStep(
    Icons.phone_in_talk,
    'Tieni il telefono a portata',
    'Un amministratore ti contatta per capire cosa non va.',
  ),
  _GuideStep(
    Icons.desktop_windows,
    'L\'amministratore si collega',
    'Vede il tuo schermo per aiutarti dal vivo. Un banner verde ti mostra sempre quando la sessione è attiva.',
  ),
  _GuideStep(
    Icons.verified_user,
    'Sei sempre tu al controllo',
    'Nessuno entra senza la tua richiesta, e puoi terminare la sessione quando vuoi.',
  ),
];

/// Le 5 schermate mutuamente esclusive della spec §7.1.
enum ApplianceState {
  unregistered, // A — manca device_token
  idle, // B — registrato, nessuna richiesta
  requesting, // C — richiesta inviata, in attesa
  sessionActive, // D — admin connesso
  anonymousIdentifying, // E — sessione anonima in identificazione
}

class Green4YouHomePage extends StatefulWidget {
  const Green4YouHomePage({Key? key}) : super(key: key);

  @override
  State<Green4YouHomePage> createState() => _Green4YouHomePageState();
}

class _Green4YouHomePageState extends State<Green4YouHomePage> {
  ApplianceState _state = ApplianceState.idle;
  String _userName = '';
  String _adminName = '';
  String? _peerId;
  String? _richiestaToken;
  bool _wasAnonymous = false;
  bool _busy = false;
  DateTime? _requestSentAt;
  int _timeoutSeconds = 900; // da ts_scadenza/timeout_secondi della risposta
  Timer? _pollTimer; // polling stato-richiesta / recupera-credenziali
  Timer? _tick; // refresh del countdown in schermata C
  bool _registering = false; // polling registrazione in corso (schermata A)
  int _regSecondsLeft = 600; // countdown conferma registrazione (dal 202)
  String? _registrationUrl; // URL conferma col nonce, riapribile dopo il login Kairos
  bool _errorVisible = false; // evita dialog d'errore impilati

  // --- Lato admin (UI adattiva per ruolo, v4131) ---
  bool _isAdmin = false; // utente_kairos.is_admin del device registrato
  List<Map<String, dynamic>> _queue = []; // richieste in attesa da accettare
  Timer? _queueTimer; // polling coda assistenza (5s)
  int? _assistingId; // richiesta_id per cui si sta avviando la sessione

  static const String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tick?.cancel();
    _queueTimer?.cancel();
    super.dispose();
  }

  /// Stato iniziale: B se registrato (device_token in Keychain), altrimenti A.
  /// Se l'utente è admin, avvia anche il polling della coda assistenza.
  Future<void> _init() async {
    final peerId = await bind.mainGetMyId();
    final registered = await Green4YouStore.isRegistered();
    final name = await Green4YouStore.userName();
    final isAdmin = await Green4YouStore.isAdmin();
    if (!mounted) return;
    setState(() {
      _peerId = peerId;
      _userName = name ?? '';
      _isAdmin = isAdmin;
      _state = registered ? ApplianceState.idle : ApplianceState.unregistered;
    });
    if (registered && isAdmin) _startQueuePolling();
  }

  /// Restituisce l'ID RustDesk (9-10 cifre) generato dal core. Dopo un'installazione
  /// fresca il core potrebbe non averlo ancora caricato all'avvio, quindi la lettura
  /// in _init() torna stringa vuota e _peerId resterebbe vuoto per tutta la sessione,
  /// facendo fallire genera-nonce / richiesta-anonima con HTTP 400. Qui rileggiamo
  /// con qualche retry e aggiorniamo lo stato appena l'ID è disponibile.
  Future<String> _ensurePeerId() async {
    var id = _peerId ?? '';
    for (var i = 0; id.isEmpty && i < 12; i++) {
      id = await bind.mainGetMyId();
      if (id.isEmpty) await Future.delayed(const Duration(milliseconds: 400));
    }
    if (id.isNotEmpty && id != (_peerId ?? '') && mounted) {
      setState(() => _peerId = id);
    }
    return id;
  }

  String get _hostname {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'PC';
    }
  }

  String get _so => Platform.operatingSystem; // macos | windows | linux

  /// Riga "Inviata X fa · scade tra Y min" della schermata C.
  String get _requestStatusLine {
    if (_requestSentAt == null) return '';
    final elapsed = DateTime.now().difference(_requestSentAt!);
    final agoMin = elapsed.inMinutes;
    final remaining = _timeoutSeconds - elapsed.inSeconds;
    final remMin = (remaining / 60).ceil().clamp(0, 999);
    final agoStr = agoMin <= 0 ? 'pochi secondi fa' : 'circa $agoMin min fa';
    return 'Inviata $agoStr · scade tra $remMin min';
  }

  @override
  Widget build(BuildContext context) {
    // Sfondo bianco pulito in light mode (preferenza Green4You); preserva il dark.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Theme.of(context).colorScheme.background : Colors.white;
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(child: Center(child: _buildBody(context))),
          if (_isInSession) _buildSessionBanner(context),
          // "Come funziona?" ancorato in basso al centro (schermate A e B).
          if (_state == ApplianceState.unregistered ||
              _state == ApplianceState.idle)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(child: _guideLink(context)),
            ),
        ],
      ),
    );
  }

  bool get _isInSession =>
      _state == ApplianceState.sessionActive ||
      _state == ApplianceState.anonymousIdentifying;

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case ApplianceState.unregistered:
        return _screenUnregistered(context);
      case ApplianceState.idle:
        // Admin: home a due sezioni (coda assistenza + richiedi assistenza).
        return _isAdmin ? _screenAdminHome(context) : _screenIdle(context);
      case ApplianceState.requesting:
        return _screenRequesting(context);
      case ApplianceState.sessionActive:
      case ApplianceState.anonymousIdentifying:
        return _screenSessionBackground(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Componenti riutilizzabili
  // ---------------------------------------------------------------------------

  Widget _logoHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo.png',
          width: 84,
          height: 84,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.support_agent, size: 84, color: kGreen4You),
        ),
        const SizedBox(height: 12),
        Text(
          'Green4You Assist',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? null
                    : kGreen4YouDark,
              ),
        ),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback onPressed,
      {IconData? icon}) {
    return SizedBox(
      width: 280,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen4You,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon ?? Icons.support_agent, size: 22),
        label: Text(label,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onPressed,
      {Color color = kGreen4You}) {
    return SizedBox(
      width: 280,
      height: 46,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.7)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  /// Link discreto "Come funziona?" che apre il carosello guida.
  Widget _guideLink(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.help_outline, size: 16),
      label: const Text('Come funziona?'),
      style: TextButton.styleFrom(foregroundColor: kGreen4You),
      onPressed: () => _showGuide(context),
    );
  }

  void _showGuide(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _GuideDialog(),
    );
  }

  // ---------------------------------------------------------------------------
  // (A) Non registrato
  // ---------------------------------------------------------------------------
  Widget _screenUnregistered(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logoHeader(context),
        const SizedBox(height: 28),
        if (_registering) ...[
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(kGreen4You)),
          ),
          const SizedBox(height: 18),
          Text('In attesa di conferma nel browser…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'Per registrare questo PC devi essere connesso a Kairos.\n'
            'Se il browser ti ha chiesto di accedere, fai login e poi premi '
            '"Riapri la pagina di conferma".\n'
            'Scade tra ${(_regSecondsLeft / 60).ceil()} min.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 18),
          _primaryButton('Riapri la pagina di conferma', _reopenRegistration,
              icon: Icons.open_in_browser),
          const SizedBox(height: 10),
          _outlineButton('Annulla', _onCancelRegistration,
              color: Colors.redAccent),
        ] else ...[
          Text('Questo PC non è ancora associato a un account.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 28),
          _primaryButton('Richiedi assistenza', _onRequestAssistance),
          const SizedBox(height: 12),
          _outlineButton('Registra questo PC', _onRegisterDevice),
        ],
        const SizedBox(height: 24),
        Text(
          'Versione 1.0.0',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // (B) Registrato, idle
  // ---------------------------------------------------------------------------
  Widget _screenIdle(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logoHeader(context),
        const SizedBox(height: 24),
        Text(_userName.isEmpty ? 'Ciao 👋' : 'Ciao $_userName 👋',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text('Hai bisogno di assistenza?',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 28),
        _primaryButton('Richiedi assistenza', _onRequestAssistance),
        const SizedBox(height: 16),
        TextButton.icon(
          icon: const Icon(Icons.settings, size: 16),
          label: const Text('Impostazioni'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
          onPressed: _onOpenSettings,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // (B-admin) Home admin: coda assistenza + richiedi assistenza
  // ---------------------------------------------------------------------------
  Widget _screenAdminHome(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _logoHeader(context),
              const SizedBox(height: 18),
              Text(_userName.isEmpty ? 'Ciao 👋' : 'Ciao $_userName 👋',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 24),
              // --- Sezione coda assistenza ---
              Row(
                children: [
                  const Icon(Icons.support_agent, size: 20, color: kGreen4You),
                  const SizedBox(width: 8),
                  Text('Coda assistenza',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? null : kGreen4YouDark)),
                  const Spacer(),
                  if (_queue.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: kGreen4You,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_queue.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_queue.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text('Nessuna richiesta in attesa.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey)),
                )
              else
                ..._queue.map((r) => _queueCard(context, r)),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              // --- Sezione richiedi assistenza (anche l'admin può chiedere) ---
              Text('Hai bisogno di assistenza tu?',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              _primaryButton('Richiedi assistenza', _onRequestAssistance),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Impostazioni'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                onPressed: _onOpenSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card di una richiesta in coda con i dati del collaboratore e il bottone
  /// "Assisti" (disabilitato/spinner mentre si avvia un'altra sessione).
  Widget _queueCard(BuildContext context, Map<String, dynamic> r) {
    final id = r['richiesta_id'] as int?;
    // Contratto v4132: campi piatti (collaboratore_nome, nota_collaboratore).
    // Fallback alle vecchie forme (utente.nome_da_mostrare, note_collaboratore)
    // per robustezza verso payload più datati.
    final utente = r['utente'];
    final nome = (r['collaboratore_nome'] ??
            (utente is Map ? utente['nome_da_mostrare'] : null)) as String?;
    final hostname = (r['hostname'] as String?)?.trim();
    final so = (r['sistema_operativo'] as String?)?.trim();
    final nota =
        ((r['nota_collaboratore'] ?? r['note_collaboratore']) as String?)
            ?.trim();
    final attesa = r['secondi_attesa'];
    final attesaStr = (attesa is int && attesa > 0)
        ? (attesa < 60 ? '${attesa}s fa' : '${(attesa / 60).floor()} min fa')
        : null;
    final thisBusy = _assistingId == id;
    final otherBusy = _assistingId != null && !thisBusy;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome?.trim().isNotEmpty == true ? nome!.trim() : 'Collaboratore',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  if (hostname?.isNotEmpty == true ||
                      so?.isNotEmpty == true ||
                      attesaStr != null)
                    Text(
                      [
                        if (hostname?.isNotEmpty == true) hostname,
                        if (so?.isNotEmpty == true) so,
                        if (attesaStr != null) attesaStr,
                      ].join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  if (nota?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(nota!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen4You,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: thisBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Icon(Icons.login, size: 18),
                label: const Text('Assisti'),
                onPressed:
                    (id == null || thisBusy || otherBusy) ? null : () => _onAssist(id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // (C) Richiesta inviata, in attesa
  // ---------------------------------------------------------------------------
  Widget _screenRequesting(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logoHeader(context),
        const SizedBox(height: 28),
        Text('Richiesta inviata.',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text('Un amministratore ti contatterà a breve.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(kGreen4You)),
        ),
        const SizedBox(height: 24),
        _outlineButton('Annulla richiesta', _onCancelRequest,
            color: Colors.redAccent),
        const SizedBox(height: 14),
        Text(_requestStatusLine,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // (D/E) sfondo dietro al banner di sessione
  // ---------------------------------------------------------------------------
  Widget _screenSessionBackground(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logoHeader(context),
        const SizedBox(height: 20),
        Text('Assistenza in corso',
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildSessionBanner(BuildContext context) {
    final isAnon = _state == ApplianceState.anonymousIdentifying;
    final bannerColor = isAnon ? const Color(0xFFE6A700) : kGreen4You;
    final text = isAnon
        ? 'Sessione in corso — l\'amministratore sta identificando l\'utente'
        : 'Sessione in corso con $_adminName';
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: bannerColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Termina sessione'),
                onPressed: _onEndSession,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Callback (PROTOTIPO: per ora navigano tra gli stati; niente API reali)
  // ---------------------------------------------------------------------------
  /// Richiedi assistenza — da B (registrato) o A (anonima). La scelta dipende
  /// dalla presenza del device_token in Keychain.
  Future<void> _onRequestAssistance() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final token = await Green4YouStore.deviceToken();
      Map<String, dynamic> res;
      if (token != null && token.isNotEmpty) {
        res = await Green4YouApi.richiediAssistenza(deviceToken: token);
        _wasAnonymous = false;
      } else {
        final peerId = await _ensurePeerId();
        if (peerId.isEmpty) {
          _showError(
              'ID dispositivo non ancora pronto.\n\nAttendi qualche secondo e riprova.');
          return;
        }
        res = await Green4YouApi.richiediAssistenzaAnonima(
          peerId: peerId,
          hostname: _hostname,
          sistemaOperativo: _so,
          versioneApp: _appVersion,
        );
        _wasAnonymous = true;
      }
      _richiestaToken = res['richiesta_token'] as String?;
      _requestSentAt = DateTime.now();
      final t = res['timeout_secondi'];
      if (t is int) _timeoutSeconds = t;
      if (_richiestaToken == null) {
        _showError('Risposta inattesa dal server.');
        return;
      }
      setState(() => _state = ApplianceState.requesting);
      _startPolling();
      _startTick();
    } catch (e) {
      _showError('Impossibile inviare la richiesta.\n\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Registra questo PC (§4.1): genera nonce, apre il browser sulla pagina di
  /// conferma Kairos, poi fa polling di recupera-credenziali finché l'utente
  /// conferma; salva device_token+password+nome in Keychain.
  /// Registra questo PC: genera nonce, apre il browser, poi POLLING PRIMARIO di
  /// recupera-credenziali (il deep-link è solo un acceleratore opzionale, non
  /// affidabile per utenti non tecnici). Retry sempre consentito.
  Future<void> _onRegisterDevice() async {
    _pollTimer?.cancel();
    setState(() {
      _registering = true;
      _regSecondsLeft = 600;
    });
    try {
      final peerId = await _ensurePeerId();
      if (peerId.isEmpty) {
        if (mounted) setState(() => _registering = false);
        _showError(
            'ID dispositivo non ancora pronto.\n\nAttendi qualche secondo e riprova.');
        return;
      }
      final nonce = await Green4YouApi.generaNonce(
        peerId: peerId,
        hostname: _hostname,
        sistemaOperativo: _so,
        versioneApp: _appVersion,
      );
      final url =
          'https://crm.green4you.cloud/kairos/modules/assistenza_remota/registra-dispositivo.php?nonce=$nonce';
      _registrationUrl = url;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _pollRegistration(nonce);
    } catch (e) {
      _showError('Registrazione non riuscita.\n\n$e');
      if (mounted) setState(() => _registering = false);
    }
  }

  /// Riapre nel browser la stessa pagina di conferma (stesso nonce). Utile quando
  /// l'utente non era loggato su Kairos: il primo tentativo lo manda al login e lo
  /// lascia sulla dashboard senza tornare alla conferma; rifatto il login, riaprire
  /// questo URL mostra direttamente la conferma e il polling già attivo completa.
  Future<void> _reopenRegistration() async {
    final url = _registrationUrl;
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // se il browser non si apre, l'utente può comunque riprovare manualmente
    }
  }

  void _onCancelRegistration() {
    _pollTimer?.cancel();
    setState(() => _registering = false);
  }

  void _pollRegistration(String nonce) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      RecuperaResult res;
      try {
        res = await Green4YouApi.recuperaCredenziali(nonce);
      } catch (_) {
        return; // rete: riprova al prossimo tick
      }
      if (!mounted) return;
      switch (res.stato) {
        case 'pending':
          setState(() =>
              _regSecondsLeft = res.secondiAllaScadenza ?? _regSecondsLeft);
          break;
        case 'confirmed':
          t.cancel();
          final creds = res.creds;
          if (creds == null || creds['device_token'] == null) {
            setState(() => _registering = false);
            _showError('Risposta inattesa dal server.');
            return;
          }
          try {
            final utente = creds['utente_kairos'];
            final name =
                utente is Map ? utente['nome_da_mostrare'] as String? : null;
            final isAdmin =
                utente is Map ? utente['is_admin'] == true : false;
            // is_developer salvato ma non usato in UI oggi (risposta #004).
            final isDeveloper =
                utente is Map ? utente['is_developer'] == true : false;
            // Rotazione token (device già registrato): sovrascrive il vecchio.
            await Green4YouStore.saveCredentials(
              deviceToken: creds['device_token'] as String,
              password: creds['password_permanente_cliente'] as String?,
              userName: name,
              isAdmin: isAdmin,
              isDeveloper: isDeveloper,
            );
            if (!mounted) return;
            setState(() {
              _userName = name ?? '';
              _isAdmin = isAdmin;
              _registering = false;
              _state = ApplianceState.idle;
            });
            if (isAdmin) _startQueuePolling();
          } catch (e) {
            setState(() => _registering = false);
            _showError('Salvataggio credenziali (Keychain): $e');
          }
          break;
        case 'expired':
        default:
          t.cancel();
          setState(() => _registering = false);
          _showError(
              'Registrazione non completata o scaduta. Riprova; se persiste, contatta l\'amministratore.');
          break;
      }
    });
  }

  Future<void> _onCancelRequest() async {
    _pollTimer?.cancel();
    _tick?.cancel();
    final token = _richiestaToken;
    if (token != null) {
      try {
        await Green4YouApi.annullaRichiesta(token);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _state =
        _wasAnonymous ? ApplianceState.unregistered : ApplianceState.idle);
  }

  /// Polling stato richiesta (§4.2): in_attesa -> C, accettata/attiva -> D,
  /// stati terminali -> torna a B/A.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (t) async {
      final token = _richiestaToken;
      if (token == null) {
        t.cancel();
        return;
      }
      Map<String, dynamic> s;
      try {
        s = await Green4YouApi.statoRichiesta(token);
      } catch (_) {
        return;
      }
      if (!mounted) return;
      final stato = s['stato'] as String?;
      final adminNome = s['admin_nome'] as String?;
      switch (stato) {
        case 'in_attesa':
          break;
        case 'accettata':
        case 'attiva':
          setState(() {
            _adminName = (adminNome != null && adminNome.isNotEmpty)
                ? adminNome
                : 'un amministratore';
            _state = ApplianceState.sessionActive;
          });
          break;
        case 'completata':
        case 'rifiutata':
        case 'timeout':
        case 'annullata':
        case 'errore':
          t.cancel();
          _tick?.cancel();
          setState(() => _state = _wasAnonymous
              ? ApplianceState.unregistered
              : ApplianceState.idle);
          break;
      }
    });
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == ApplianceState.requesting) setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // Lato admin: coda assistenza (polling ogni 5s) e accettazione richieste
  // ---------------------------------------------------------------------------

  /// Polling della coda richieste in attesa (§6.10). Aggiorna _queue; errori di
  /// rete silenziosi (riprova al tick successivo), come gli altri polling.
  void _startQueuePolling() {
    _queueTimer?.cancel();
    _refreshQueue(); // primo fetch immediato
    _queueTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshQueue();
    });
  }

  Future<void> _refreshQueue() async {
    final token = await Green4YouStore.deviceToken();
    if (token == null || token.isEmpty) return;
    try {
      final list = await Green4YouApi.richiesteInAttesa(token);
      if (!mounted) return;
      setState(() => _queue = list);
    } catch (_) {
      // rete: riprova al prossimo tick
    }
  }

  /// L'admin accetta una richiesta: avvia-sessione → preleva-credenziali →
  /// connessione RustDesk verso il target. Chiude il loop E2E.
  Future<void> _onAssist(int richiestaId) async {
    if (_assistingId != null) return;
    setState(() => _assistingId = richiestaId);
    try {
      final token = await Green4YouStore.deviceToken();
      if (token == null || token.isEmpty) {
        _showError('Device non registrato: impossibile accettare.');
        return;
      }
      final sessione = await Green4YouApi.avviaSessione(
        deviceToken: token,
        richiestaId: richiestaId,
      );
      final sessionToken = sessione['session_token'] as String?;
      if (sessionToken == null || sessionToken.isEmpty) {
        _showError('Risposta inattesa da avvia-sessione.');
        return;
      }
      final creds = await Green4YouApi.prelevaCredenzialiSessione(
        deviceToken: token,
        sessionToken: sessionToken,
      );
      final targetId = creds['target_peer_id_rustdesk'] as String?;
      final targetPwd = creds['password_target'] as String?;
      if (targetId == null || targetId.isEmpty) {
        _showError('Credenziali del target mancanti nella risposta.');
        return;
      }
      if (!mounted) return;
      // Avvia la sessione RustDesk in uscita verso il collaboratore. La sessione
      // si apre in una finestra dedicata; la coda admin resta attiva.
      connect(context, targetId,
          password: targetPwd, isSharedPassword: targetPwd != null);
      _refreshQueue();
    } catch (e) {
      _showError('Impossibile avviare l\'assistenza.\n\n$e');
    } finally {
      if (mounted) setState(() => _assistingId = null);
    }
  }

  void _onOpenSettings() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Impostazioni'),
        content: const Text('Green4You Assist 1.0.0'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Green4YouStore.clear();
              _queueTimer?.cancel();
              if (!mounted) return;
              setState(() {
                _userName = '';
                _isAdmin = false;
                _queue = [];
                _state = ApplianceState.unregistered;
              });
            },
            child: const Text('Esci da questo account',
                style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  void _onEndSession() {
    // TODO(Fase 2): chiudere realmente la connessione RustDesk in entrata.
    _pollTimer?.cancel();
    setState(() => _state =
        _wasAnonymous ? ApplianceState.unregistered : ApplianceState.idle);
  }

  /// Errore PERSISTENTE, leggibile e copiabile (per inoltrarlo a un admin).
  /// Niente SnackBar che lampeggia e sparisce.
  void _showError(String msg) {
    if (!mounted || _errorVisible) return;
    _errorVisible = true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
        title: const Text('Si è verificato un problema'),
        content: SizedBox(
          width: 340,
          child: SelectableText(
            msg,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copia'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: msg));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Errore copiato negli appunti'),
                      duration: Duration(seconds: 1)),
                );
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    ).then((_) => _errorVisible = false);
  }
}

/// Carosello guida "Come funziona" — 4 card scorrevoli con pallini e bottone.
class _GuideDialog extends StatefulWidget {
  const _GuideDialog();

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _guideSteps.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? Theme.of(context).colorScheme.surface : Colors.white;
    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 330,
        height: 400,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                child: const Text('Salta'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _guideSteps.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _buildCard(context, _guideSteps[i]),
              ),
            ),
            _buildDots(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen4You,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _next,
                  child: Text(_isLast ? 'Ho capito' : 'Avanti',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, _GuideStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: kGreen4You,
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 22),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? null
                      : kGreen4YouDark,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            step.text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600], height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_guideSteps.length, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? kGreen4You : Colors.grey.withOpacity(0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
