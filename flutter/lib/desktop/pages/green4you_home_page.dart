import 'package:flutter/material.dart';

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
  // --- Stub (verranno da Keychain/device_token + API) ---
  ApplianceState _state = ApplianceState.idle;
  final String _userName = 'Marco'; // da registrazione §4.1
  final String _adminName = 'Luca'; // da deep-link connect §7.3
  final int _sentMinutesAgo = 1;
  final int _expiresInMinutes = 14;

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
        Text('Ciao $_userName 👋',
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
        Text('Inviata $_sentMinutesAgo min fa · scade tra $_expiresInMinutes min',
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
  void _onRequestAssistance() {
    // TODO(API): POST /api/v2/richiedi-assistenza.php (o -anonima per stato A)
    setState(() => _state = ApplianceState.requesting);
  }

  void _onRegisterDevice() {
    // TODO(API+deeplink): apri browser su URL §6.2, attendi green4youassist://registered
    debugPrint('[Green4You] Avvio flusso registrazione (§4.1) — stub');
  }

  void _onCancelRequest() {
    // TODO(API): POST /api/v2/annulla-richiesta.php
    setState(() => _state = ApplianceState.idle);
  }

  void _onOpenSettings() {
    // TODO: dialog Impostazioni [Esci da questo account] [Quit] [About]
    debugPrint('[Green4You] Apertura impostazioni — stub');
  }

  void _onEndSession() {
    // TODO: chiudi la sessione RustDesk attiva
    setState(() => _state = ApplianceState.idle);
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
