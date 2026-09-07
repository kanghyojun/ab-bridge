#!/usr/bin/env bash
# install.sh <mac|remote> — ~/.local/bin 에 심볼릭 링크를 겁니다.
set -euo pipefail

ROLE="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"

case "$ROLE" in
  mac)    ROLE_DIR="$ROOT/mac" ;;
  remote) ROLE_DIR="$ROOT/remote" ;;
  *) echo "사용법: ./install.sh <mac|remote>" >&2; exit 1 ;;
esac

mkdir -p "$BIN"
for f in "$ROLE_DIR"/* "$ROOT/shared"/*; do
  name="$(basename "$f")"
  ln -sfn "$f" "$BIN/$name"
  echo "• $BIN/$name → $f"
done

if [ "$ROLE" = remote ]; then
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$ROOT/skill" "$HOME/.claude/skills/ab-bridge"
  echo "• ~/.claude/skills/ab-bridge → $ROOT/skill"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo
  echo "⚠ jq가 없습니다. 설정 파일을 읽는 데 필요합니다."
  echo "   macOS: brew install jq   /   데비안·우분투: sudo apt install jq"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo; echo "⚠ $BIN 이 PATH에 없습니다. 셸 설정에 추가하십시오." ;;
esac

echo
echo "완료. 설정 파일은 ~/.config/ab-bridge/profiles.json 입니다."
echo "없으면 맥에서 ab-up을 한 번 돌릴 때 기본값으로 만들어집니다."
