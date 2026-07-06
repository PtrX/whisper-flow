# WhisperFlow — Verlauf in der Menüleiste (Design)

**Datum:** 2026-07-06
**Status:** Genehmigt von Peter (autonome Ausführung angefragt: "mach du alles")
**Ziel:** Zugriff auf mehr als nur die letzte Transkription — ein "History"-Untermenü zeigt die letzten Diktate, Klick fügt den gewählten Eintrag am Cursor ein.

## Entscheidungen

Peter hat vorab gesagt, dass kein "richtiger" Verlauf nötig ist — daraus abgeleitet, bewusst minimal:

| Frage | Entscheidung |
|---|---|
| Anzahl Einträge | Letzte 10 |
| Speicherung | **Nur im Speicher (RAM)**, nicht auf Platte — passend zum Privacy-First-Ansatz. Beim Beenden der App weg. |
| UI | Untermenü "History" im bestehenden Menü, ein Eintrag pro Diktat (gekürzte Vorschau) |
| Aktion | Klick fügt den Text am aktuellen Cursor ein (gleicher Mechanismus wie Doppel-Tap-Reinsert) |
| Leer-Zustand | Deaktivierter Eintrag "No dictations yet" |

## Architektur

1. **`DictationHistory`** (neu, WhisperFlowCore, testbar): einfacher Ringpuffer-Struct. `record(_ text: String)` fügt vorn ein, kappt bei 10 Einträgen. `all: [String]` liefert neueste zuerst.

2. **`PipelineCoordinator`** (bestehend, erweitert): ersetzt das bisherige einzelne `lastInsertedText: String?` durch eine private `DictationHistory`-Instanz.
   - `handleRecordingFinished` ruft `history.record(textToInsert)` statt die einzelne Variable zu setzen.
   - `reinsertLastTranscription()` nutzt `history.all.first` (Verhalten unverändert für den Doppel-Tap).
   - Neu: `historyEntries: [String]` (read-only, neueste zuerst) und `insertHistoryEntry(at index: Int) -> PipelineOutcome` (Bounds-Check → `.discarded` bei ungültigem Index, sonst Einfügen wie gehabt, `.reinserted`/`.insertFailed`).
   - Konstruktor bleibt unverändert (3 Parameter) — keine bestehenden Aufrufstellen brechen.

3. **`MenuBarController`** (bestehend, erweitert): neuer Menüpunkt "History" mit Untermenü, gebaut in `rebuildMenu()` (läuft ohnehin nach jedem Diktat erneut, da `updateState()` nach jeder Aufnahme aufgerufen wird — kein zusätzlicher Beobachtungsmechanismus nötig). Zugriff auf aktuelle Einträge über eine neue `historyProvider: (() -> [String])?`-Property. Klick auf einen Eintrag ruft `onSelectHistoryEntry: ((Int) -> Void)?` mit dem Index auf.

4. **`AppDelegate`/`main.swift`** (bestehend, erweitert): verdrahtet `menuController.historyProvider` mit `coordinator?.historyEntries` und `menuController.onSelectHistoryEntry` mit `coordinator?.insertHistoryEntry(at:)`, Ergebnis-Handling identisch zum bestehenden Doppel-Tap-Pfad (Icon-Status aktualisieren, `.insertFailed` zeigt Fehler).

## Datenfluss

Nach jedem erfolgreichen Diktat: Text landet in `DictationHistory` (Index 0 = neuester). Menü-Öffnen liest die aktuelle Liste frisch aus (kein Caching-Problem möglich, da bei jedem Öffnen `rebuildMenu()` bereits gelaufen ist). Klick auf Eintrag N → `insertHistoryEntry(at: N)` → derselbe Einfüge-Pfad wie überall sonst (Clipboard+⌘V primär, AX Fallback).

## Fehlerbehandlung

- Verlauf leer → Untermenü zeigt deaktivierten Platzhalter, kein Crash.
- Ungültiger Index (z. B. Race durch schnelles Diktieren zwischen Öffnen und Klick) → `.discarded`, still, kein Crash.
- Einfügen scheitert → `.insertFailed`, gleiches Fehlerverhalten wie beim normalen Diktat/Doppel-Tap.

## Testing

- **Unit (WhisperFlowCore):** `DictationHistory` — leer initial, `record` fügt vorn ein, Kappung bei 10 Einträgen (11. Eintrag verdrängt ältesten), Reihenfolge neueste-zuerst.
- **Unit (PipelineCoordinatorTests, erweitert):** `historyEntries` nach mehreren `handleRecordingFinished`-Aufrufen in richtiger Reihenfolge; `insertHistoryEntry(at:)` fügt korrekten Text ein; ungültiger Index → `.discarded`; `reinsertLastTranscription()` bleibt unverändert kompatibel zu bestehenden Tests.
- **Manuell (Claude, live):** History-Untermenü nach mehreren Diktaten prüfen (Reihenfolge, Kürzung langer Texte, Kappung bei >10), Klick auf älteren Eintrag fügt richtigen Text ein, leerer Zustand bei Frisch-Start, kein Verlauf nach Neustart der App (bewusst nicht persistiert).

## Nicht in V1

Persistenz über App-Neustart, Löschen einzelner Einträge, Suche im Verlauf, Kopieren in Zwischenablage statt Einfügen (Einfügen deckt den genannten Bedarf "Cursor war woanders" bereits ab).
