# Omarchy Workstation Playbook

Ansible playbook for configuring my Arch Linux workstation on top of **Omarchy 4 ("Quattro")**.

> **Requires Omarchy 4.** `bootstrap.sh` refuses to run on Omarchy 3.x. Upgrade with
> `omarchy-upgrade-to-quattro` first. See [PLAN.md](PLAN.md) for what the migration changed.

## Layering

Omarchy owns the desktop and, as of Quattro, a good deal more:

| Omarchy 4 owns | This playbook owns |
|---|---|
| Hyprland (Lua config), Quickshell shell (bar, menu, notifications, lock, OSD) | Extra packages from the official repos and AUR |
| foot, Neovim, fonts, audio, SDDM, themes | Zsh + Oh-My-Zsh + Powerlevel10k |
| Firewall baseline (ufw + ufw-docker) | Extra firewall rules |
| DNS (`omarchy-dns`, systemd-resolved) | WireGuard, Tor SOCKS proxy |
| `/etc/docker/daemon.json` | Docker service, group membership, Python bindings |
| Coding-agent binaries via `mise` | Agent skills and Pi extensions |
| | VSCode, Go, dotfile symlinks |

Nothing here writes into Omarchy's own files. On Quattro those live in
`/usr/share/omarchy` (pacman-owned); `~/.local/share/omarchy` is a compatibility symlink.

## Quick Start

```bash
# Change username to yours
./rename.sh

# Run the playbook
./bootstrap.sh
```

## Usage

```bash
# Run everything
./bootstrap.sh

# Run specific roles (they're self-contained)
ansible-playbook playbook.yml --tags zsh
ansible-playbook playbook.yml --tags "docker,agents"

# Cross-cutting tags spanning roles
ansible-playbook playbook.yml --tags packages
ansible-playbook playbook.yml --skip-tags packages

# Dry run — the primary way to validate a change
ansible-playbook playbook.yml --check --diff

# Inspect
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-tags
```

## Roles

Each role is self-contained: it installs its own packages, creates its own
directories, and makes its own symlinks, so `--tags <role>` is always a
complete standalone run.

| Role | Description | Tag |
|------|-------------|-----|
| `pacman` | Extra packages from the official repos | `pacman` |
| `aur` | Asserts `yay` is available (Omarchy ships it) | `aur` |
| `aur_packages` | Extra packages from the AUR | `aur-packages` |
| `zsh` | Zsh with Oh-My-Zsh and Powerlevel10k (does not `chsh`) | `zsh` |
| `vscode` | VSCode with Wayland flags, extensions, settings | `vscode` |
| `go` | Go toolchain and `GOPATH` workspace | `go` |
| `firewall` | Extra ufw rules on top of Omarchy's baseline | `firewall` |
| `wireguard` | WireGuard tooling, killswitch, `wg-on`/`wg-off` | `wireguard` |
| `tor_proxy` | Tor SOCKS proxy with `tor-on`/`tor-off` | `tor_proxy` |
| `docker_engine` | Docker service, docker group, Python bindings | `docker` |
| `agents` | Coding-agent config: legacy cleanup + Pi extensions | `agents` |
| `skills` | Symlinks agent skills into Claude Code and Pi | `skills` |
| `folders` | Creates directories listed in `config.yml` | `folders` |
| `dotfiles` | Clones the dotfiles repo and symlinks configs | `dotfiles` |
| `links` | Extra symlinks from `regular_links` | `links` |

Dormant roles, present but not in `playbook.yml`: `npm_global`, `permissions`, `pi_extensions`.

### Coding agents

Omarchy 4 installs agent binaries itself through `mise` — `omarchy-mise-install`
writes lazy shims into `~/.local/bin` for `claude`, `codex`, `gemini`, `pi`,
`opencode` and others. This playbook no longer installs them. Pick a default with:

```bash
omarchy-default-agent claude   # or pi, codex, gemini, opencode …
```

The `agents` role removes the older npm-global installs and PATH entries that
would otherwise shadow those shims, and installs Pi extensions.

## Configuration

Edit `config.yml` — it is the single file you change. Role defaults live in
`roles/<role>/defaults/main.yml` and anything in `config.yml` overrides them.

```yaml
# Official repos
pacman_installed_packages:
  - package-name

# AUR
aur_installed_packages:
  - aur-package-name

# Extra firewall rules (Omarchy owns the deny-in baseline)
firewall_allowed_tcp_ports: [22]

# Dotfile symlinks
dotfiles_links:
  - { src: "app/config", dest: ".config/app/config" }
```

## Requirements

- Arch Linux with **Omarchy 4**
- Ansible (`sudo pacman -S ansible`) — `bootstrap.sh` installs it if missing
- sudo privileges

## Companion Repository

[omarchy-dotfiles](https://github.com/henningmyhrvold/omarchy-dotfiles) — the actual
config files that get symlinked, plus the Omarchy customization scripts. Note the
playbook clones it with `update: false`, so it never pulls over local edits; update
it manually with `git -C ~/src/omarchy-dotfiles pull`.
