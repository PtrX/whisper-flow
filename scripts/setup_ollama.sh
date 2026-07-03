#!/usr/bin/env bash
set -euo pipefail

if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama not found. Install it with: brew install ollama"
    exit 1
fi

if ! pgrep -x "ollama" >/dev/null 2>&1; then
    echo "Starting ollama serve in the background..."
    nohup ollama serve >/tmp/ollama.log 2>&1 &
    sleep 2
fi

echo "Pulling qwen3:4b..."
ollama pull qwen3:4b

echo "Verifying with a test prompt..."
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3:4b",
  "prompt": "Reply with exactly: OK",
  "stream": false
}' | grep -q '"response"' && echo "Ollama + qwen3:4b ready."
