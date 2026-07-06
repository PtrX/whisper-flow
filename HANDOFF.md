# HANDOFF — WhisperFlow (private, lokale Wispr-Flow-Alternative)

**Stand:** 2026-07-06 · Session 3 (Bugfixes, Icon, GitHub-Release, Settings-Fenster, Verlauf)

## Status: Läuft produktiv bei Peter, aktiv weiterentwickelt

App ist installiert (`/Applications/WhisperFlow.app`), läuft täglich, diktiert Deutsch + Russisch korrekt in echten Apps inkl. Claude Desktop. Öffentliches Repo: **https://github.com/PtrX/whisper-flow** (MIT-Lizenz).

## Was funktioniert

- Push-to-talk (Standard: rechte ⌥, jetzt konfigurierbar), Deutsch/Russisch-ASR via Parakeet v3, Ollama-Cleanup mit Rohtext-Fallback, Text-Einfügen (Clipboard+⌘V primär, AX-API Fallback), Doppel-Tap zum erneuten Einfügen der letzten Transkription, Trailing-Space nach jedem Diktat, eigenes App-Icon, Settings-Fenster (Hotkey/Modell/Timeout/Cleanup an-aus, sofort wirksam, persistiert), **Verlauf** (History-Untermenü, letzte 10 Diktate, nur im Speicher, Klick fügt erneut ein).
- 54 Unit-Tests, alle grün. `swift build && swift test` vor jedem Deploy prüfen.

## Wie diese Session gebaut wurde

Nach dem initialen 12-Task-Build (Session 2, siehe Git-Log) kamen drei Runden dazu:

1. **Bugfix-Runde** (direkt von Claude, kein Subagent) — Peter meldete "Ready, aber Taste reagiert nicht" und ähnliche Symptome; jeder Fund über `superpowers:systematic-debugging` (Logs, Code lesen, Hypothese, Fix, Rebuild+Redeploy, Re-Test). Fünf echte Bugs gefunden, siehe Gotchas unten.
2. **Settings-Fenster** — brainstormed, Spec+Plan geschrieben, **an Codex übergeben** (`codex:rescue`-Skill, `Agent`-Tool). Codex konnte in seiner Sandbox **nicht committen** (`.git/index.lock`: "Operation not permitted") — Task 1 blieb uncommitted stehen, Rest lief erst nach erneutem Anstoß **ohne** Commit-Auftrag an Codex durch; Claude hat alle Commits selbst nachgezogen, in denselben Gruppen wie im Plan vorgesehen. Danach unabhängig `swift build`/`swift test` verifiziert, Code stichprobenartig gelesen (main.swift/SettingsWindow.swift), erst dann committet.
3. **Verlauf (History)** — Peter sagte explizit "mach du alles ... /goal", also autonom durchgezogen: Design selbst entschieden (kein Rückfragen-Loop, da Umfang aus vorherigem Gespräch schon klar), Spec+Plan geschrieben, direkt mit "nicht committen" an Codex übergeben (Lesson aus Runde 2 angewendet) — lief diesmal ohne Blocker durch. Claude hat committet, Code gelesen, Build+Test unabhängig geprüft, live QA gemacht (Peter hat nur kurz bestätigt), dann gepusht.

**Lesson:** Codex-Sandbox kann `.git` nicht schreiben — bei Codex-Handoffs von vornherein "nicht committen, ich committe" instruieren (in Runde 3 direkt gemacht, lief glatt).

## Vorfälle Session 2 (Erst-Implementierung, zur Erinnerung)

Ausführlich im Git-Log ab Commit `e195eb8` bis `393b881`. Kurzfassung der 5 Bugs, alle durch Live-Testing auf Peters Mac gefunden (keiner durch Unit-Tests, da strukturell nicht fangbar):

1. **App hing für immer** nach Accessibility-Prompt — kein OS-Callback für "Berechtigung erteilt", kein Poll-Retry vorhanden → Fix: 1s-Polling.
2. **Menüleisten-Icon unsichtbar** — `updateIcon()` wurde nie beim Start aufgerufen, nur bei `updateState()`.
3. **Hotkey reagierte nie** — Event-Tap lauschte auf `.keyDown`/`.keyUp` statt `.flagsChanged` (rechte ⌥ ist eine reine Modifier-Taste, löst diese nie aus).
4. **Deutsch/Russisch wurden falsch erkannt** (phonetisches Englisch) — `ParakeetEngine` nutzte FluidAudios `UnifiedAsrManager` = **English-only**-Modell (`parakeet-unified-en-0.6b`), nicht die mehrsprachige v3-TDT-API.
5. **Text-Einfügen scheiterte in Electron-Apps** (Claude Desktop, vermutlich auch Slack/Discord/VS Code) — AX-API meldet dort fälschlich `.success`, ohne dass der Text ankommt → Priorität umgedreht: Clipboard+⌘V ist jetzt primär, AX nur Fallback.

## Gotchas (weiterhin relevant)

- **FluidAudio hat zwei komplett getrennte Parakeet-Backends**: `AsrManager` + `AsrModels.downloadAndLoad(version: .v3)` (multilingual, **richtig**) vs. `UnifiedAsrManager` (English-only "Parakeet Unified 0.6B", **falsch** für DE/RU). Bei jeder FluidAudio-Änderung genau prüfen, welches benutzt wird.
- **Ad-hoc Signing ändert sich bei jedem Rebuild** → Accessibility/Mikrofon müssen danach oft neu erteilt werden (in Systemeinstellungen alten Eintrag ggf. entfernen, falls er nicht neu abgefragt wird). `scripts/build_app_bundle.sh` signiert automatisch mit, aber die Signatur ist bei jedem Build neu.
- **Rechte ⌥ ist ein Modifier-Key** → nur über `.flagsChanged`-Events erkennbar, nie `.keyDown`/`.keyUp`. Gilt auch für die neuen konfigurierbaren Hotkeys (alle bewusst auf Modifier-Tasten beschränkt, siehe `HotkeyOption`).
- **AX-Einfügen lügt in Electron-Apps** — meldet `.success`, obwohl nichts passiert. Deshalb Clipboard+⌘V primär, nicht nur als Fallback für geworfene Fehler.
- **Codex-Sandbox kann nicht in `.git` schreiben** — bei Handoffs an Codex Commits selbst übernehmen.
- Ollama läuft lokal auf Port 11434, Modell konfigurierbar über Settings-Fenster (Default weiterhin `qwen3:4b`). Setup-Skript: `scripts/setup_ollama.sh`.
- Icon-Quelle: `Resources/AppIcon.svg`, `scripts/build_icon.sh` regeneriert `.icns` (nutzt `qlmanage`, kein Drittanbieter-Tool nötig).

## Offene Feature-Ideen (gebrainstormt, nach Priorität)

Peter hat diese Reihenfolge gewählt: **Settings-Fenster (✅ fertig) → Verlauf (✅ fertig) → VAD (Voice Activity Detection statt Taste halten) → Autostart bei Login.**

- **VAD** — nächstes dran. Größter Eingriff, ändert das Interaktionsmodell (halten vs. antippen+Auto-Stop bei Stille). Braucht eigene Design-Runde (noch nicht gebrainstormt).
- **Autostart bei Login** — kleinster Umfang, zuletzt eingeplant. **Aktuell NICHT aktiviert** (kein LaunchAgent, kein Login-Item registriert — geprüft via `ls ~/Library/LaunchAgents/` und `osascript` Login-Items) — Peter muss die App nach jedem Neustart weiterhin manuell öffnen.

## Setup-Voraussetzungen (unverändert)

macOS 14+, Apple Silicon, Ollama (`brew install ollama`), Swift 6 Toolchain. Details in [README.md](README.md).
