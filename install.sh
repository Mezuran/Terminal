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
RUN_SELECTED=0
WEEKLY_UPDATE=0
NO_UI=0
SELECTED_TOOLS=""
PROGRESS_CURRENT=0
PROGRESS_TOTAL=0
TUI_BIN=""
SCHEDULER_CONFIGURED=0

say() { printf '\n\033[1;35m›\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!\033[0m %s\n' "$*" >&2; }
die() { printf '\n\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [--config-only] [--no-ui] [--help]

  --config-only  Link the included configs and install shell aliases without
                 downloading tools or installing Neovim plugins.
  --no-ui        Run the core setup without the interactive selector.
  --help         Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --config-only) INSTALL_TOOLS=0 ;;
    --no-ui) NO_UI=1 ;;
    --run-selected)
      RUN_SELECTED=1
      shift
      SELECTED_TOOLS="${1:-}"
      ;;
    --weekly-update) WEEKLY_UPDATE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)." ;;
  esac
  shift
done

[[ -f "$REPO_DIR/starship.toml" && -d "$REPO_DIR/nvim" ]] || die "Run this script from a complete Terminal repository checkout."

mkdir -p "$BIN_DIR" "$OPT_DIR" "$CONFIG_DIR"
export PATH="$BIN_DIR:$OPT_DIR/go/bin:$OPT_DIR/node/bin:$OPT_DIR/bun/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
export NPM_CONFIG_PREFIX="$LOCAL_DIR"
export BUN_INSTALL="$OPT_DIR/bun"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/terminal-install.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

progress_step() {
  ((PROGRESS_CURRENT += 1))
  if ((!RUN_SELECTED)); then
    say "$1"
    return
  fi
  printf '@@TERMINAL_PROGRESS\t%d\t%d\t%s\n' "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$1"
}

contains_tool() {
  case ",${SELECTED_TOOLS}," in
    *,"$1",*) return 0 ;;
    *) return 1 ;;
  esac
}

is_termux() {
  [[ "${TERMUX_VERSION:-}" != "" || "${PREFIX:-}" == *"/com.termux/"* ]]
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 127
  fi
}

ensure_tui() {
  local goos goarch asset checksums
  if is_termux; then
    goos=android
  else
    goos="$(uname -s | tr '[:upper:]' '[:lower:]')"
  fi
  goarch="$(uname -m)"
  case "$goarch" in
    x86_64|amd64) goarch=amd64 ;;
    aarch64|arm64) goarch=arm64 ;;
    *) return 1 ;;
  esac
  case "$goos" in
    linux|darwin) ;;
    android) [[ "$goarch" == arm64 ]] || return 1 ;;
    *) return 1 ;;
  esac

  TUI_BIN="$TMP_DIR/terminal-tui"
  asset="terminal-tui-${goos}-${goarch}"
  checksums="$TMP_DIR/SHA256SUMS"
  if curl --fail --silent --show-error --location --retry 2 \
    "https://github.com/Mezuran/Terminal/releases/latest/download/SHA256SUMS" \
    --output "$checksums" 2>/dev/null && \
    curl --fail --silent --show-error --location --retry 2 \
    "https://github.com/Mezuran/Terminal/releases/latest/download/$asset" \
    --output "$TUI_BIN" 2>/dev/null; then
    expected="$(awk -v name="$asset" '$2 == name { print $1; exit }' "$checksums")"
    actual="$(sha256_file "$TUI_BIN" 2>/dev/null || true)"
    if [[ -n "$expected" && "$actual" == "$expected" ]]; then
      chmod 0755 "$TUI_BIN"
      return 0
    fi
  fi

  if command -v go >/dev/null 2>&1; then
    if (cd "$REPO_DIR/tui" && GOTOOLCHAIN=local go build -trimpath -ldflags='-s -w' -o "$TUI_BIN" .) >/dev/null 2>&1; then
      chmod 0755 "$TUI_BIN"
      return 0
    fi
  fi
  return 1
}

select_optional_tools() {
  if is_termux; then
    command -v pkg >/dev/null 2>&1 || die "Termux was detected but its pkg package manager is missing."
    pkg install -y curl coreutils gawk || die "Could not install the Termux tools needed to verify and launch the selector."
  fi
  if ((NO_UI)); then
    warn "Interactive selector disabled; installing the core terminal setup only."
    SELECTED_TOOLS=""
    return
  fi
  if [[ ! -t 0 || ! -t 1 || ! -r /dev/tty ]]; then
    warn "No interactive terminal detected; installing core setup only. Use install.sh in a terminal to select optional tools."
    SELECTED_TOOLS=""
    return
  fi

  ensure_tui || die "Could not start the Charm installer UI. Install Go 1.24+ or download a release binary, then retry."
  "$TUI_BIN" "$REPO_DIR/install.sh" || die "The installer UI did not complete successfully."
  # The interactive app reinvokes this script with --run-selected after selection.
  exit 0
}

if ((WEEKLY_UPDATE)); then
  # Defined below after tool helpers are loaded.
  :
elif ((INSTALL_TOOLS && ! RUN_SELECTED)); then
  select_optional_tools
fi

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
  local stripped="$TMP_DIR/bash-stripped"
  local updated="$TMP_DIR/bash-updated"
  [[ -e "$rc" ]] || : > "$rc"

  awk -v start="$BASH_MARKER" -v end="# <<< Terminal dotfiles <<<" \
    'index($0, start) { skipping=1; next } skipping && index($0, end) { skipping=0; next } !skipping { print }' \
    "$rc" > "$stripped"
  {
    printf '%s\n' "$BASH_MARKER"
    printf 'export PATH="$HOME/.local/opt/go/bin:$HOME/.local/opt/node/bin:$HOME/.local/opt/bun/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"\n'
    printf 'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"\n'
    printf 'export BUN_INSTALL="$HOME/.local/opt/bun"\n'
    printf 'export COLORFGBG="15;0"\n'
    printf '%s\n' 'if command -v brew >/dev/null 2>&1; then _terminal_llvm="$(brew --prefix llvm 2>/dev/null)/bin"; [[ ! -d "$_terminal_llvm" ]] || export PATH="$_terminal_llvm:$PATH"; unset _terminal_llvm; fi'
    printf 'if [[ -r %q ]]; then source %q; fi\n' "$REPO_DIR/shell/aliases.sh" "$REPO_DIR/shell/aliases.sh"

    if [[ -r "$BLE_SCRIPT" ]] && ! grep -Fq 'share/blesh/ble.sh' "$stripped"; then
      printf 'if [[ -r %q ]]; then source -- %q --attach=none; fi\n' "$BLE_SCRIPT" "$BLE_SCRIPT"
    fi
    if ! grep -Eq 'starship[[:space:]]+init[[:space:]]+bash' "$stripped"; then
      printf '%s\n' 'if command -v starship >/dev/null 2>&1; then eval "$(starship init bash)"; fi'
    fi
    if [[ -r "$BLE_SCRIPT" ]] && ! grep -Fq 'ble-attach' "$stripped"; then
      printf '%s\n' '[[ ! ${BLE_VERSION-} ]] || ble-attach'
    fi
    printf '%s\n' '# <<< Terminal dotfiles <<<'
  } > "$block"
  cat "$stripped" "$block" > "$updated"
  if ! cmp -s "$rc" "$updated"; then
    [[ -s "$rc" ]] && backup_copy "$rc"
    cat "$updated" > "$rc"
    say "Updated aliases and Starship startup in $rc."
  else
    say "Bash startup is already configured."
  fi
}

configure_zsh() {
  local rc="$HOME/.zshrc"
  local block="$TMP_DIR/zsh-block"
  local stripped="$TMP_DIR/zsh-stripped"
  local updated="$TMP_DIR/zsh-updated"
  [[ -e "$rc" ]] || : > "$rc"
  awk -v start="$ZSH_MARKER" -v end="# <<< Terminal dotfiles <<<" \
    'index($0, start) { skipping=1; next } skipping && index($0, end) { skipping=0; next } !skipping { print }' \
    "$rc" > "$stripped"
  {
    printf '%s\n' "$ZSH_MARKER"
    printf 'export PATH="$HOME/.local/opt/go/bin:$HOME/.local/opt/node/bin:$HOME/.local/opt/bun/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"\n'
    printf 'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"\n'
    printf 'export BUN_INSTALL="$HOME/.local/opt/bun"\n'
    printf 'export COLORFGBG="15;0"\n'
    printf '%s\n' 'if command -v brew >/dev/null 2>&1; then _terminal_llvm="$(brew --prefix llvm 2>/dev/null)/bin"; [[ ! -d "$_terminal_llvm" ]] || export PATH="$_terminal_llvm:$PATH"; unset _terminal_llvm; fi'
    printf '[[ -r %q ]] && source %q\n' "$REPO_DIR/shell/aliases.sh" "$REPO_DIR/shell/aliases.sh"
    if ! grep -Eq 'starship[[:space:]]+init[[:space:]]+zsh' "$stripped"; then
      printf '%s\n' 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'
    fi
    printf '%s\n' '# <<< Terminal dotfiles <<<'
  } > "$block"
  cat "$stripped" "$block" > "$updated"
  if ! cmp -s "$rc" "$updated"; then
    [[ -s "$rc" ]] && backup_copy "$rc"
    cat "$updated" > "$rc"
    say "Updated aliases and Starship startup in $rc."
  else
    say "Zsh startup is already configured."
  fi
}

configure_fish() {
  local rc="$CONFIG_DIR/fish/config.fish"
  local block="$TMP_DIR/fish-block"
  local stripped="$TMP_DIR/fish-stripped"
  local updated="$TMP_DIR/fish-updated"
  mkdir -p "$(dirname "$rc")"
  [[ -e "$rc" ]] || : > "$rc"
  awk -v start="$FISH_MARKER" -v end="# <<< Terminal dotfiles <<<" \
    'index($0, start) { skipping=1; next } skipping && index($0, end) { skipping=0; next } !skipping { print }' \
    "$rc" > "$stripped"
  {
    printf '%s\n' "$FISH_MARKER"
    printf 'fish_add_path --prepend "$HOME/.local/opt/go/bin" "$HOME/.local/opt/node/bin" "$HOME/.local/opt/bun/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin" "$HOME/.opencode/bin" "$HOME/.local/bin" /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/local/sbin\n'
    printf 'set -gx NPM_CONFIG_PREFIX "$HOME/.local"\n'
    printf 'set -gx BUN_INSTALL "$HOME/.local/opt/bun"\n'
    printf 'set -gx COLORFGBG "15;0"\n'
    printf '%s\n' 'if type -q brew; set -l _terminal_llvm (brew --prefix llvm 2>/dev/null)/bin; test ! -d "$_terminal_llvm"; or fish_add_path --prepend "$_terminal_llvm"; end'
    printf 'if test -r %q\n  source %q\nend\n' "$REPO_DIR/shell/aliases.fish" "$REPO_DIR/shell/aliases.fish"
    if ! grep -Fq 'starship init fish' "$stripped"; then
      printf '%s\n' 'if type -q starship; starship init fish | source; end'
    fi
    printf '%s\n' '# <<< Terminal dotfiles <<<'
  } > "$block"
  cat "$stripped" "$block" > "$updated"
  if ! cmp -s "$rc" "$updated"; then
    [[ -s "$rc" ]] && backup_copy "$rc"
    cat "$updated" > "$rc"
    say "Updated aliases and Starship startup in $rc."
  else
    say "Fish startup is already configured."
  fi
}

replace_current_link() {
  local source="$1"
  local target="$2"
  local temporary="${target}.new.$$"

  if [[ -e "$target" && ! -L "$target" ]]; then
    backup_path "$target"
  fi
  rm -f "$temporary"
  ln -s "$source" "$temporary"
  python3 - "$temporary" "$target" <<'PY'
import os
import sys
os.replace(sys.argv[1], sys.argv[2])
PY
}

install_go_stable() {
  local info version filename checksum archive install_dir
  info="$(python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("https://go.dev/dl/?mode=json", timeout=30) as response:
    releases = json.load(response)
release = next(item for item in releases if item.get("stable"))
os_name = {"Linux": "linux", "Darwin": "darwin"}[__import__("platform").system()]
arch = {"x86_64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(__import__("platform").machine())
if not arch:
    raise SystemExit("Unsupported Go architecture")
asset = next(item for item in release["files"] if item["os"] == os_name and item["arch"] == arch and item["kind"] == "archive")
print(release["version"], asset["filename"], asset["sha256"])
PY
)" || die "Could not resolve the latest stable Go release."
  read -r version filename checksum <<<"$info"
  install_dir="$OPT_DIR/$version"

  if [[ ! -x "$install_dir/bin/go" ]]; then
    say "Downloading $version…"
    archive="$TMP_DIR/$filename"
    curl --fail --silent --show-error --location --retry 3 "https://go.dev/dl/$filename" --output "$archive" \
      || die "Could not download $version."
    python3 - "$archive" "$checksum" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as archive:
    for block in iter(lambda: archive.read(1024 * 1024), b""):
        digest.update(block)
if digest.hexdigest() != sys.argv[2]:
    raise SystemExit("Go archive checksum mismatch")
PY
    mkdir -p "$TMP_DIR/go-extract"
    tar -xzf "$archive" -C "$TMP_DIR/go-extract"
    mv "$TMP_DIR/go-extract/go" "$install_dir"
  fi

  replace_current_link "$install_dir" "$OPT_DIR/go"
  say "Go $version is ready in $OPT_DIR/go."
}

install_node_lts() {
  local info version filename checksum archive install_dir
  info="$(python3 - <<'PY'
import json
import platform
import urllib.request

with urllib.request.urlopen("https://nodejs.org/dist/index.json", timeout=30) as response:
    releases = json.load(response)
release = next(item for item in releases if item.get("lts"))
os_name = {"Linux": "linux", "Darwin": "darwin"}[platform.system()]
arch = {"x86_64": "x64", "aarch64": "arm64", "arm64": "arm64"}.get(platform.machine())
if not arch:
    raise SystemExit("Unsupported Node.js architecture")
filename = f"node-{release['version']}-{os_name}-{arch}.tar.xz"
platform_file = f"linux-{arch}" if os_name == "linux" else f"osx-{arch}-tar"
if platform_file not in release["files"]:
    raise SystemExit(f"Node.js has no stable LTS asset for {os_name}/{arch}")
print(release["version"], filename)
PY
)" || die "Could not resolve the latest Node.js LTS release."
  read -r version filename <<<"$info"
  checksum="$(curl --fail --silent --show-error --location --retry 3 "https://nodejs.org/dist/$version/SHASUMS256.txt" | awk -v name="$filename" '$2 == name {print $1}')"
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || die "Could not read the Node.js archive checksum."
  install_dir="$OPT_DIR/node-$version"

  if [[ ! -x "$install_dir/bin/node" ]]; then
    say "Downloading Node.js $version (LTS)…"
    archive="$TMP_DIR/$filename"
    curl --fail --silent --show-error --location --retry 3 "https://nodejs.org/dist/$version/$filename" --output "$archive" \
      || die "Could not download Node.js $version."
    python3 - "$archive" "$checksum" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as archive:
    for block in iter(lambda: archive.read(1024 * 1024), b""):
        digest.update(block)
if digest.hexdigest() != sys.argv[2]:
    raise SystemExit("Node.js archive checksum mismatch")
PY
    mkdir -p "$TMP_DIR/node-extract"
    tar -xJf "$archive" -C "$TMP_DIR/node-extract"
    mv "$TMP_DIR/node-extract/${filename%.tar.xz}" "$install_dir"
  fi

  replace_current_link "$install_dir" "$OPT_DIR/node"
  say "Node.js $version is ready in $OPT_DIR/node."
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    if uv self update; then
      say "uv is already up to date."
      return 0
    fi
    warn "Updating the existing uv installation in place failed; installing a user-local copy."
  fi
  say "Installing the latest stable uv…"
  curl --fail --silent --show-error --location --retry 3 https://astral.sh/uv/install.sh --output "$TMP_DIR/uv-install.sh" \
    || die "Could not download uv's official installer."
  UV_INSTALL_DIR="$BIN_DIR" UV_NO_MODIFY_PATH=1 sh "$TMP_DIR/uv-install.sh" \
    || die "The uv installer failed."
}

install_theme_asset() {
  local source="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then backup_path "$target"; fi
  install -m 0644 "$source" "$target"
}

merge_json_setting() {
  local target="$1" key="$2" value="$3" output
  output="$(mktemp "$TMP_DIR/json-config.XXXXXX")"
  python3 - "$target" "$output" "$key" "$value" <<'PY'
import json
import os
import sys

source, destination, key, value = sys.argv[1:]
config = {}
if os.path.exists(source):
    with open(source, encoding="utf-8") as stream:
        content = stream.read()

    # OpenCode also accepts JSONC. Strip comments and trailing commas without
    # mistaking comment markers or commas inside quoted strings for syntax.
    uncommented = []
    index = 0
    in_string = False
    escaped = False
    while index < len(content):
        char = content[index]
        following = content[index + 1] if index + 1 < len(content) else ""
        if in_string:
            uncommented.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            uncommented.append(char)
            index += 1
        elif char == "/" and following == "/":
            index += 2
            while index < len(content) and content[index] not in "\r\n":
                index += 1
        elif char == "/" and following == "*":
            index += 2
            while index + 1 < len(content) and content[index:index + 2] != "*/":
                if content[index] in "\r\n":
                    uncommented.append(content[index])
                index += 1
            index = min(len(content), index + 2)
        else:
            uncommented.append(char)
            index += 1

    without_trailing_commas = []
    index = 0
    in_string = False
    escaped = False
    while index < len(uncommented):
        char = uncommented[index]
        if in_string:
            without_trailing_commas.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            without_trailing_commas.append(char)
            index += 1
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(uncommented) and uncommented[lookahead].isspace():
                lookahead += 1
            if lookahead < len(uncommented) and uncommented[lookahead] in "}]":
                index += 1
            else:
                without_trailing_commas.append(char)
                index += 1
        else:
            without_trailing_commas.append(char)
            index += 1

    config = json.loads("".join(without_trailing_commas))
    if not isinstance(config, dict):
        raise SystemExit(f"{source} must contain a JSON object")
try:
    value = json.loads(value)
except json.JSONDecodeError:
    pass
config[key] = value
with open(destination, "w", encoding="utf-8") as stream:
    json.dump(config, stream, indent=2, ensure_ascii=False)
    stream.write("\n")
PY
  if [[ -f "$target" ]] && cmp -s "$target" "$output"; then return 0; fi
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" ]]; then
    backup_copy "$target"
    cat "$output" > "$target"
  else
    install -m 0644 "$output" "$target"
  fi
}

merge_codex_theme_setting() {
  local target="$1" output
  output="$(mktemp "$TMP_DIR/codex-config.XXXXXX")"
  python3 - "$target" "$output" <<'PY'
import os
import re
import sys

source, destination = sys.argv[1:]
lines = []
if os.path.exists(source):
    with open(source, encoding="utf-8") as stream:
        lines = stream.readlines()

section_start = None
section_end = len(lines)
for index, line in enumerate(lines):
    match = re.match(r"\s*\[([^]]+)\]\s*(?:#.*)?$", line)
    if match:
        if match.group(1).strip() == "tui":
            section_start = index
            section_end = len(lines)
            for end in range(index + 1, len(lines)):
                if re.match(r"\s*\[", lines[end]):
                    section_end = end
                    break
            break

setting = 'theme = "charm-dark"\n'
if section_start is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.extend(["[tui]\n", setting])
else:
    theme_line = None
    for index in range(section_start + 1, section_end):
        if re.match(r"\s*theme\s*=", lines[index]):
            theme_line = index
            break
    if theme_line is not None:
        indent = re.match(r"\s*", lines[theme_line]).group(0)
        lines[theme_line] = indent + setting
    else:
        lines.insert(section_end, setting)

with open(destination, "w", encoding="utf-8") as stream:
    stream.writelines(lines)
PY
  if [[ -f "$target" ]] && cmp -s "$target" "$output"; then return 0; fi
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" ]]; then
    backup_copy "$target"
    cat "$output" > "$target"
  else
    install -m 0644 "$output" "$target"
  fi
}

install_claude_theme() {
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  install_theme_asset "$REPO_DIR/ai-themes/claude/charm-dark.json" "$config_dir/themes/charm-dark.json"
  merge_json_setting "$config_dir/settings.json" theme "custom:charm-dark"
  say "Enabled the Charm Dark theme for Claude Code."
}

install_codex_theme() {
  local config_dir="${CODEX_HOME:-$HOME/.codex}"
  install_theme_asset "$REPO_DIR/ai-themes/codex/charm-dark.tmTheme" "$config_dir/themes/charm-dark.tmTheme"
  merge_codex_theme_setting "$config_dir/config.toml"
  say "Enabled Charm Dark syntax highlighting for Codex."
}

install_opencode_theme() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode" config_file version use_cli_settings=0
  if [[ -f "$config_dir/cli.json" ]]; then
    use_cli_settings=1
  elif command -v opencode >/dev/null 2>&1; then
    version="$(opencode --version 2>/dev/null || true)"
    if [[ "$version" =~ ([0-9]+)\. ]] && ((BASH_REMATCH[1] >= 2)); then
      use_cli_settings=1
    fi
  fi
  if ((use_cli_settings)); then
    install_theme_asset "$REPO_DIR/ai-themes/opencode/charm-v2.json" "$config_dir/themes/charm-v2.json"
    merge_json_setting "$config_dir/cli.json" theme '{"name":"charm-v2","mode":"dark"}'
  else
    install_theme_asset "$REPO_DIR/ai-themes/opencode/charm.json" "$config_dir/themes/charm.json"
    if [[ -f "$config_dir/tui.jsonc" ]]; then
      merge_json_setting "$config_dir/tui.jsonc" theme charm
    elif [[ -f "$config_dir/tui.json" ]]; then
      merge_json_setting "$config_dir/tui.json" theme charm
    else
      config_file="$config_dir/tui.json"
      merge_json_setting "$config_file" theme charm
    fi
  fi
  say "Enabled the Charm theme for OpenCode."
}

link_brew_gcc() {
  command -v brew >/dev/null 2>&1 || return 0
  local prefix gcc_path gxx_path
  prefix="$(brew --prefix gcc 2>/dev/null)" || return 0
  read -r gcc_path gxx_path <<<"$(python3 - "$prefix/bin" <<'PY'
import re
import sys
from pathlib import Path

directory = Path(sys.argv[1])
def newest(name):
    matches = []
    for path in directory.glob(f"{name}-*"):
        match = re.fullmatch(re.escape(name) + r"-(\d+)", path.name)
        if match and path.exists():
            matches.append((int(match.group(1)), str(path)))
    return max(matches, default=(0, ""))[1]

print(newest("gcc"), newest("g++"))
PY
)"
  [[ -n "$gcc_path" ]] && link_managed_config "$gcc_path" "$BIN_DIR/gcc"
  [[ -n "$gxx_path" ]] && link_managed_config "$gxx_path" "$BIN_DIR/g++"
  return 0
}

install_system_packages() {
  local want_php=0 want_clang=0 want_gcc=0 manager
  if { contains_tool php || contains_tool composer; } && ! command -v php >/dev/null 2>&1; then want_php=1; fi
  if contains_tool clang && ! command -v clang >/dev/null 2>&1; then want_clang=1; fi
  if contains_tool gcc && ! command -v gcc >/dev/null 2>&1; then want_gcc=1; fi

  if [[ "$(uname -s)" == Darwin ]]; then
    { contains_tool php || contains_tool composer || contains_tool clang || contains_tool gcc; } || return 0
    if ! command -v brew >/dev/null 2>&1; then
      contains_tool gcc && die "Install Homebrew first to provide GNU GCC on macOS: https://brew.sh/"
      ((want_php || want_clang)) && die "Install Homebrew first to install selected PHP/Clang on macOS: https://brew.sh/"
      warn "Homebrew is not installed; existing macOS system tools will be used, but Homebrew-managed updates are unavailable."
      return 0
    fi
    if contains_tool php || contains_tool composer; then
      brew list --versions php >/dev/null 2>&1 || want_php=1
    fi
    if contains_tool clang; then
      brew list --versions llvm >/dev/null 2>&1 || want_clang=1
    fi
    if contains_tool gcc; then
      brew list --versions gcc >/dev/null 2>&1 || want_gcc=1
    fi
    ((want_php || want_clang || want_gcc)) || return 0
    local packages=()
    ((want_php)) && packages+=(php)
    ((want_clang)) && packages+=(llvm)
    ((want_gcc)) && packages+=(gcc)
    if ((${#packages[@]})); then brew install "${packages[@]}"; fi
    contains_tool gcc && link_brew_gcc
    return 0
  fi

  local packages=()
  if ((want_php)) && ! command -v php >/dev/null 2>&1; then packages+=(php-cli); fi
  if ((want_clang)) && ! command -v clang >/dev/null 2>&1; then packages+=(clang); fi
  if ((want_gcc)) && ! command -v gcc >/dev/null 2>&1; then packages+=(build-essential); fi
  ((${#packages[@]})) || return 0

  if command -v apt-get >/dev/null 2>&1; then
    manager=apt
    sudo -n apt-get update || die "Administrator approval is required to install selected PHP/compiler packages."
    sudo -n apt-get install -y "${packages[@]}" || die "Could not install selected system packages."
  elif command -v dnf >/dev/null 2>&1; then
    manager=dnf
    local dnf_packages=()
    ((want_php)) && ! command -v php >/dev/null 2>&1 && dnf_packages+=(php-cli)
    ((want_clang)) && ! command -v clang >/dev/null 2>&1 && dnf_packages+=(clang)
    ((want_gcc)) && ! command -v gcc >/dev/null 2>&1 && dnf_packages+=(gcc gcc-c++)
    sudo -n dnf install -y "${dnf_packages[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    manager=pacman
    local pacman_packages=()
    ((want_php)) && ! command -v php >/dev/null 2>&1 && pacman_packages+=(php)
    ((want_clang)) && ! command -v clang >/dev/null 2>&1 && pacman_packages+=(clang)
    ((want_gcc)) && ! command -v gcc >/dev/null 2>&1 && pacman_packages+=(gcc)
    sudo -n pacman -Syu --needed --noconfirm "${pacman_packages[@]}"
  else
    die "No supported system package manager found for PHP/Clang/GCC."
  fi
  say "Installed selected system packages with $manager."
}

install_selected_tool() {
  if is_termux; then
    case "$1" in
      rust|go|nodejs|python|composer|php|clang) return 0 ;;
      *) die "$1 is not supported by the Termux installer." ;;
    esac
  fi
  case "$1" in
    rust)
      if command -v rustup >/dev/null 2>&1; then
        rustup toolchain install stable --profile minimal
        rustup update stable
      else
        curl --fail --silent --show-error --location --retry 3 https://sh.rustup.rs --output "$TMP_DIR/rustup-init.sh"
        sh "$TMP_DIR/rustup-init.sh" -y --default-toolchain stable --profile minimal --no-modify-path
      fi
      ;;
    go) install_go_stable ;;
    bun)
      mkdir -p "$OPT_DIR"
      curl --fail --silent --show-error --location --retry 3 https://bun.com/install --output "$TMP_DIR/bun-install.sh"
      bash "$TMP_DIR/bun-install.sh"
      "$OPT_DIR/bun/bin/bun" upgrade --stable
      ;;
    nodejs) install_node_lts ;;
    uv) install_uv ;;
    python)
      install_uv
      uv python install --default
      uv python upgrade
      ;;
    composer)
      command -v php >/dev/null 2>&1 || die "Composer requires PHP. Select PHP or install PHP first."
      curl --fail --silent --show-error --location --retry 3 https://getcomposer.org/installer --output "$TMP_DIR/composer-setup.php"
      php "$TMP_DIR/composer-setup.php" --install-dir="$BIN_DIR" --filename=composer
      composer self-update --stable --no-interaction
      ;;
    php|clang|gcc) : ;; # Installed together by install_system_packages.
    codex)
      curl --fail --silent --show-error --location --retry 3 https://chatgpt.com/codex/install.sh --output "$TMP_DIR/codex-install.sh"
      CODEX_NON_INTERACTIVE=1 sh "$TMP_DIR/codex-install.sh"
      install_codex_theme
      ;;
    opencode)
      curl --fail --silent --show-error --location --retry 3 https://opencode.ai/install --output "$TMP_DIR/opencode-install.sh"
      bash "$TMP_DIR/opencode-install.sh" --no-modify-path
      install_opencode_theme
      ;;
    claude)
      curl --fail --silent --show-error --location --retry 3 https://claude.ai/install.sh --output "$TMP_DIR/claude-install.sh"
      bash "$TMP_DIR/claude-install.sh" stable
      install_claude_theme
      ;;
    cursor)
      curl --fail --silent --show-error --location --retry 3 https://cursor.com/install --output "$TMP_DIR/cursor-install.sh"
      bash "$TMP_DIR/cursor-install.sh"
      say "Cursor CLI will use the generated shell config's Charm dark-mode hint."
      ;;
    *) die "Unknown selected tool: $1" ;;
  esac
}

install_selected_tools() {
  local tool
  if is_termux; then
    install_termux_selected_packages
  else
    install_system_packages
  fi
  IFS=',' read -r -a selected_array <<< "$SELECTED_TOOLS"
  for tool in "${selected_array[@]}"; do
    [[ -n "$tool" ]] || continue
    install_selected_tool "$tool" || die "Could not install $tool."
    progress_step "Installed $tool"
  done
}

termux_package_for_tool() {
  case "$1" in
    rust) printf '%s\n' rust ;;
    go) printf '%s\n' golang ;;
    nodejs) printf '%s\n' nodejs-lts ;;
    python) printf '%s\n' python ;;
    composer) printf '%s\n' composer ;;
    php) printf '%s\n' php ;;
    clang) printf '%s\n' clang ;;
    *) return 1 ;;
  esac
}

install_termux_selected_packages() {
  local tool package
  local packages=()
  IFS=',' read -r -a selected_array <<< "$SELECTED_TOOLS"
  for tool in "${selected_array[@]}"; do
    [[ -n "$tool" ]] || continue
    package="$(termux_package_for_tool "$tool")" || die "$tool is not supported by the Termux installer."
    packages+=("$package")
  done
  ((${#packages[@]})) || return 0
  pkg install -y "${packages[@]}" || die "Could not install selected Termux packages."
}

update_system_packages() {
  local packages=()
  if [[ "$(uname -s)" == Darwin ]]; then
    command -v brew >/dev/null 2>&1 || return 0
    local brew_packages=()
    contains_tool php && brew_packages+=(php)
    contains_tool composer && brew_packages+=(php)
    contains_tool clang && brew_packages+=(llvm)
    contains_tool gcc && brew_packages+=(gcc)
    if ((${#brew_packages[@]})) && ! brew upgrade "${brew_packages[@]}"; then
      warn "Homebrew could not update one or more selected system tools."
    fi
    contains_tool gcc && link_brew_gcc
    return 0
  fi

  if contains_tool php; then packages+=(php-cli); fi
  contains_tool composer && packages+=(php-cli)
  contains_tool clang && packages+=(clang)
  contains_tool gcc && packages+=(gcc)
  ((${#packages[@]})) || return 0
  if command -v apt-get >/dev/null 2>&1; then
    if sudo -n apt-get update && sudo -n apt-get install -y --only-upgrade "${packages[@]}"; then
      say "Updated selected system packages."
    else
      warn "System package updates need administrator approval. Run '$REPO_DIR/install.sh --weekly-update' in a terminal after using sudo."
    fi
  elif command -v dnf >/dev/null 2>&1; then
    local dnf_packages=()
    if contains_tool php; then dnf_packages+=(php-cli); fi
    contains_tool clang && dnf_packages+=(clang)
    contains_tool gcc && dnf_packages+=(gcc gcc-c++)
    if ! sudo -n dnf upgrade -y "${dnf_packages[@]}"; then
      warn "Selected system package updates need administrator approval. Run the updater after using sudo."
    fi
  else
    warn "Automatic selected system-package upgrades are unavailable for this distribution's package manager."
  fi
}

update_selected_tools() {
  local tool failed=0
  [[ -r "$CONFIG_DIR/terminal/selected-tools" ]] || { say "No selected tools are recorded; nothing to update."; return 0; }
  SELECTED_TOOLS="$(paste -sd, "$CONFIG_DIR/terminal/selected-tools")"
  [[ -n "$SELECTED_TOOLS" ]] || { say "No optional tools were selected; nothing to update."; return 0; }

  if is_termux; then
    local package
    local packages=()
    IFS=',' read -r -a selected_array <<< "$SELECTED_TOOLS"
    for tool in "${selected_array[@]}"; do
      package="$(termux_package_for_tool "$tool")" || { warn "Ignoring unsupported Termux tool '$tool'."; continue; }
      packages+=("$package")
    done
    if ((${#packages[@]})); then
      pkg install -y "${packages[@]}" || return 1
      say "Selected Termux packages are up to date."
    fi
    return 0
  fi

  update_system_packages
  IFS=',' read -r -a selected_array <<< "$SELECTED_TOOLS"
  for tool in "${selected_array[@]}"; do
    say "Checking stable updates for $tool…"
    case "$tool" in
      rust) rustup update stable || failed=1 ;;
      go) install_go_stable || failed=1 ;;
      bun) "$OPT_DIR/bun/bin/bun" upgrade --stable || failed=1 ;;
      nodejs) install_node_lts || failed=1 ;;
      uv) uv self update || failed=1 ;;
      python)
        uv python install --default && uv python upgrade || failed=1
        ;;
      composer) composer self-update --stable --no-interaction || failed=1 ;;
      php|clang|gcc) : ;; # Updated by the OS package manager above.
      codex)
        curl --fail --silent --show-error --location --retry 3 https://chatgpt.com/codex/install.sh --output "$TMP_DIR/codex-update.sh" && CODEX_NON_INTERACTIVE=1 sh "$TMP_DIR/codex-update.sh" || failed=1
        ;;
      opencode)
        curl --fail --silent --show-error --location --retry 3 https://opencode.ai/install --output "$TMP_DIR/opencode-update.sh" && bash "$TMP_DIR/opencode-update.sh" --no-modify-path || failed=1
        ;;
      claude) claude update || failed=1 ;;
      cursor) : ;; # Cursor Agent CLI applies its own automatic updates.
      *) warn "Ignoring unknown selected tool '$tool'." ;;
    esac
  done
  ((failed == 0)) || return 1
  say "Selected tool updates are complete."
}

install_weekly_scheduler() {
  local unit_dir plist_dir
  if is_termux; then
    warn "Android does not provide a dependable user scheduler here; run '$REPO_DIR/update.sh' weekly to update selected tools."
    return 0
  fi
  if [[ "$(uname -s)" == Darwin ]]; then
    plist_dir="$HOME/Library/LaunchAgents"
    mkdir -p "$plist_dir"
    mkdir -p "$HOME/.local/state/terminal"
    python3 - "$REPO_DIR/update.sh" "$HOME/.local/state/terminal/weekly-update.log" "$plist_dir/com.mezuran.terminal-update.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

script, log, output = sys.argv[1:]
Path(output).write_bytes(plistlib.dumps({
    "Label": "com.mezuran.terminal-update",
    "ProgramArguments": ["/bin/bash", script],
    "StartInterval": 604800,
    "RunAtLoad": False,
    "StandardOutPath": log,
    "StandardErrorPath": log,
}))
PY
    launchctl bootout "gui/$(id -u)/com.mezuran.terminal-update" >/dev/null 2>&1 || true
    if launchctl bootstrap "gui/$(id -u)" "$plist_dir/com.mezuran.terminal-update.plist"; then
      SCHEDULER_CONFIGURED=1
    else
      warn "Could not load the weekly launchd updater."
    fi
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    unit_dir="$CONFIG_DIR/systemd/user"
    mkdir -p "$unit_dir"
    local update_script="${REPO_DIR//\\/\\\\}"
    update_script="${update_script// /\\x20}"
    cat > "$unit_dir/terminal-update.service" <<EOF
[Unit]
Description=Update selected Terminal tools to stable releases

[Service]
Type=oneshot
ExecStart=/bin/bash $update_script
EOF
    cat > "$unit_dir/terminal-update.timer" <<'EOF'
[Unit]
Description=Weekly update check for selected Terminal tools

[Timer]
OnCalendar=weekly
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    if systemctl --user daemon-reload && systemctl --user enable --now terminal-update.timer; then
      SCHEDULER_CONFIGURED=1
    else
      warn "Could not enable the systemd user timer."
    fi
  else
    warn "No usable systemd user manager was found; run '$REPO_DIR/update.sh' weekly to update selected tools."
  fi
}

linux_uses_glibc() {
  [[ "$(uname -s)" == Linux ]] || return 1
  [[ -r /etc/alpine-release ]] && return 1
  if command -v getconf >/dev/null 2>&1 && getconf GNU_LIBC_VERSION 2>/dev/null | grep -q '^glibc '; then
    return 0
  fi
  local loader
  for loader in /lib/ld-linux*.so* /lib64/ld-linux*.so* /usr/lib/ld-linux*.so*; do
    [[ -e "$loader" ]] && return 0
  done
  return 1
}

install_tools() {
  local os arch nvim_asset starship_pattern lsd_pattern bat_pattern glow_pattern pop_pattern
  if is_termux; then
    local installed_golang_for_pop=0
    command -v pkg >/dev/null 2>&1 || die "Termux pkg was not found."
    case "$(uname -m)" in
      aarch64|arm64) ;;
      *) die "Termux core setup is supported only on Android arm64 (detected $(uname -m))." ;;
    esac
    say "Installing the Termux-compatible core from the official pkg repositories…"
    pkg update -y || die "Could not refresh Termux package indexes."
    pkg install -y neovim starship lsd bat glow git curl tar coreutils findutils \
      || die "Could not install the Termux-compatible core packages."
    progress_step "Neovim ready"
    progress_step "Starship ready"
    progress_step "lsd ready"
    progress_step "bat ready"
    progress_step "Glow ready"
    if ! command -v pop >/dev/null 2>&1; then
      if ! command -v go >/dev/null 2>&1; then
        pkg install -y golang || die "Could not install the temporary Go build dependency for Pop."
        installed_golang_for_pop=1
      fi
      mkdir -p "$BIN_DIR" "$OPT_DIR/go"
      CGO_ENABLED=0 GOBIN="$BIN_DIR" GOPATH="$OPT_DIR/go" go install github.com/charmbracelet/pop@latest \
        || die "Could not build Pop for Android/Termux using the Termux Go package."
    fi
    progress_step "Pop ready"
    if ((installed_golang_for_pop)) && ! contains_tool go; then
      pkg uninstall -y golang || warn "Pop was built, but the temporary Go build dependency could not be removed."
    fi
    install_blesh_if_available
    return 0
  fi
  os="$(uname -s)"
  arch="$(uname -m)"

  if [[ "$os" == Linux ]] && ! linux_uses_glibc; then
    die "The core binary releases require glibc. This Linux device is not confirmed as glibc-compatible; use --config-only to link configs without installing tools."
  fi

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
  progress_step "Neovim ready"
  install_release_binary starship starship/starship "$starship_pattern"
  progress_step "Starship ready"
  install_release_binary lsd lsd-rs/lsd "$lsd_pattern"
  progress_step "lsd ready"
  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    link_managed_config "$(command -v batcat)" "$BIN_DIR/bat"
    say "Linked bat to the installed batcat executable."
  else
    install_release_binary bat sharkdp/bat "$bat_pattern"
  fi
  progress_step "bat ready"
  install_release_binary glow charmbracelet/glow "$glow_pattern"
  progress_step "Glow ready"
  install_release_binary pop charmbracelet/pop "$pop_pattern"
  progress_step "Pop ready"
  install_blesh_if_available
}

if ((WEEKLY_UPDATE)); then
  update_selected_tools
  exit $?
fi

if ((INSTALL_TOOLS)); then
  selected_count=0
  if [[ -n "$SELECTED_TOOLS" ]]; then
    IFS=',' read -r -a selected_array <<< "$SELECTED_TOOLS"
    selected_count="${#selected_array[@]}"
  fi
  PROGRESS_TOTAL=$((11 + selected_count))
  install_tools
  install_selected_tools

  mkdir -p "$CONFIG_DIR/terminal"
  : > "$CONFIG_DIR/terminal/selected-tools"
  if [[ -n "$SELECTED_TOOLS" ]]; then
    tr ',' '\n' <<< "$SELECTED_TOOLS" | sed '/^$/d' > "$CONFIG_DIR/terminal/selected-tools"
  fi
fi

link_managed_config "$REPO_DIR/nvim" "$CONFIG_DIR/nvim"
if ((INSTALL_TOOLS)); then progress_step "Neovim config linked"; fi
link_managed_config "$REPO_DIR/starship.toml" "$CONFIG_DIR/starship.toml"
if ((INSTALL_TOOLS)); then progress_step "Starship config linked"; fi

case "${SHELL:-}" in
  */bash|bash) configure_bash ;;
  */zsh|zsh) configure_zsh ;;
  */fish|fish) configure_fish ;;
  *) warn "Could not identify the active shell from SHELL=${SHELL:-unset}; configure aliases manually from $REPO_DIR/shell/." ;;
esac
if ((INSTALL_TOOLS)); then progress_step "Shell startup configured"; fi

if ((INSTALL_TOOLS)); then
  install_weekly_scheduler
  if ((SCHEDULER_CONFIGURED)); then
    progress_step "Weekly updater configured"
  else
    progress_step "Manual updater available"
  fi
  say "Bootstrapping NvChad and its locked plugins (first run may take a little while)…"
  if ! nvim --headless +qa >"$TMP_DIR/nvim-bootstrap.log" 2>&1; then
    cat "$TMP_DIR/nvim-bootstrap.log" >&2
    die "Neovim setup failed. Re-run install.sh after resolving the error."
  fi
  progress_step "NvChad ready"
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

if ((INSTALL_TOOLS)); then
  if ((SCHEDULER_CONFIGURED)); then
    say "Selected optional tools update weekly. Review the choices in $CONFIG_DIR/terminal/selected-tools."
  else
    say "Selected tools are recorded in $CONFIG_DIR/terminal/selected-tools. Run '$REPO_DIR/update.sh' manually to check for updates."
  fi
fi
