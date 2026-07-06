# WhisperFlow — Einstellungsfenster (Design)

**Datum:** 2026-07-06
**Status:** Genehmigt von Peter
**Ziel:** Die bisher hart codierten Konfigurationswerte (Ollama-Modell, Cleanup-Timeout, Cleanup an/aus, Hotkey) über ein natives Einstellungsfenster änderbar machen — Änderungen wirken sofort, ohne App-Neustart.

## Entscheidungen (mit Peter geklärt)

| Frage | Entscheidung |
|---|---|
| Umfang V1 | Ollama-Modell, Cleanup-Timeout, Cleanup an/aus, Hotkey |
| Hotkey-Auswahl | Dropdown aus fester Modifier-Liste (kein freier Key-Recorder) |
| UI-Technik | SwiftUI-Fenster via NSHostingController (Ansatz A) |
| Umsetzung | Wird an Codex/OpenCode übergeben; QS macht Claude (Fable) live am System |

## Architektur

Neue und geänderte Komponenten:

1. **`SettingsStore`** (neu, WhisperFlowCore, testbar)
   - Dünner typisierter Wrapper um `UserDefaults` (injizierbare Suite für Tests).
   - Properties: `ollamaModel: String` (Default `"qwen3:4b"`), `cleanupTimeout: TimeInterval` (Default `3.0`), `cleanupEnabled: Bool` (Default `true`), `hotkeyOption: HotkeyOption` (Default `.rightOption`).
   - Einzige Quelle der Wahrheit — kein anderer Code greift direkt auf UserDefaults zu.

2. **`HotkeyOption`** (neu, WhisperFlowCore, testbar)
   - `enum HotkeyOption: String, CaseIterable, Sendable`: `.rightOption`, `.leftOption`, `.rightCommand`, `.rightControl`, `.rightShift`.
   - Liefert pro Case: `keyCode: Int64` (CGEvent-Keycodes: rechte ⌥ = 61, linke ⌥ = 58, rechte ⌘ = 54, rechte ⌃ = 62, rechte ⇧ = 60), `flagMask: CGEventFlags` (`.maskAlternate` / `.maskCommand` / `.maskControl` / `.maskShift`) und `displayName: String` (z. B. "Rechte ⌥ (Option)").
   - Bewusst nur Modifier-Tasten: alle laufen über den bestehenden `.flagsChanged`-Event-Tap. F-Tasten (F13 …) bräuchten einen zweiten Erkennungspfad (`keyDown`/`keyUp`) — nicht in V1.

3. **`HotkeyStateMachine`** (bestehend, minimal erweitert)
   - `init(targetKeyCode: Int64 = 61)` statt fest codierter 61; Verhalten sonst identisch. Bestehende Tests bleiben unverändert gültig.

4. **`HotkeyListener`** (bestehend, erweitert)
   - Nimmt `HotkeyOption` im Konstruktor; nutzt `option.keyCode` für die State-Machine und `option.flagMask` statt fest `.maskAlternate` für die isDown-Erkennung.

5. **`OllamaCleanupService`** (bestehend, geändert)
   - Statt Modell/Timeout im Konstruktor zu fixieren, liest der Service **bei jedem `cleanup(...)`-Aufruf** frisch aus dem injizierten `SettingsStore` → Änderungen wirken sofort, kein Observer nötig.
   - Ist `cleanupEnabled == false`, wirft er sofort `CleanupError.disabled` → der bestehende, getestete Fallback in `PipelineCoordinator` fügt dann den Rohtext ein. `PipelineCoordinator` bleibt unangetastet.

6. **`SettingsWindow`** (neu, WhisperFlowApp, SwiftUI + `NSHostingController`)
   - Formular: Picker (Hotkey, aus `HotkeyOption.allCases`), TextField (Ollama-Modell), Slider 1–10 s mit Wertanzeige (Timeout), Toggle (Cleanup aktiv).
   - Öffnung über neuen Menüpunkt "Settings…" im bestehenden Menüleisten-Menü. App bleibt `LSUIElement`; das Fenster wird per `NSApp.activate` in den Vordergrund geholt. Nur eine Instanz (bei erneutem Klick bestehendes Fenster fokussieren).

7. **`AppDelegate`/`MenuBarController`** (bestehend, erweitert)
   - Menüpunkt "Settings…" ergänzen.
   - Bei Hotkey-Änderung (direkter Callback vom Settings-Fenster an den AppDelegate — kein KVO): laufenden `HotkeyListener` mit `stop()` beenden und mit neuer `HotkeyOption` neu erzeugen/starten. Während einer aktiven Aufnahme eintreffende Änderungen werden erst nach Abschluss der Aufnahme angewendet.

## Datenfluss

Menüleiste → "Settings…" → Fenster. Jede Änderung schreibt sofort in `SettingsStore` (kein OK/Abbrechen). Cleanup-relevante Werte wirken beim nächsten Diktat (frisches Lesen pro Aufruf); Hotkey-Änderung stoppt und startet den Listener sofort neu.

## Fehlerbehandlung

- **Ungültiger/nicht vorhandener Modellname:** keine Validierung im Fenster — Ollama liefert beim nächsten Diktat einen Fehler, der bestehende Rohtext-Fallback greift. (Ollama ist die Wahrheit über verfügbare Modelle.)
- **Timeout:** Slider hart auf 1–10 s begrenzt.
- **Erststart / fehlende Werte:** Defaults ergeben exakt das heutige Verhalten (qwen3:4b, 3 s, Cleanup an, rechte ⌥) — keine Migration nötig.
- **Leerer Modellname:** wird wie ungültiger Name behandelt (Fallback), zusätzlich trimmt `SettingsStore` Whitespace und behandelt einen leeren String als "Default verwenden".

## Testing

- **Unit (WhisperFlowCore):**
  - `SettingsStore`: Defaults ohne gespeicherte Werte; Persistenz (isolierte `UserDefaults(suiteName:)`-Instanz pro Test); leerer Modellname → Default.
  - `HotkeyOption`: Keycode-/FlagMask-/DisplayName-Mapping für alle Cases.
  - `HotkeyStateMachine`: mit abweichendem `targetKeyCode` (z. B. 54) identische Transitions; Taste 61 wird dann ignoriert.
  - `OllamaCleanupService`: liest Settings pro Aufruf frisch (Setting zwischen zwei Aufrufen ändern → zweiter Aufruf nutzt neuen Wert, prüfbar über gemockten URLProtocol-Request-Body); `cleanupEnabled == false` → wirft sofort, ohne HTTP-Request.
- **Manuell (Claude/Fable, live am System):** Fenster öffnen/schließen, Modellwechsel auf ungültiges Modell → Rohtext-Fallback, Timeout-Änderung spürbar, Cleanup-Toggle, Hotkey-Wechsel im laufenden Betrieb inkl. Diktat mit neuer Taste, Doppel-Tap-Reinsert mit neuer Taste, Persistenz über App-Neustart.

## Nicht in V1 (bewusst)

Freier Hotkey-Recorder, F-Tasten als Hotkey, Modell-Dropdown mit Live-Abfrage von Ollama (`/api/tags`), Validierung des Modellnamens, mehrsprachige UI (Fenster ist Englisch wie der Rest der App).
