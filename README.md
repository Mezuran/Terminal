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

The installer works in your home directory and does **not** use `sudo`. It downloads missing tools from their upstream releases, sets up the configurations, then installs the Neovim plugins pinned by the lockfile. Open a new terminal when it finishes.

> **Backups, not surprises:** Existing `~/.config/nvim` and `~/.config/starship.toml` are moved to timestamped `.backup-*` paths before the managed symlinks are created. Existing shell startup files are preserved and backed up before a small, marked setup block is appended. Re-running the installer is safe.

To update the setup later:

```bash
git -C "$HOME/.local/share/terminal" pull --ff-only && "$HOME/.local/share/terminal/install.sh"
```

This refreshes the managed configs and bootstraps any missing Neovim plugins from the lockfile. Installed tool binaries and existing plugin revisions are left in place; the installer downloads a binary only when the command is missing. Use `:Lazy update` from Neovim when you intentionally want newer plugin versions.

To only link the configs and aliases (without downloading tools or installing plugins):

```bash
"$HOME/.local/share/terminal/install.sh" --config-only
```

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

Nerd Font glyphs are recommended for the prompt and Neovim UI. The installer places missing executables in `~/.local/bin` and Neovim in `~/.local/opt`; no system packages are changed.

## Layout

```text
.
├── install.sh             # User-local bootstrap and config installer
├── nvim/                  # NvChad configuration and Charm themes
├── shell/                 # Bash/Zsh and Fish aliases
├── starship.toml          # Charm left/right prompt
├── LICENSE                # Apache License 2.0
└── THIRD_PARTY_NOTICES.md # Upstream project notes
```

## License

The configuration and installer are available under the [Apache License 2.0](LICENSE); copyright details are in [NOTICE](NOTICE). Neovim, NvChad, Starship, and the installed tools remain separate upstream projects under their respective licenses.
