#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LOCAL_DIR="${HOME:?HOME must be set}/.local"
readonly BIN_DIR="$LOCAL_DIR/bin"
readonly OPT_DIR="$LOCAL_DIR/opt"
readonly CONFIG_DIR="$HOME/.config"
readonly BASH_MARKER="# >>> Terminal dotfiles >>>"
readonly ZSH_MARKER="# >>> Terminal dotfiles >>>"
readonly FISH_MARKER="# >>> Terminal dotfiles >>>"
readonly BLE_SCRIPT="$HOME/.local/share/blesh/ble.sh"

INSTALL_TOOLS=1

say() { printf '\n\033[1;35m›\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!\033[0m %s\n' "$*" >&2; }
die() { printf '\n\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [--config-only] [--help]

  --config-only  Link the included configs and install shell aliases without
                 downloading tools or syncing Neovim plugins.
  --help         Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --config-only) INSTALL_TOOLS=0 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)." ;;
  esac
  shift
done

[[ -f "$REPO_DIR/starship.toml" && -d "$REPO_DIR/nvim" ]] || die "Run this script from a complete Terminal repository checkout."

mkdir -p "$BIN_DIR" "$OPT_DIR" "$CONFIG_DIR"
export PATH="$BIN_DIR:$PATH"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/terminal-install.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

backup_path() {
  local path="$1"
  local backup="${path}.backup-$(date +%Y%m%d-%H%M%S)"
  local suffix=1

  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${path}.backup-$(date +%Y%m%d-%H%M%S)-$suffix"
    ((suffix += 1))
  done

  mv "$path" "$backup"
  say "Preserved existing $path at $backup"
}

backup_copy() {
  local path="$1"
  local backup="${path}.backup-$(date +%Y%m%d-%H%M%S)"
  local suffix=1

  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${path}.backup-$(date +%Y%m%d-%H%M%S)-$suffix"
    ((suffix += 1))
  done

  cp -p "$path" "$backup"
  say "Backed up $path to $backup"
}

link_managed_config() {
  local source="$1"
  local target="$2"

  mkdir -p "$(dirname "$target")"
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    say "Already linked: $target"
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    backup_path "$target"
  fi

  ln -s "$source" "$target"
  say "Linked $target → $source"
}

release_asset_url() {
  local repository="$1"
  local pattern="$2"
  local json="$TMP_DIR/$(printf '%s' "$repository" | tr '/' '_').json"

  curl --fail --silent --show-error --location --retry 3 \
    --header 'Accept: application/vnd.github+json' \
    --header 'User-Agent: Mezuran-Terminal-installer' \
    "https://api.github.com/repos/$repository/releases/latest" \
    --output "$json" || die "Could not read the latest release for $repository."

  python3 - "$json" "$pattern" <<'PY'
import fnmatch
import json
import sys

with open(sys.argv[1], encoding="utf-8") as release_file:
    release = json.load(release_file)

pattern = sys.argv[2]
matches = [
    asset["browser_download_url"]
    for asset in release.get("assets", [])
    if fnmatch.fnmatchcase(asset.get("name", ""), pattern)
]
if len(matches) != 1:
    print(
        f"Expected one release asset matching {pattern!r}; found {len(matches)}.",
        file=sys.stderr,
    )
    sys.exit(1)
print(matches[0])
PY
}

install_release_binary() {
  local binary="$1"
  local repository="$2"
  local pattern="$3"
  local url archive extract_dir source

  if command -v "$binary" >/dev/null 2>&1; then
    say "$binary is already available at $(command -v "$binary")."
    return
  fi

  say "Installing $binary from $repository…"
  url="$(release_asset_url "$repository" "$pattern")" || die "Could not find a $binary release for this platform."
  archive="$TMP_DIR/$binary.tar.gz"
  extract_dir="$TMP_DIR/$binary"
  mkdir -p "$extract_dir"
  curl --fail --silent --show-error --location --retry 3 "$url" --output "$archive" \
    || die "Download failed for $binary."
  tar -xzf "$archive" -C "$extract_dir" || die "Could not unpack $binary."

  source="$(find "$extract_dir" -type f -name "$binary" -print -quit)"
  [[ -n "$source" ]] || die "The $binary archive did not contain its executable."
  install -m 0755 "$source" "$BIN_DIR/$binary"
  say "Installed $binary to $BIN_DIR/$binary"
}

install_neovim() {
  local asset="$1"
  local archive extract_dir executable source_dir destination

  if command -v nvim >/dev/null 2>&1; then
    say "Neovim is already available at $(command -v nvim)."
    return
  fi

  say "Installing the latest stable Neovim…"
  archive="$TMP_DIR/neovim.tar.gz"
  extract_dir="$TMP_DIR/neovim"
  mkdir -p "$extract_dir"
  curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/neovim/neovim/releases/latest/download/$asset" \
    --output "$archive" || die "Neovim download failed."
  tar -xzf "$archive" -C "$extract_dir" || die "Could not unpack Neovim."

  executable="$(find "$extract_dir" -type f -path '*/bin/nvim' -print -quit)"
  [[ -n "$executable" ]] || die "The Neovim archive did not contain bin/nvim."
  source_dir="${executable%/bin/nvim}"
  destination="$OPT_DIR/neovim"
  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_path "$destination"
  fi
  mv "$source_dir" "$destination"
  link_managed_config "$destination/bin/nvim" "$BIN_DIR/nvim"
  say "Installed Neovim to $destination"
}

install_blesh_if_available() {
  [[ "${SHELL:-}" == */bash || "${SHELL:-}" == bash ]] || return 0
  [[ -r "$BLE_SCRIPT" ]] && { say "ble.sh is already installed for Starship's Bash right prompt."; return 0; }

  if ! command -v git >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v gawk >/dev/null 2>&1; then
    warn "Skipping optional ble.sh: Bash's Starship right prompt needs git, GNU make, and gawk."
    return 0
  fi

  say "Building ble.sh so Bash can display Starship's right prompt…"
  git clone --quiet --recursive --depth 1 --shallow-submodules \
    https://github.com/akinomyoga/ble.sh.git "$TMP_DIR/ble.sh" \
    || die "Could not download ble.sh."
  make -s -C "$TMP_DIR/ble.sh" install PREFIX="$LOCAL_DIR" \
    || die "Could not build/install ble.sh."
}

configure_bash() {
  local rc="$HOME/.bashrc"
  local block="$TMP_DIR/bash-block"
  [[ -e "$rc" ]] || : > "$rc"
  if grep -Fq "$BASH_MARKER" "$rc"; then
    say "Bash startup already has the Terminal block."
    return
  fi

  [[ -s "$rc" ]] && backup_copy "$rc"
  {
    printf '%s\n' "$BASH_MARKER"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n'
    printf 'if [[ -r %q ]]; then source %q; fi\n' "$REPO_DIR/shell/aliases.sh" "$REPO_DIR/shell/aliases.sh"

    if [[ -r "$BLE_SCRIPT" ]] && ! grep -Fq 'share/blesh/ble.sh' "$rc"; then
      printf 'if [[ -r %q ]]; then source -- %q --attach=none; fi\n' "$BLE_SCRIPT" "$BLE_SCRIPT"
    fi
    if ! grep -Eq 'starship[[:space:]]+init[[:space:]]+bash' "$rc"; then
      printf '%s\n' 'if command -v starship >/dev/null 2>&1; then eval "$(starship init bash)"; fi'
    fi
    if [[ -r "$BLE_SCRIPT" ]] && ! grep -Fq 'ble-attach' "$rc"; then
      printf '%s\n' '[[ ! ${BLE_VERSION-} ]] || ble-attach'
    fi
    printf '%s\n' '# <<< Terminal dotfiles <<<'
  } > "$block"
  cat "$block" >> "$rc"
  say "Added aliases and Starship startup to $rc."
}

configure_zsh() {
  local rc="$HOME/.zshrc"
  local block="$TMP_DIR/zsh-block"
  [[ -e "$rc" ]] || : > "$rc"
  if grep -Fq "$ZSH_MARKER" "$rc"; then
    say "Zsh startup already has the Terminal block."
    return
  fi

  [[ -s "$rc" ]] && backup_copy "$rc"
  {
    printf '%s\n' "$ZSH_MARKER"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n'
    printf '[[ -r %q ]] && source %q\n' "$REPO_DIR/shell/aliases.sh" "$REPO_DIR/shell/aliases.sh"
    if ! grep -Eq 'starship[[:space:]]+init[[:space:]]+zsh' "$rc"; then
      printf '%s\n' 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'
    fi
    printf '%s\n' '# <<< Terminal dotfiles <<<'
  } > "$block"
  cat "$block" >> "$rc"
  say "Added aliases and Starship startup to $rc."
}

configure_fish() {
  local rc="$CONFIG_DIR/fish/config.fish"
  local block="$TMP_DIR/fish-block"
  mkdir -p "$(dirname "$rc")"
  [[ -e "$rc" ]] || : > "$rc"
  if grep -Fq "$FISH_MARKER" "$rc"; then
    say "Fish startup already has the Terminal block."
    return
  fi

  [[ -s "$rc" ]] && backup_copy "$rc"
  {
    printf '%s\n' "$FISH_MARKER"
    printf 'fish_add_path --prepend "$HOME/.local/bin"\n'
    printf 'if test -r %q\n  source %q\nend\n' "$REPO_DIR/shell/aliases.fish" "$REPO_DIR/shell/aliases.fish"
    if ! grep -Fq 'starship init fish' "$rc"; then
      printf '%s\n' 'if type -q starship; starship init fish | source; end'
    fi
    printf '%s\n' '# <<< Terminal dotfiles <<<'
  } > "$block"
  cat "$block" >> "$rc"
  say "Added aliases and Starship startup to $rc."
}

install_tools() {
  local os arch nvim_asset starship_pattern lsd_pattern bat_pattern glow_pattern pop_pattern
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os:$arch" in
    Linux:x86_64|Linux:amd64)
      nvim_asset='nvim-linux-x86_64.tar.gz'
      starship_pattern='starship-x86_64-unknown-linux-gnu.tar.gz'
      lsd_pattern='lsd-v*-x86_64-unknown-linux-gnu.tar.gz'
      bat_pattern='bat-v*-x86_64-unknown-linux-gnu.tar.gz'
      glow_pattern='glow_*_Linux_x86_64.tar.gz'
      pop_pattern='pop_*_Linux_x86_64.tar.gz'
      ;;
    Linux:aarch64|Linux:arm64)
      nvim_asset='nvim-linux-arm64.tar.gz'
      starship_pattern='starship-aarch64-unknown-linux-musl.tar.gz'
      lsd_pattern='lsd-v*-aarch64-unknown-linux-gnu.tar.gz'
      bat_pattern='bat-v*-aarch64-unknown-linux-gnu.tar.gz'
      glow_pattern='glow_*_Linux_arm64.tar.gz'
      pop_pattern='pop_*_Linux_arm64.tar.gz'
      ;;
    Darwin:x86_64)
      nvim_asset='nvim-macos-x86_64.tar.gz'
      starship_pattern='starship-x86_64-apple-darwin.tar.gz'
      lsd_pattern='lsd-v*-x86_64-apple-darwin.tar.gz'
      bat_pattern='bat-v*-x86_64-apple-darwin.tar.gz'
      glow_pattern='glow_*_Darwin_x86_64.tar.gz'
      pop_pattern='pop_*_Darwin_x86_64.tar.gz'
      ;;
    Darwin:arm64|Darwin:aarch64)
      nvim_asset='nvim-macos-arm64.tar.gz'
      starship_pattern='starship-aarch64-apple-darwin.tar.gz'
      lsd_pattern='lsd-v*-aarch64-apple-darwin.tar.gz'
      bat_pattern='bat-v*-aarch64-apple-darwin.tar.gz'
      glow_pattern='glow_*_Darwin_arm64.tar.gz'
      pop_pattern='pop_*_Darwin_arm64.tar.gz'
      ;;
    *)
      die "Unsupported platform: $os/$arch (supported: Linux and macOS, x86_64 and arm64)."
      ;;
  esac

  for command in curl git tar python3 install find; do require_command "$command"; done

  install_neovim "$nvim_asset"
  install_release_binary starship starship/starship "$starship_pattern"
  install_release_binary lsd lsd-rs/lsd "$lsd_pattern"
  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    link_managed_config "$(command -v batcat)" "$BIN_DIR/bat"
    say "Linked bat to the installed batcat executable."
  else
    install_release_binary bat sharkdp/bat "$bat_pattern"
  fi
  install_release_binary glow charmbracelet/glow "$glow_pattern"
  install_release_binary pop charmbracelet/pop "$pop_pattern"
  install_blesh_if_available
}

if ((INSTALL_TOOLS)); then
  install_tools
fi

link_managed_config "$REPO_DIR/nvim" "$CONFIG_DIR/nvim"
link_managed_config "$REPO_DIR/starship.toml" "$CONFIG_DIR/starship.toml"

case "${SHELL:-}" in
  */bash|bash) configure_bash ;;
  */zsh|zsh) configure_zsh ;;
  */fish|fish) configure_fish ;;
  *) warn "Could not identify the active shell from SHELL=${SHELL:-unset}; configure aliases manually from $REPO_DIR/shell/." ;;
esac

if ((INSTALL_TOOLS)); then
  say "Bootstrapping NvChad and its locked plugins (first run may take a little while)…"
  if ! nvim --headless +qa >"$TMP_DIR/nvim-bootstrap.log" 2>&1; then
    cat "$TMP_DIR/nvim-bootstrap.log" >&2
    die "Neovim setup failed. Re-run install.sh after resolving the error."
  fi
  say "Neovim setup completed."
fi

cat <<EOF

Terminal setup is ready.
  Neovim config: $CONFIG_DIR/nvim -> $REPO_DIR/nvim
  Starship config: $CONFIG_DIR/starship.toml -> $REPO_DIR/starship.toml
  Local binaries: $BIN_DIR

Open a new terminal to load aliases and the Charm Starship prompt.
Run nvim, then use <leader>uT to toggle Charm dark/light.
EOF
