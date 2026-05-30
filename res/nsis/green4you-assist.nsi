; Installer NSIS per Green4You Assist (Windows).
; Installazione per-utente (HKCU, niente UAC): copia i file della build Flutter,
; crea i collegamenti, registra lo URL scheme green4youassist:// e l'uninstaller.
;
; Compilazione (in CI o locale):
;   makensis /DSRC_DIR=<cartella build> /DVERSION=<x.y.z> green4you-assist.nsi
; SRC_DIR deve contenere l'output di "flutter build windows" (rustdesk.exe, le
; DLL e la cartella data\). VERSION è la versione mostrata in Programmi installati.

Unicode true
SetCompressor /SOLID lzma

!ifndef SRC_DIR
  !error "SRC_DIR non definito: passare /DSRC_DIR=<cartella build Release>"
!endif
!ifndef VERSION
  !define VERSION "1.0.0"
!endif

!define APP_NAME      "Green4You Assist"
!define APP_EXE       "rustdesk.exe"          ; BINARY_NAME del fork (interno)
!define APP_SCHEME    "green4youassist"       ; deve combaciare con get_uri_prefix()
!define APP_PUBLISHER "Green4You"
!define APP_REGKEY    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

Name "${APP_NAME}"
OutFile "Green4You-Assist-${VERSION}-Setup.exe"
InstallDir "$LOCALAPPDATA\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_NAME}" "InstallDir"
RequestExecutionLevel user                    ; per-utente: nessun prompt UAC
ShowInstDetails show
ShowUnInstDetails show

; Icona installer/uninstaller: file dedicato accanto a questo script (generato
; da generate_app_icon.ps1). I path MUI_ICON sono relativi alla cartella del
; .nsi, quindi basta il nome file (NON anteporre ${__FILEDIR__}: NSIS lo
; risolve già da qui, raddoppierebbe in res\nsis\res\nsis\).
!define MUI_ICON   "green4you.ico"
!define MUI_UNICON "green4you.ico"

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Avvia ${APP_NAME}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Italian"
!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------------------
Section "Install"
  SetOutPath "$INSTDIR"
  ; Copia tutta la build Flutter (exe + DLL + data\).
  File /r "${SRC_DIR}\*.*"

  ; Collegamenti (Start Menu + Desktop) col nome di brand, puntano all'exe interno.
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut  "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut  "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; URL scheme green4youassist:// (per-utente, HKCU\Software\Classes).
  ; NB: green4youassist senza spazio — allineato a get_uri_prefix() lato Rust.
  WriteRegStr HKCU "Software\Classes\${APP_SCHEME}" "" "URL:${APP_NAME} Protocol"
  WriteRegStr HKCU "Software\Classes\${APP_SCHEME}" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\${APP_SCHEME}\DefaultIcon" "" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKCU "Software\Classes\${APP_SCHEME}\shell\open\command" "" '"$INSTDIR\${APP_EXE}" "%1"'

  ; Voce in "App e funzionalità" (ARP) + percorso installazione.
  WriteRegStr   HKCU "Software\${APP_NAME}" "InstallDir" "$INSTDIR"
  WriteRegStr   HKCU "${APP_REGKEY}" "DisplayName"     "${APP_NAME}"
  WriteRegStr   HKCU "${APP_REGKEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr   HKCU "${APP_REGKEY}" "Publisher"       "${APP_PUBLISHER}"
  WriteRegStr   HKCU "${APP_REGKEY}" "DisplayIcon"     "$INSTDIR\${APP_EXE},0"
  WriteRegStr   HKCU "${APP_REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKCU "${APP_REGKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "${APP_REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${APP_REGKEY}" "NoRepair" 1

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; ---------------------------------------------------------------------------
Section "Uninstall"
  ; Chiudi l'app se in esecuzione, poi rimuovi file e chiavi.
  ExecWait 'taskkill /F /IM "${APP_EXE}"'

  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  DeleteRegKey HKCU "Software\Classes\${APP_SCHEME}"
  DeleteRegKey HKCU "${APP_REGKEY}"
  DeleteRegKey HKCU "Software\${APP_NAME}"

  RMDir /r "$INSTDIR"
SectionEnd
