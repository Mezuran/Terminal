#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/terminal"
mkdir -p "$STATE_DIR"
export PATH="$HOME/.local/bin:$HOME/.local/opt/go/bin:$HOME/.local/opt/node/bin:$HOME/.local/opt/bun/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
export NPM_CONFIG_PREFIX="$HOME/.local"
export BUN_INSTALL="$HOME/.local/opt/bun"

if command -v flock >/dev/null 2>&1; then
  exec 9>"$STATE_DIR/update.lock"
  flock -n 9 || exit 0
else
  LOCK_DIR="$STATE_DIR/update.lock.d"
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
fi

{
  printf '\n[%s] Weekly stable update check started.\n' "$(date -Is 2>/dev/null || date)"
  bash "$REPO_DIR/install.sh" --weekly-update
  printf '[%s] Weekly stable update check finished.\n' "$(date -Is 2>/dev/null || date)"
} 2>&1 | tee -a "$STATE_DIR/updates.log"
