# HANDOFF — WhisperFlow (private, lokale Wispr-Flow-Alternative)

**Stand:** 2026-07-05 · Session 2 (Implementierung via OpenCode/DeepSeek V4 Flash — abgeschlossen)

## Status: Implementierung fertig, manuelle QA steht aus

Alle 12 Tasks aus dem Implementierungsplan sind umgesetzt, committet und unabhängig verifiziert (`swift build`, `swift test` → 24/24 grün, `.app`-Bundle baut + signiert sauber). **Nächster Schritt ist die manuelle QA-Checkliste unten — das muss Peter selbst machen, kein Tool kann das automatisieren.**

## Wie gebaut wurde

- Implementiert von **OpenCode CLI mit `opencode/deepseek-v4-flash-free`** (kostenloses Modell, kein Login nötig), gesteuert von Claude über ein Treiber-Skript (`opencode run --continue --file <plan> --dangerously-skip-permissions`), das Task für Task aus dem Plan durchgereicht hat.
- Nach jedem Task hat Claude **unabhängig** `swift build`/`swift test` laufen lassen — nicht nur dem Selbst-Report des Agents vertraut.
- Plan: [docs/superpowers/plans/2026-07-02-whisperflow-implementation-plan.md](docs/superpowers/plans/2026-07-02-whisperflow-implementation-plan.md)
- Spec: [docs/superpowers/specs/2026-07-02-local-dictation-design.md](docs/superpowers/specs/2026-07-02-local-dictation-design.md)

## Was gebaut wurde

- **Swift Package** mit zwei Targets: `WhisperFlowCore` (testbare Bibliothek: Hotkey-State-Machine, CleanupService/Ollama-Client, TranscriptionEngine-Protokoll + echte Parakeet-v3-Anbindung via FluidAudio, AudioRecorder, TextInserter mit AX+Clipboard-Fallback, PipelineCoordinator als Orchestrator, PermissionsManager) und `WhisperFlowApp` (ausführbar: HotkeyListener per CGEventTap, MenuBarController mit Zustands-Icons, AppDelegate-Verdrahtung).
- **24 Unit-Tests**, alle grün, TDD durchgehend.
- **`WhisperFlow.app`-Bundle** via `scripts/build_app_bundle.sh` (Release-Build + Info.plist mit `LSUIElement`, ad-hoc signiert).
- Reale FluidAudio-API verwendet (`UnifiedAsrManager`, `loadModels()`, `transcribe()`, `cleanup()`) — abweichend von der API-Skizze im Plan, aber das war explizit vorgesehen (Task 5 verlangte, die echte API per `grep` im Package-Checkout zu verifizieren statt zu raten).

## Vorfälle während der Session (für's Protokoll)

1. **Bash-Bug im eigenen Treiber-Skript** (leeres Array + `set -u` bricht in macOS' bash 3.2) — sofort gefixt.
2. **Task 5:** OpenCode schrieb einen Fixture-Test mit Swift Testing (`@Test`), der hart fehlschlug, wenn `Tests/WhisperFlowCoreTests/Fixtures/*.wav` fehlt, statt sauber zu skippen (Plan wollte `XCTSkip`-Äquivalent). Der Korrektur-Versuch über eine neue `opencode run --continue`-Session **hing 2+ Tage fest** (0 Fortschritt, nur Leerlauf-Housekeeping-Logs, keine Netzwerkverbindung mehr offen) — Prozess gekillt, den 2-Zeilen-Fix (`guard ... else { return }`) hat Claude direkt selbst gemacht.
3. **Tasks 10–12:** OpenCode hat die eigentliche Arbeit jedes Mal korrekt erledigt und committet, aber den geforderten exakten `TASK_N_RESULT: PASS`-Marker nicht immer gedruckt (endete stattdessen mit einer Rückfrage an den Nutzer, oder räumte das gebaute `.app`-Bundle nach dem Commit selbst wieder auf). Das Treiber-Skript wurde entsprechend robuster gemacht (Fallback auf unabhängige Verifikation statt starrem Marker-Grep, `.gitignore` um `WhisperFlow.app/` ergänzt).

**Lesson:** Bei headless-CLI-Automatisierung mit einem Coding-Agent lieber auf eigene, unabhängige Verifikation (Build/Test/Bundle neu bauen) verlassen als auf exakte Text-Marker im Agent-Output — Marker-Matching ist brüchig, echte Builds/Tests sind der verlässliche Fallback.

## Nächste Schritte — manuelle QA (Peter, nicht automatisierbar)

Aus dem Plan, Task 12, manueller Teil:

- [ ] `WhisperFlow.app` nach `/Applications` verschieben, einmal starten (aktuell nur im Projektordner gebaut, noch nicht dort liegend — `./scripts/build_app_bundle.sh` erzeugt es neu)
- [ ] Mikrofon-Zugriff beim ersten Start erlauben
- [ ] Accessibility-Zugriff in Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen erteilen
- [ ] Rechte ⌥ halten, deutschen Satz mit Füllwörtern sprechen, loslassen — bereinigter Text sollte innerhalb ~1,5s am Cursor erscheinen
- [ ] Dasselbe auf Russisch
- [ ] Einfügen testen in: Notes, Mail, Chrome-Adressleiste, VS Code, Slack
- [ ] Ollama beenden (`killall ollama`) und erneut diktieren — roher (unbereinigter) Text sollte trotzdem erscheinen, kein Crash
- [ ] In ein Passwortfeld diktieren — kein unerwarteter Inhalt sollte erscheinen
- [ ] Rechte ⌥ unter 0,3s antippen — nichts sollte eingefügt werden

**Optional, nicht blockierend:** Echte Audio-Fixture-Dateien (`Tests/WhisperFlowCoreTests/Fixtures/de_sample.wav`, `ru_sample.wav`, ~5s, 16kHz mono) bereitstellen, damit der Parakeet-Integrationstest gegen echte Audiodaten statt nur zu skippen läuft.

## Gotchas (weiterhin relevant)

- **FluidAudio/Parakeet:** `.v3` verwenden (Deutsch+Russisch), nicht `.v2` (English-only). Reale API: `UnifiedAsrManager(configuration:config:encoderPrecision:)`, `loadModels()`, `transcribe(_:)`, `cleanup()` — nicht die im Plan skizzierte `AsrModels.downloadAndLoad`-API, die es in der installierten FluidAudio-Version (0.15.4) so nicht gibt.
- **AX-Einfügen scheitert** in Google Docs, manchen Electron-Apps und sicheren Feldern → Clipboard-Fallback ist Pflicht (bereits implementiert in `TextInserter.swift`).
- App braucht **kein App Sandbox**, Mikrofon- + Accessibility-Permission, ad-hoc Signing reicht lokal (bereits so gebaut).
- Ollama läuft lokal auf Port 11434 mit `qwen3:4b` — Setup-Skript: `scripts/setup_ollama.sh`.
