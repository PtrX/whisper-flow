# WhisperFlow — Private, lokale Wispr-Flow-Alternative (Design)

**Datum:** 2026-07-02
**Status:** Genehmigt von Peter
**Ziel:** Systemweites Push-to-talk-Diktat auf dem Mac, das zu 100 % lokal läuft — kein Audio, kein Text, kein Screenshot verlässt die Maschine.

## Hintergrund

Wispr Flow bietet: Hotkey halten → sprechen → polierter Text erscheint am Cursor in jeder App. Die Verarbeitung (ASR + LLM-Cleanup) läuft aber in der Cloud (OpenAI/Meta-Server), inkl. periodischer Screenshots des aktiven Fensters; ~800 MB RAM idle. WhisperFlow repliziert die Kern-UX vollständig on-device.

## Entscheidungen (mit Peter geklärt)

| Frage | Entscheidung |
|---|---|
| Scope | Transkription + LLM-Cleanup (Füllwörter, Grammatik, Formatierung) |
| Sprachen | Deutsch + Russisch, Auto-Erkennung |
| Stack | Natives Swift-Menüleisten-Tool (kein Dock-Icon, kein Fenster) |
| ASR-Engine | Parakeet-TDT 0.6B v3 via FluidAudio (CoreML, on-device, DE+RU bestätigt) |
| Cleanup-LLM | Ollama + Qwen3-4B über localhost-HTTP |
| V1-Features | Nur der Kern — kein Verlauf, keine App-bewusste Formatierung, kein Custom-Vokabular |
| Ansatz | A: Eigene App mit Parakeet; Engine hinter Protokoll gekapselt für späteren Whisper-Wechsel |

## Architektur

Sechs Komponenten, je eine Aufgabe, schmale Schnittstellen:

1. **HotkeyListener** — globaler CGEventTap. Rechte Option-Taste (⌥) halten = aufnehmen, loslassen = stoppen. Taste als Code-Konstante (später konfigurierbar).
2. **AudioRecorder** — AVAudioEngine, 16 kHz mono PCM, Aufnahme während Taste gehalten.
3. **TranscriptionEngine (Protokoll)** — `transcribe(audio: [Float]) async throws -> String`. V1-Implementierung: `ParakeetEngine` (FluidAudio Swift Package). Auto-Spracherkennung DE/RU. Modell (~600 MB) wird beim ersten Start von Hugging Face geladen, danach offline.
4. **CleanupService** — POST an `http://localhost:11434/api/generate` (Ollama, Qwen3-4B). Prompt-Regeln: Füllwörter entfernen, Grammatik glätten, Sprache beibehalten (nie übersetzen), nichts hinzuerfinden, nur den bereinigten Text zurückgeben. Timeout 3 s.
5. **TextInserter** — primär Accessibility API (AXUIElement `kAXSelectedTextAttribute`), Fallback: NSPasteboard setzen + CGEvent ⌘V simulieren, alten Clipboard-Inhalt danach wiederherstellen.
6. **MenuBarController + PermissionsManager** — NSStatusItem mit Zuständen (bereit / aufnahme / verarbeitung / warnung), Quit-Menü. Erststart: geführtes Einholen von Mikrofon- und Accessibility-Berechtigung mit Direktlinks in die Systemeinstellungen.

## Datenfluss

⌥ halten → Icon rot, Aufnahme → loslassen → Parakeet (~0,2 s) → Qwen3-Cleanup (~1 s) → Einfügen am Cursor. Ziel: < 1,5 s vom Loslassen bis zum Text.

## Fehlerbehandlung

Grundprinzip: **lieber roher Text als kein Text.**

- Ollama down / Timeout → rohe Transkription einfügen, Icon zeigt kurz Warnung.
- AX-Einfügen scheitert (Google Docs, Electron-Apps, sichere Felder) → Clipboard-Fallback automatisch.
- Aufnahme < 0,3 s oder leer → still verwerfen.
- Fehlende Berechtigung → Benachrichtigung mit Link in Systemeinstellungen.
- ASR-Fehler → Benachrichtigung, kein Einfügen.

## Testing

- **Unit:** CleanupService (gemockte Ollama-Antworten, Timeout, Fallback auf Rohtext), Pipeline-Zustandslogik.
- **Integration:** deutsche + russische Beispiel-WAVs durch die echte ParakeetEngine, erwartete Transkripte tolerant vergleichen.
- **Manuell:** Einfüge-Matrix in Notes, Mail, Chrome, VS Code, Slack; Verhalten bei Passwortfeldern.

## Setup-Voraussetzungen

- macOS 26 (vorhanden: 26.5.1), Apple Silicon, Xcode-Toolchain.
- Ollama installieren + `ollama pull qwen3:4b` (Setup-Skript im Repo).
- Kein App Sandbox (nötig für AX-API); Code-Signing ad-hoc für lokalen Gebrauch.

## Nicht in V1 (bewusst)

Verlauf, App-bewusste Formatierung, Custom-Vokabular, konfigurierbare Hotkey-UI, Streaming-Transkription während des Sprechens, Auto-Update. Architektur blockiert nichts davon.
