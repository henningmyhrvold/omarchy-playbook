#!/bin/bash
set -e

DOTFILES_PLAYBOOK="$HOME/src/omarchy-playbook"
DOTFILES="$HOME/src/omarchy-dotfiles"
DOTSSH="$HOME/.ssh"

# Verify Omarchy 4 ("Quattro") is installed.
#
# Keyed on the package rather than ~/.local/share/omarchy: on Quattro that path
# is only a compatibility symlink to /usr/share/omarchy, so `-d` succeeds on
# both 3.x and 4.x and proves nothing about the version. The `omarchy` package
# is what actually defines the Quattro layout.
if ! command -v pacman &> /dev/null; then
    echo "Error: pacman not found. This playbook targets Arch/Omarchy."
    exit 1
fi

if ! pacman -Q omarchy &> /dev/null; then
    echo "Error: Omarchy 4 (Quattro) not detected — the 'omarchy' package is missing."
    if [ -d "$HOME/.local/share/omarchy" ]; then
        echo "An older Omarchy appears to be installed (version: $(cat "$HOME/.local/share/omarchy/version" 2>/dev/null || echo unknown))."
        echo "This playbook no longer supports Omarchy 3.x. Upgrade first:"
        echo "    omarchy-upgrade-to-quattro"
    else
        echo "Install Omarchy 4 first."
    fi
    exit 1
fi

echo "Omarchy detected: $(pacman -Q omarchy)"

# Full system upgrade
echo "Upgrading system packages..."
sudo pacman -Syu --noconfirm

# Install Ansible if not present
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    sudo pacman -S --noconfirm ansible
    hash -r
fi

# Create SSH key if needed
if [ ! -f "$DOTSSH/id_ed25519" ]; then
    echo "Creating SSH Ed25519 key..."
    mkdir -p "$DOTSSH"
    chmod 700 "$DOTSSH"
    ssh-keygen -t ed25519 -f "$DOTSSH/id_ed25519" -N "" -C "$USER@$(uname -n)"
    cat "$DOTSSH/id_ed25519.pub" >> "$DOTSSH/authorized_keys"
    chmod 600 "$DOTSSH/authorized_keys"
    echo "SSH key created."
fi

# Install Ansible requirements
echo "Installing Ansible requirements..."
ansible-galaxy install -r "$DOTFILES_PLAYBOOK/requirements.yml"

# Run playbook
echo "Running Ansible playbook..."
cd "$DOTFILES_PLAYBOOK"
ansible-playbook playbook.yml --diff -v --ask-become-pass

echo "Done!"
