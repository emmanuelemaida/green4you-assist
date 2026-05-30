# Sviluppo 125 — Build Windows Green4You Assist — Log di lavoro

> Tenuto da Claude Windows. Branch: `feature/fase4-ui-shell`. Un solo file, aggiornato in continuazione.
> Obiettivo: rendere la build Windows **buildabile e funzionante** (la macchina admin che accetta). Su macOS funziona gia' (Claude Mac).

## Stato numerazione commit

- Ultimo commit Claude Mac: **v18** (Branding macOS Fase 4).
- Prossimo numero da usare: vedi "Ultimo v usato" qui sotto. I numeri DEVONO essere consecutivi.
- **Ultimo v usato: (nessuno ancora da parte di Claude Windows — si parte da v19)**
- Autore commit: Emmanuele Maida <emmanuele.maida@gmail.com>. NIENTE Co-Authored-By, niente emoji (convenzione repo).

## Decisioni architetturali (da Claude server, risposta #001)

- UI admin = dentro la stessa app, adattiva per ruolo (la scrivo io, Claude Windows).
- Backend v4131 attivo: `recupera-credenziali.php` ritorna `is_admin`/`is_developer` in `utente_kairos`.
- Installer = NSIS. Build = GitHub Actions (toolchain locale assente).
- Deep-link `green4youassist://connect` = opzionale, rimandabile.
- Bug registry windows.rs = lo fixo io (codice fork = mio dominio). Scelta: Opzione B (derivo `ext` da get_uri_prefix, non tocco APP_NAME).

## Lavoro svolto

### F1 — Branding Windows (FATTO, non ancora compilato)
- `flutter/windows/runner/Runner.rc`: CompanyName/ProductName/FileDescription/OriginalFilename/Copyright -> Green4You Assist.
- `flutter/windows/runner/resources/app_icon.ico`: rigenerato dal logo verde `flutter/assets/logo.png` (7 risoluzioni 16-256, verificato a vista). Sorgenti condivisi `res/icon.png`/`res/mac-icon.png` restano logo blu RustDesk (Mac fu brandizzato sostituendo direttamente AppIcon.icns).
- `flutter/windows/generate_app_icon.ps1`: nuovo script PowerShell 5.1 riusabile per rigenerare l'ico.

### Fix bug registry URL scheme (FATTO, non ancora compilato)
- `src/platform/windows.rs`: in `get_after_install`, `get_before_uninstall`, `update_install_option` ora `ext = get_uri_prefix().trim_end_matches("://")` (= "green4youassist") invece di `app_name.to_lowercase()` (= "green4you assist", con spazio, errato). Rimossa una var app_name divenuta inutilizzata in update_install_option.

### Lato admin — UI che accetta (FATTO, non ancora compilato)
- `flutter/lib/models/green4you_store.dart`: aggiunto `is_admin` (save/read/clear).
- `flutter/lib/models/green4you_api.dart`: aggiunti `richiesteInAttesa(deviceToken)` e `avviaSessione(deviceToken, richiestaId)`. Contratti dal playbook E2E.
- `flutter/lib/desktop/pages/green4you_home_page.dart`: import `connect`; se utente admin la home mostra "Coda assistenza" (polling 5s) + bottone Assisti (avvia-sessione -> preleva-credenziali -> connect verso target). Sezione "Richiedi assistenza" mantenuta. DEV switcher ancora presente (rimuovere prima del rilascio).

## DA FARE
- [ ] F3: workflow GitHub Actions Windows (adattato da .github/workflows/flutter-build.yml) — l'UNICO compilatore disponibile.
- [ ] F3: template NSIS per l'installer.
- [ ] Validare compilazione Flutter + Rust in CI (nulla e' stato compilato in locale: niente toolchain).
- [ ] Primo giro E2E: Mac chiede, Windows accetta.

## Note / rischi
- Niente toolchain di build in locale (no flutter/rust/VS C++/NSIS/gh; solo git+python). Tutto si valida in CI.
- CI RustDesk di riferimento: windows-2022, Flutter 3.24.5, Rust 1.75, LLVM 15.0.6, vcpkg 120deac..., triplet x64-windows-static, engine Flutter custom rustdesk/engine, `python build.py --flutter` -> `flutter/build/windows/x64/runner/Release`.
