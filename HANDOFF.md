# HANDOFF — WhisperFlow (private, lokale Wispr-Flow-Alternative)

**Stand:** 2026-07-02 · Session 1 (Research + Design)

## Was diese Session gemacht wurde

1. **Recherche Wispr Flow:** Cloud-basiert (ASR + LLM-Cleanup auf OpenAI/Meta-Servern), kein Offline-Modus, macht sogar Screenshots des aktiven Fensters, ~800 MB RAM idle. Kern-UX: Hotkey halten → sprechen → polierter Text am Cursor in jeder App.
2. **Brainstorming-Skill durchlaufen** (superpowers): Klärungsfragen, 3 Ansätze, Design abschnittsweise genehmigt.
3. **Design-Spec geschrieben und committet:** `docs/superpowers/specs/2026-07-02-local-dictation-design.md`

## Genehmigtes Design (Kurzfassung)

- **App:** natives Swift-Menüleisten-Tool "WhisperFlow", kein Dock-Icon
- **Pipeline:** rechte ⌥ halten → AVAudioEngine (16 kHz mono) → Parakeet-TDT 0.6B **v3** via FluidAudio (CoreML, on-device, DE+RU auto-erkannt, ~0,2 s) → Cleanup via Ollama + Qwen3-4B (`localhost:11434`, Timeout 3 s) → Einfügen per AX-API, Fallback Clipboard+⌘V
- **Prinzip:** lieber roher Text als kein Text (Ollama down → Rohtranskript einfügen)
- **V1 = nur Kern.** Kein Verlauf, kein App-Kontext, kein Custom-Vokabular
- **Engine hinter Protokoll** gekapselt → Whisper-Wechsel später trivial

## Systemstand

- Git-Repo frisch initialisiert, 1 Commit (Spec). Sonst leeres Projekt — **noch kein Code**.
- macOS 26.5.1, Apple Silicon. **Ollama ist NICHT installiert** (Setup-Schritt: installieren + `ollama pull qwen3:4b`).
- Peter hat das Design genehmigt; die schriftliche Spec-Review durch Peter stand beim Session-Ende noch aus (Review-Gate aus dem Brainstorming-Skill).

## Nächste Schritte

1. Peters Spec-Review abwarten/erfragen (`docs/superpowers/specs/2026-07-02-local-dictation-design.md`)
2. Dann: **superpowers:writing-plans Skill invoken** → Implementierungsplan schreiben (das ist der vorgeschriebene nächste Schritt im Brainstorming-Flow, Task #6 in der Task-Liste)
3. Danach Implementierung (executing-plans / subagent-driven-development + TDD-Skill)

## Gotchas

- **FluidAudio/Parakeet:** unbedingt **v3** nehmen (`FluidInference/parakeet-tdt-0.6b-v3-coreml`) — v2 ist English-only, v3 kann 25 Sprachen inkl. Deutsch + Russisch. Modell ~600 MB, lädt beim ersten Start von Hugging Face.
- **Apple Foundation Models** (in macOS 26 eingebaut) wäre für Cleanup bequemer gewesen, kann aber **kein Russisch** → deshalb Ollama/Qwen3.
- **AX-Einfügen scheitert** in Google Docs, manchen Electron-Apps und sicheren Feldern → Clipboard-Fallback ist Pflicht, alten Clipboard-Inhalt wiederherstellen.
- App braucht **kein App Sandbox** (AX-API), Mikrofon- + Accessibility-Permission, ad-hoc Signing reicht lokal.
- Cleanup-Prompt-Regeln (wichtig für DE/RU): Sprache beibehalten, nie übersetzen, nichts hinzuerfinden, nur Text zurückgeben.
