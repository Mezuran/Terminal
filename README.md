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

On Linux, macOS, or inside WSL, with `git`, `curl`, `tar`, and Python 3 available, run:

```bash
git clone --depth 1 https://github.com/Mezuran/Terminal.git "$HOME/.local/share/terminal" && "$HOME/.local/share/terminal/install.sh"
```

The Charm installer opens a keyboard-driven multi-select menu with a live progress bar and status log. The core terminal setup is always included; optional tools start unchecked. Use **↑/↓** to move, **space** to select multiple tools, **a** to select all, **n** to clear, and **enter** to install. The UI uses Charmbracelet’s Bubble Tea and Bubbles packages; prebuilt, checksum-verified UI binaries are used when available.

On native Windows, open PowerShell and run:

```powershell
git clone --depth 1 https://github.com/Mezuran/Terminal.git "$HOME\.local\share\terminal"
& "$HOME\.local\share\terminal\install.ps1"
```

The Windows installer is native PowerShell and also downloads a checksum-verified selector; it does not require Go. In Termux, run:

```bash
pkg install -y git
git clone --depth 1 https://github.com/Mezuran/Terminal.git "$HOME/.local/share/terminal"
bash "$HOME/.local/share/terminal/install.sh"
```

The installer bootstraps its checksum/transfer utilities and uses Termux `pkg` packages for the compatible core.

Desktop installs are user-local by default. On Linux, a selected PHP/compiler system package explains why and requests interactive `sudo` approval; macOS uses Homebrew. Termux installs compatible packages with its user-owned `pkg` manager and never invokes `sudo`. Native Windows only offers PHP/compiler executables already on PATH. No sudo password is stored. After installation, open a new terminal.

> **Backups, not surprises:** Existing Neovim and Starship configs are preserved at timestamped `.backup-*` paths before managed links/copies are created. Existing shell startup files and the PowerShell profile are backed up before the marked setup block is refreshed. Re-running the installer is safe.

To update the setup later:

```bash
git -C "$HOME/.local/share/terminal" pull --ff-only && "$HOME/.local/share/terminal/install.sh"
```

On native Windows:

```powershell
git -C "$HOME\.local\share\terminal" pull --ff-only
& "$HOME\.local\share\terminal\install.ps1"
```

This refreshes the managed configs and bootstraps any missing Neovim plugins from the lockfile. Use `install.ps1` instead of `install.sh` on native Windows. Installed core binaries and existing plugin revisions are left in place; use `:Lazy update` from Neovim when you intentionally want newer plugin versions. To change the optional-tool selection, run the installer again and make new choices.

To only link the configs and aliases (without downloading tools or installing plugins):

```bash
"$HOME/.local/share/terminal/install.sh" --config-only
```

Native Windows: `& "$HOME\.local\share\terminal\install.ps1" -ConfigOnly`.

## Optional tools and updates

The selector offers these optional tools. Their installation/update channels are chosen to track production/stable versions:

| Menu option | Install and weekly update behavior |
| --- | --- |
| Rust | `rustup` stable toolchain; Termux uses its stable `rust` package |
| Go | Latest stable `go.dev` archive; Termux uses its `golang` package |
| Bun | Official installer; `bun upgrade --stable` |
| Node.js | Latest LTS release; Termux uses `nodejs-lts` |
| uv | Official standalone installer and `uv self update` |
| Python | Latest stable Python managed by uv; Termux uses its `python` package |
| Composer | Official stable self-updater; Termux uses its `composer` package. Native Windows requires existing PHP |
| PHP | OS package manager/Homebrew; Termux uses `pkg`. Native Windows requires PHP already on PATH |
| Clang / GCC | Linux package manager/Homebrew; Termux offers Clang only. Native Windows requires an existing compiler |
| OpenAI Codex | Official stable installer for supported Windows/Linux/macOS hosts |
| OpenCode | Official release binary for supported Windows/Linux/macOS hosts |
| Claude Code | Official **stable** installer/channel |
| Cursor CLI | Official CLI (`agent` command); auto-updates. Native Windows supports x64 and ARM64 |

Selected tools are recorded in `~/.config/terminal/selected-tools` (or the matching user config directory on Windows). Selected tools are checked weekly by a user-level systemd timer (Linux/WSL), launchd agent (macOS), or Task Scheduler task (native Windows). Termux does not provide a dependable scheduler in the base app, so updates there are manual. Run an update immediately with:

```bash
"$HOME/.local/share/terminal/update.sh"
```

Native Windows: `& "$HOME\.local\share\terminal\install.ps1" -WeeklyUpdate`.

Linux PHP/compiler updates are managed by the OS package manager. A scheduled update cannot prompt for a password: it uses `sudo -n` only, and logs/defer system-package upgrades if administrator authorization is not already available. Termux uses user-owned `pkg` packages and never invokes `sudo`; native Windows only offers existing PHP/compiler installations. User-local tool updates continue normally. No sudo credentials are saved.

`--no-ui` installs the core setup without optional selections, for scripts or non-interactive sessions. On Linux/macOS, the installer UI needs no Go when a matching release binary is available; building it from source requires Go 1.24 or later. Native Windows uses PowerShell and a prebuilt `.exe` selector.

### AI CLI theme defaults and compatibility

Selecting an AI CLI applies the Charm appearance automatically; the selector has no theme option. Colors are drawn from the same palette as `nvim/lua/themes/charm_dark.lua` and `starship.toml`, within each CLI's supported theming surface:

| CLI | Automatic Charm setup | What the CLI allows |
| --- | --- | --- |
| Claude Code | Installs `~/.claude/themes/charm-dark.json` and selects `custom:charm-dark` | Custom UI colors |
| OpenAI Codex | Installs `~/.codex/themes/charm-dark.tmTheme` and selects it in `config.toml` | Syntax highlighting and diffs; the rest of its TUI keeps Codex's own colors |
| OpenCode | Legacy `tui.json`/`tui.jsonc` gets `themes/charm.json`; current `cli.json` gets the v2 `themes/charm-v2.json` | Custom UI theme |
| Cursor CLI | Sets `COLORFGBG=15;0` in the generated shell configuration | Dark/light mode only; Cursor controls its accent colors |

Existing agent config values are preserved; changed config files are backed up. Cursor cannot currently be given the exact custom palette through its CLI config, and Codex only exposes syntax/diff themes, so exact color matching is limited by those tools.

The selector detects the host OS, CPU architecture, Linux libc, package manager, and required system tools before enabling choices. Unsupported or unavailable items are disabled with the reason shown in the menu; **a** selects only compatible options. WSL is detected as Linux and uses `install.sh`; native Windows uses `install.ps1`.

| Host | Core behavior and optional-tool compatibility |
| --- | --- |
| Linux/glibc or macOS, amd64 or arm64 | Full core setup; supported optional tools are offered |
| WSL on Linux/glibc, amd64 or arm64 | Same as Linux; Bash installer and Linux package channels |
| Native Windows amd64 | PowerShell core setup and compatible Windows optional tools |
| Native Windows arm64 | Neovim, Starship, and bat core; lsd, Glow, and Pop are skipped unless already installed. Bun, Cursor CLI, and other supported options remain available |
| Termux on Android arm64 | Neovim, Starship, lsd, bat, Glow, Rust, Go, Node.js LTS, Python, PHP, Composer, and Clang use `pkg`; Pop is built locally with a temporary Go dependency (kept if Go is selected) |
| Termux Bun, uv, GCC, or AI CLIs | Disabled with an Android/Termux-specific reason; no supported package or upstream build is available |
| musl/Alpine, unknown Linux libc, unsupported CPU, or other OS | Core setup is blocked and optional tools are disabled; `--config-only` remains available where the shell can run it |
| Missing PHP/compiler on Linux | Offered only with `apt`, `dnf`, or `pacman` and `sudo`; approval is requested interactively |
| Missing PHP/Clang or GNU GCC on macOS | Homebrew is required; an existing Apple Clang can use the Xcode toolchain |
| Missing PHP or compiler on native Windows | Disabled; this installer does not silently install a system-wide toolchain |

These are explicit supported targets, not a promise that every POSIX-like OS or processor works. If an upstream tool adds or drops an architecture, the menu remains conservative until the installer has a verified install path for it.

## What you get

### Neovim + NvChad

- User-local stable Neovim binary on desktop hosts; Termux uses its `pkg` package.
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

The installer ensures `lsd`, `bat`, [Glow](https://github.com/charmbracelet/glow), and [Pop](https://github.com/charmbracelet/pop) are available when supported (Termux installs the first three with `pkg`; Windows ARM64 skips tools without an ARM64 build). It adds these aliases where the shell supports them:

```bash
ls   # lsd -AFL --group-dirs=first
cat  # bat
```

- **Glow** renders Markdown in the terminal: `glow README.md`.
- **Pop** is Charmbracelet’s terminal email client. It needs SMTP or Resend credentials before it can send mail; installation does not authenticate or send anything.

## Supported systems

- Linux with glibc: x86_64 and ARM64 (including WSL)
- macOS: Intel and Apple Silicon
- Native Windows: x64 core; ARM64 core with lsd, Glow, and Pop unavailable unless already installed
- Termux on Android: ARM64

Other OSes, architectures, and Linux libc variants are detected and blocked rather than guessed compatible. Nerd Font glyphs are recommended for the prompt and Neovim UI. Core executables and runtimes are user-local except Termux core packages, which are installed in the Termux user environment. On Linux, selecting missing PHP/Clang/GCC uses apt, dnf, or pacman and requires interactive `sudo`; on macOS it uses Homebrew. On Termux, compatible packages use `pkg` without `sudo`. On Arch-based systems, initial package installation is supported, but unattended weekly system-package upgrades are intentionally not run.

## Layout

```text
.
├── install.sh             # Linux/macOS/WSL/Termux bootstrap and updates
├── install.ps1            # Native Windows bootstrap, selection, and updates
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
