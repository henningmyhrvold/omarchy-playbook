#!/bin/bash
set -e

DOTFILES_PLAYBOOK="$HOME/src/omarchy-playbook"
DOTFILES="$HOME/src/omarchy-dotfiles"
DOTSSH="$HOME/.ssh"

# Verify Omarchy is installed
if [ ! -d "$HOME/.local/share/omarchy" ]; then
    echo "Error: Omarchy not detected. Install Omarchy first."
    exit 1
fi

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
