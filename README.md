# Dotfiles-Playbook

Ansible playbook for configuring my Arch Linux workstation.

## Key Feature: Self-Contained Roles

Each role is **fully self-contained** and can be run independently. This means:
- Each role installs its own packages
- Each role creates its own directories
- Each role sets up its own symlinks
- You can pick and choose which roles to run

## Quick Start

```bash
# Change username to yours
git grep -l henning | xargs sed -i 's/henning/youruser/g'

# Run the playbook
./bootstrap.sh
```

## What It Does

- Installs packages from official repos (pacman) and AUR (paru)
- Sets up Hyprland (Wayland compositor), Waybar, Wofi, etc.
- Configures Zsh with Oh-My-Zsh and Powerlevel10k
- Links dotfiles from the [dotfiles repo](https://github.com/henningmyhrvold/dotfiles.git)
- Sets up Docker, development tools, and Claude AI tools

## Structure

```
.
├── bootstrap.sh      # Entry point - installs requirements and runs playbook
├── playbook.yml      # Main Ansible playbook
├── config.yml        # All configuration variables
├── inventory         # Ansible inventory (localhost)
├── requirements.yml  # Ansible Galaxy collections
├── roles/            # Ansible roles (all self-contained)
└── ansible.cfg       # Ansible configuration
```

## Usage

```bash
# Run everything
./bootstrap.sh

# Run specific roles (they're self-contained!)
ansible-playbook playbook.yml --tags "zsh"
ansible-playbook playbook.yml --tags "nvim"
ansible-playbook playbook.yml --tags "hyprland"
ansible-playbook playbook.yml --tags "docker"

# Run multiple roles
ansible-playbook playbook.yml --tags "zsh,nvim,tmux"

# Skip certain roles
ansible-playbook playbook.yml --skip-tags "mcp"

# Dry run
ansible-playbook playbook.yml --check

# Verbose output
ansible-playbook playbook.yml -v
```

## Self-Contained Roles

Each of these roles can be run independently:

| Role | Description | Tag |
|------|-------------|-----|
| `zsh` | Zsh with Oh-My-Zsh and Powerlevel10k | `zsh` |
| `nvim` | Neovim with LazyVim | `nvim` |
| `tmux` | Tmux with TPM | `tmux` |
| `ghostty` | Ghostty terminal | `ghostty` |
| `hyprland` | Hyprland + Waybar + Wofi + Dunst | `hyprland` |
| `audio` | PipeWire audio stack | `audio` |
| `fonts` | System fonts | `fonts` |
| `sddm` | Display manager | `sddm` |
| `docker_engine` | Docker + BuildKit | `docker` |
| `claude_code` | Claude Code CLI | `claude-code` |
| `claude_desktop_wayland` | Claude Desktop (Wayland) | `claude-desktop` |
| `mcp_filesystem` | MCP Filesystem server | `mcp-filesystem` |
| `mcp_github` | MCP GitHub server | `mcp-github` |
| `mcp_ref` | MCP Context7 server | `mcp-ref` |

## Adding Packages

Edit `config.yml` for packages not covered by self-contained roles:

```yaml
# Official repos
pacman_installed_packages:
  - package-name

# AUR
aur_installed_packages:
  - aur-package-name
```

Or override role defaults:

```yaml
# Add to config.yml to override zsh role packages
zsh_pacman_packages:
  - zsh
  - zsh-autosuggestions
  - zsh-syntax-highlighting  # Added!
```

## Adding Dotfile Symlinks

Edit `config.yml`:

```yaml
dotfiles_links:
  - { src: "app/config", dest: ".config/app/config" }
```

## Requirements

- Arch Linux
- Ansible (`sudo pacman -S ansible`)
- sudo privileges

## Companion Repository

[dotfiles](https://github.com/henningmyhrvold/dotfiles.git) - Contains the actual configuration files that get symlinked.
