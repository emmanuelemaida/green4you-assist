import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
    super.dispose();
  }

  /// Stato iniziale: B se registrato (device_token in Keychain), altrimenti A.
  Future<void> _init() async {
    final peerId = await bind.mainGetMyId();
    final registered = await Green4YouStore.isRegistered();
    final name = await Green4YouStore.userName();
    if (!mounted) return;
    setState(() {
      _peerId = peerId;
      _userName = name ?? '';
      _state = registered ? ApplianceState.idle : ApplianceState.unregistered;
    });
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
          _buildDevSwitcher(context), // solo prototipo
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
        return _screenIdle(context);
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
        Text('Questo PC non è ancora associato a un account.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 28),
        _primaryButton('Richiedi assistenza', _onRequestAssistance),
        const SizedBox(height: 12),
        _outlineButton('Registra questo PC', _onRegisterDevice),
        const SizedBox(height: 24),
        Text(
          'Versione 1.0.0 — sorgenti: github.com/emmanuelemaida/green4you-assist',
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
        res = await Green4YouApi.richiediAssistenzaAnonima(
          peerId: _peerId ?? '',
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
    } catch (_) {
      _showError('Impossibile inviare la richiesta. Controlla la connessione.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Registra questo PC (§4.1): genera nonce, apre il browser sulla pagina di
  /// conferma Kairos, poi fa polling di recupera-credenziali finché l'utente
  /// conferma; salva device_token+password+nome in Keychain.
  Future<void> _onRegisterDevice() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final nonce = await Green4YouApi.generaNonce(
        peerId: _peerId ?? '',
        hostname: _hostname,
        sistemaOperativo: _so,
        versioneApp: _appVersion,
      );
      final url =
          'https://crm.green4you.cloud/kairos/modules/assistenza_remota/registra-dispositivo.php?nonce=$nonce';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _pollRegistration(nonce);
    } catch (_) {
      _showError('Registrazione non riuscita. Riprova.');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pollRegistration(String nonce) {
    _pollTimer?.cancel();
    int attempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      attempts++;
      if (attempts > 100) {
        // il nonce scade in ~5 min: smetti di attendere
        t.cancel();
        if (mounted) setState(() => _busy = false);
        return;
      }
      Map<String, dynamic>? creds;
      try {
        creds = await Green4YouApi.recuperaCredenziali(nonce);
      } catch (_) {
        return;
      }
      if (creds != null && creds['device_token'] != null) {
        t.cancel();
        final utente = creds['utente_kairos'];
        final name =
            utente is Map ? utente['nome_da_mostrare'] as String? : null;
        await Green4YouStore.saveCredentials(
          deviceToken: creds['device_token'] as String,
          password: creds['password_permanente_cliente'] as String?,
          userName: name,
        );
        if (!mounted) return;
        setState(() {
          _userName = name ?? '';
          _state = ApplianceState.idle;
          _busy = false;
        });
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
              if (!mounted) return;
              setState(() {
                _userName = '';
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

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ---------------------------------------------------------------------------
  // Pannellino DEV per ciclare gli stati (RIMUOVERE prima del rilascio)
  // ---------------------------------------------------------------------------
  Widget _buildDevSwitcher(BuildContext context) {
    Widget chip(String label, ApplianceState s) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            onTap: () => setState(() => _state = s),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _state == s ? kGreen4You : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: _state == s ? Colors.white : Colors.black54)),
            ),
          ),
        );
    return Positioned(
      bottom: 6,
      right: 6,
      child: Opacity(
        opacity: 0.75,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DEV ',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            chip('A', ApplianceState.unregistered),
            chip('B', ApplianceState.idle),
            chip('C', ApplianceState.requesting),
            chip('D', ApplianceState.sessionActive),
            chip('E', ApplianceState.anonymousIdentifying),
          ],
        ),
      ),
    );
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
