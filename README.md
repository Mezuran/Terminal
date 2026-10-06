<div align="center">

# ✦ Terminal

**A Charm-colored terminal setup, ready in one command.**

NvChad · Starship · `lsd` · `bat` · Glow · Pop

![Neovim Charm palette](https://img.shields.io/badge/Neovim-Charm%20dark%2Flight-6b50ff?style=for-the-badge)
![Starship](https://img.shields.io/badge/Starship-left%20%2B%20right-00ffb2?style=for-the-badge)
![License](https://img.shields.io/badge/license-Apache--2.0-ff9d76?style=for-the-badge)

</div>

---

## Install

On Linux or macOS, with `git`, `curl`, `tar`, and Python 3 available, run:

```bash
git clone --depth 1 https://github.com/Mezuran/Terminal.git "$HOME/.local/share/terminal" && "$HOME/.local/share/terminal/install.sh"
```

The Charm installer opens a keyboard-driven multi-select menu with a live progress bar and status log. The core terminal setup is always included; optional tools start unchecked. Use **↑/↓** to move, **space** to select multiple tools, **a** to select all, **n** to clear, and **enter** to install. The UI uses Charmbracelet’s Bubble Tea and Bubbles packages; prebuilt, checksum-verified UI binaries are used when available.

The setup is user-local by default. If you select PHP, Clang, or GCC and a system package is needed, the installer explains why and asks for interactive `sudo` approval first. It never stores a password or runs `sudo` silently. After installation, open a new terminal.

> **Backups, not surprises:** Existing `~/.config/nvim` and `~/.config/starship.toml` are moved to timestamped `.backup-*` paths before the managed symlinks are created. Existing shell startup files are preserved and backed up before a small, marked setup block is added or refreshed. Re-running the installer is safe.

To update the setup later:

```bash
git -C "$HOME/.local/share/terminal" pull --ff-only && "$HOME/.local/share/terminal/install.sh"
```

This refreshes the managed configs and bootstraps any missing Neovim plugins from the lockfile. Installed core binaries and existing plugin revisions are left in place; use `:Lazy update` from Neovim when you intentionally want newer plugin versions. To change the optional-tool selection, run the installer again and make new choices.

To only link the configs and aliases (without downloading tools or installing plugins):

```bash
"$HOME/.local/share/terminal/install.sh" --config-only
```

## Optional tools and updates

The selector offers these optional tools. Their installation/update channels are chosen to track production/stable versions:

| Menu option | Install and weekly update behavior |
| --- | --- |
| Rust | `rustup` stable toolchain |
| Go | Latest stable release from `go.dev` |
| Bun | Official installer; `bun upgrade --stable` |
| Node.js | Latest LTS release (production channel) |
| uv | Official installer and `uv self update` |
| Python | Latest stable Python managed by uv |
| Composer | Official installer and `composer self-update --stable`; PHP is installed if needed |
| PHP | Latest stable version offered by the OS package manager or Homebrew |
| Clang / GCC | OS package channel or Homebrew; weekly package upgrades |
| OpenAI Codex | Official Codex CLI installer |
| OpenCode | Official OpenCode installer |
| Claude Code | Official **stable** channel |
| Cursor CLI | Official Cursor CLI (`agent` command); the CLI updates itself automatically |

Selected tools are recorded in `~/.config/terminal/selected-tools`. A user-level **weekly** systemd timer (Linux) or launchd agent (macOS) checks only those tools. Logs are written to `~/.local/state/terminal/updates.log`. Run an update immediately with:

```bash
"$HOME/.local/share/terminal/update.sh"
```

PHP and compiler updates are managed by your OS package manager. A scheduled Linux update cannot prompt for a password: it uses `sudo -n` only, and logs/defer system-package upgrades if administrator authorization is not already available. User-local tool updates continue normally. Run the command above from a terminal after `sudo -v` to apply those updates interactively. No sudo credentials are saved.

`--no-ui` installs the core setup without optional selections, for scripts or non-interactive sessions. The installer UI needs no Go when a matching release binary is available; building it from source requires Go 1.24 or later.

### AI CLI theme defaults and compatibility

Selecting Claude Code, Codex, or OpenCode installs and activates its Charm defaults automatically; there is no theme prompt. The shared colors come from `nvim/lua/themes/charm_dark.lua` and the Starship Charm palette. Claude Code and OpenCode support custom UI palettes. Codex currently exposes custom syntax/diff highlighting rather than full TUI chrome colors, so its Charm theme styles that supported surface. Cursor CLI has no custom palette setting in its current configuration schema; the generated shell config uses its supported `COLORFGBG` hint to select dark mode, but Cursor controls its own accent colors. Exact palette matching is therefore limited by each CLI's supported theming surface. Existing agent settings are merged and backed up before they are changed.

The selector detects the OS, CPU architecture, Linux libc, package manager, and required system tools. Incompatible items are disabled with a reason; **a** selects only compatible items. The installer currently supports glibc-based Linux and macOS on x86_64/amd64 and ARM64/aarch64. System-package choices also require a supported package manager and `sudo` when the package is missing. musl/Alpine and Linux systems where glibc cannot be confirmed can still use `--config-only`, but cannot run this installer's core binary setup.

## What you get

### Neovim + NvChad

- User-local stable Neovim binary if Neovim is not already installed.
- NvChad starter configuration with a custom Charm-inspired **dark** and **light** Base46 theme.
- `stevearc/dressing.nvim` for `vim.ui.input` and `vim.ui.select` (upstream is archived, but the plugin remains functional).
- `<leader>uT` toggles between Charm dark and light; `<leader>th` opens NvChad’s theme picker.
- Plugin versions are recorded in `nvim/lazy-lock.json`.

### Starship

- The left prompt keeps OS/user, directory, Git, language, and environment segments.
- The right prompt shows command duration and the clock.
- Charm colors are shared with `nvim/lua/themes/charm_dark.lua`:

| Role | Color | Neovim token |
| --- | --- | --- |
| Cream foreground | `#fffdf5` | `white` |
| Ink background | `#201f26` | `black` / `base00` |
| Muted gray | `#625b6a` | `grey` / `base03` |
| Violet | `#9671ff` | `nord_blue` / `base0D` |
| Mint | `#00ffb2` | `green` / `base0B` |
| Coral | `#ff9d76` | `orange` / `base09` |
| Lavender | `#c89cff` | `purple` / `base0E` |
| Pink-red | `#ff6daa` | `red` / `base0F` |
| Lime | `#ecfd65` | `yellow` / `base0A` |

Bash’s Starship right prompt uses [ble.sh](https://github.com/akinomyoga/ble.sh). The installer builds it locally when GNU `make`, `gawk`, and Git are present; otherwise the left prompt still works and the installer explains what is missing.

### Terminal commands

The installer ensures `lsd`, `bat`, [Glow](https://github.com/charmbracelet/glow), and [Pop](https://github.com/charmbracelet/pop) are available in `~/.local/bin` when not already installed. It adds these aliases:

```bash
ls   # lsd -AFL --group-dirs=first
cat  # bat
```

- **Glow** renders Markdown in the terminal: `glow README.md`.
- **Pop** is Charmbracelet’s terminal email client. It needs SMTP or Resend credentials before it can send mail; installation does not authenticate or send anything.

## Supported systems

- Linux: x86_64 and ARM64
- macOS: Intel and Apple Silicon

Nerd Font glyphs are recommended for the prompt and Neovim UI. Core executables and runtimes are installed under your home directory. Selecting PHP/Clang/GCC can use the system package manager and therefore requires your explicit approval. Linux supports apt and dnf for these packages; macOS uses Homebrew. On Arch-based systems, initial package installation is supported, but unattended weekly system-package upgrades are intentionally not run.

## Layout

```text
.
├── install.sh             # Bootstrap, selection, installs, and weekly updates
├── update.sh              # Logged weekly updater entry point
├── tui/                   # Charm Bubble Tea/Bubbles multi-select and progress UI
├── ai-themes/             # Charm defaults for Claude, Codex, and OpenCode
├── nvim/                  # NvChad configuration and Charm themes
├── shell/                 # Bash/Zsh and Fish aliases
├── starship.toml          # Charm left/right prompt
├── LICENSE                # Apache License 2.0
└── THIRD_PARTY_NOTICES.md # Upstream project notes
```

## License

The configuration and installer are available under the [Apache License 2.0](LICENSE); copyright details are in [NOTICE](NOTICE). Neovim, NvChad, Starship, and the installed tools remain separate upstream projects under their respective licenses.
