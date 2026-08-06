# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Ansible playbook that provisions a single Arch Linux workstation **running Omarchy**, against `localhost` over a local connection (`inventory`). There is no remote host, no test suite, and no linter configured — the playbook itself is the deliverable and `--check` is the closest thing to a test.

## Commands

```bash
./bootstrap.sh                                   # full run (upgrades system, installs ansible, galaxy deps, runs playbook)
ansible-playbook playbook.yml --ask-become-pass  # same run without the bootstrap preamble

ansible-playbook playbook.yml --tags zsh                    # one role
ansible-playbook playbook.yml --tags "docker,claude-code"   # several
ansible-playbook playbook.yml --tags packages               # cross-cutting tag (spans roles)
ansible-playbook playbook.yml --skip-tags packages

ansible-playbook playbook.yml --check --diff     # dry run — the primary way to validate a change
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-tags
ansible-playbook playbook.yml --list-tasks --tags zsh
ansible-playbook playbook.yml -vv                # verbose; the dns role prints extra debug when verbosity > 0

ansible-galaxy install -r requirements.yml       # community.general, kewlfft.aur, community.docker
```

Most roles are not safely testable with `--check` alone: they `register` command output and branch on it, so a check run will report failures on tasks whose prerequisites are stubbed. Read the diff output rather than trusting the exit code.

`python concat_gipity.py` dumps the repo into `project_code.txt` (file tree + all non-binary sources, honoring `.gptignore`) for pasting into an LLM. It is a standalone utility, unrelated to provisioning.

## Architecture

**Two-layer split.** Omarchy owns the desktop (Hyprland, Waybar, Walker, Mako, Neovim, fonts, audio, SDDM, terminal theming). This playbook owns packages, system services, security hardening, Docker, AI CLIs, and dotfile symlinks. **Never modify `~/.local/share/omarchy/`** — layer on top of it. `bootstrap.sh` aborts if Omarchy is not installed.

**Variable flow.** `playbook.yml` loads `config.yml` as its only `vars_files`. Roles declare their own `defaults/main.yml`, so anything in `config.yml` overrides a role default with no extra wiring. `config.yml` is the single place a user edits; roles should read from role-prefixed defaults rather than reaching for `config.yml` values directly (`target_user` and `dotfiles_home` are the deliberate exceptions).

**Self-contained roles.** Every role installs its own packages, creates its own directories, and makes its own symlinks, so `--tags <role>` is always a complete standalone run. This means duplication across roles (multiple roles install `nodejs`/`npm`, define their own `npm_global_prefix`, and re-implement the AUR sudoers dance) — that duplication is intentional; don't refactor it into a shared role without a reason.

**Privilege model.** `playbook.yml` sets `become: true` at play level, so *everything* runs as root by default. Any task touching the user's home must add `become_user: "{{ <role>_user }}"`. The standard role-default preamble is:

```yaml
<role>_user: "{{ target_user | default(ansible_facts['user_id']) }}"
<role>_home: "/home/{{ <role>_user }}"
```

**Tags.** Tags live in two places: `playbook.yml` assigns role-level tags (applied to every task in the role), and each task carries its own tag list. Cross-cutting task tags (`packages`, `folders`, `config`, `symlinks`, `verify`, `services`) let you run one concern across all roles. When adding a role, set both.

**AUR installs** use `kewlfft.aur.aur` with `use: yay` under `become_user`, which cannot prompt for a sudo password. The established pattern writes a temporary `/etc/sudoers.d/<role>-aur-temp` NOPASSWD rule (validated with `visudo -cf`), installs, then removes the rule — see `roles/zsh`, `roles/vscode`, `roles/omarchy_monitor_settings`. `roles/aur_packages` predates this and instead edits `/etc/sudoers` directly with a `.pacman_backup` copy; prefer the `sudoers.d` pattern for new work. `roles/aur` only asserts that `yay` exists (Omarchy ships it).

**Idempotency idioms** used throughout, worth matching:
- `changed_when: false` + `failed_when: false` on probe commands (`which yay`, `--version` checks).
- Stat-then-template so user-edited files are never clobbered — `roles/tor_proxy` deploys its systemd unit on first run only.
- Merge-safe JSON: `slurp` → `b64decode | from_json` → `combine(..., recursive=True)` → `to_nice_json`, so foreign keys survive. See `roles/docker_engine` (`/etc/docker/daemon.json`) and `roles/skills` (Pi `settings.json`).
- `git` clones use `force: false, update: false` — the dotfiles repo is cloned once and then owned by the user; the playbook never pulls over local edits.

**Dotfiles.** `https://github.com/henningmyhrvold/omarchy-dotfiles` is cloned to `~/src/omarchy-dotfiles`; `roles/dotfiles`, `roles/zsh`, and `roles/skills` symlink out of that checkout. Config files themselves live in that repo, not here.

**MCP / Claude Code.** `roles/claude_code` probes `docker ps` for containers named `mcp-*` and templates `.mcp.json` into `~`, `~/src`, and `~/projects` containing only the servers it found running. The roles that *created* those containers (`docker_mcp`, `mcp_filesystem`, `mcp_ref`) were deleted in commit `4d3e6e7`, so the probe currently matches nothing and the role writes an empty `mcpServers` block. Re-adding MCP means restoring container roles, not just editing the template.

## Repository state to be aware of

- **`README.md` is stale.** Its role table lists roles that no longer exist (`nvim`, `tmux`, `hyprland`, `ghostty`, `audio`, `fonts`, `sddm`, `mcp_*`, `claude_desktop_wayland`) and mentions `paru`; the repo uses `yay`. `playbook.yml` is the source of truth for what actually runs.
- **Roles present but not wired into `playbook.yml`:** `npm_global`, `permissions`, `pi_extensions`, and `omarchy_monitor_settings` (commented out). They are dormant, not dead — check before deleting.
- **`roles/links` is a no-op** as configured: it loops over `regular_links`, which `config.yml` never defines.
- **Username is baked in.** `config.yml` sets `target_user: henning`; `rename.sh` does a repo-wide `git grep | sed` to change it. `roles/tor_proxy/defaults/main.yml` hardcodes `henning` instead of deriving from `target_user` — new roles should use the `target_user | default(...)` preamble.
- **No Ansible Vault.** Nothing here holds secrets: `roles/wireguard` deploys tooling, a killswitch, and `wg-on`/`wg-off` helpers but expects `/etc/wireguard/wg0.conf` to be placed by hand, and only enables `wg-quick@wg0` if that file exists. Keep it that way — do not add credentials to `config.yml`.
- `.gitignore` excludes `.claude/`, so `.claude/settings.local.json` (which pre-approves the `filesystem`/`ref`/`docker` MCP servers) is untracked.
