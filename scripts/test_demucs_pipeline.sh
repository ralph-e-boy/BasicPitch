#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/basic-pitch-demucs-cli"
METALLIB="$ROOT/mlx.metallib"

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <audio-file> [output-dir]" >&2
  exit 2
fi

INPUT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_DIR="${2:-$ROOT/test_output}"

if [[ ! -f "$INPUT" ]]; then
  echo "error: $INPUT not found" >&2
  exit 1
fi

# Build if binary or metallib missing
if [[ ! -x "$CLI" || ! -f "$METALLIB" ]]; then
  echo "==> Building (make install)..."
  make -C "$ROOT" install
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "==> Running Demucs stem separation + BasicPitch transcription"
echo "    Input: $INPUT"
echo ""

# Single run: separate file per stem (drums, bass, vocals, other)
echo "--- Separate MIDI per stem ---"
BASENAME="$(basename "${INPUT%.*}")"
"$CLI" "$INPUT" --split-stems -o "$OUTPUT_DIR/$BASENAME.mid" --yes
echo ""

# Summary
echo "==> Output files:"
ls -lh "$OUTPUT_DIR"/*.mid
