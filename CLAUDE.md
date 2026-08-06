# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Ansible playbook that provisions a single Arch Linux workstation **running Omarchy 4 ("Quattro")**, against `localhost` over a local connection (`inventory`). There is no remote host, no test suite, and no linter configured — the playbook itself is the deliverable and `--check` is the closest thing to a test.

**Omarchy 4 only.** `bootstrap.sh` keys on the `omarchy` pacman package and refuses to run on 3.x. The migration is documented in `PLAN.md`; read it before touching anything that interacts with Omarchy, since it records *why* several roles were deleted rather than fixed.

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

**Two-layer split.** Omarchy 4 owns the desktop (Hyprland via Lua, the Quickshell shell — bar/menu/notifications/lock/OSD, foot, Neovim, fonts, audio, SDDM, themes) **and** several things it did not own in 3.x: the ufw firewall baseline, DNS via `omarchy-dns`, `/etc/docker/daemon.json`, and coding-agent binaries via `mise`. This playbook owns extra packages, VPN/Tor, security hardening, dotfile symlinks, and agent *config*.

**Never modify Omarchy's own files.** On Quattro they live in `/usr/share/omarchy` (pacman-owned); `~/.local/share/omarchy` is only a compatibility symlink, so a `-d` test on it proves nothing about the version.

**The boundary moved, and roles were deleted rather than adapted.** When a Quattro-owned surface overlaps something here, the resolution has consistently been to delete our version — `dns`, `nftables`, `claude_code`, `gemini_cli`, `openai_codex`, `pi_coding_agent`, and `omarchy_monitor_settings` are all gone for this reason. Before adding a role, check whether Quattro already owns that surface.

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
- Merge-safe JSON: `slurp` → `b64decode | from_json` → `combine(..., recursive=True)` → `to_nice_json`, so foreign keys survive. See `roles/skills` (Pi `settings.json`) — which matters because `omarchy-theme-set-pi` writes `.theme` into that same file. `roles/docker_engine` still has the machinery for `/etc/docker/daemon.json` but it is disabled (`docker_manage_daemon_json: false`): Quattro owns that file, and editing it would strand every future Omarchy change in a `.pacnew`.
- `git` clones use `force: false, update: false` — the dotfiles repo is cloned once and then owned by the user; the playbook never pulls over local edits.

**Dotfiles.** `https://github.com/henningmyhrvold/omarchy-dotfiles` is cloned to `~/src/omarchy-dotfiles`; `roles/dotfiles`, `roles/zsh`, and `roles/skills` symlink out of that checkout. Config files themselves live in that repo, not here.

**Coding agents.** Omarchy 4 installs agent binaries itself: `install/user/mise.sh` runs `omarchy-mise-install` for claude, codex, gemini, pi, opencode and others, writing *lazy shims* into `~/.local/bin` that run `mise use -g <pkg>` on first call. This playbook installs none of them. `roles/agents` owns only the config side — removing the legacy `~/.npm-global` installs and PATH lines that would otherwise shadow those shims, plus Pi extensions (which mise does not manage).

PATH order is the thing to watch: Quattro *appends* `~/.local/bin` and activates mise, so anything that *prepends* `~/.npm-global/bin` wins over both. That is why the cleanup tasks exist and why they must run before any task resolves an agent binary. The zsh half of that line lives in the dotfiles repo, not here — `roles/agents` can only warn about it.

**Firewall.** `roles/firewall` adds rules to Quattro's ufw baseline and must never reset ufw or set default policies: Omarchy's `install/config/firewall.sh` establishes deny-in/allow-out, LocalSend on 53317, the `ufw-docker` after.rules block, and container→host DNS allowances that Docker's own DNS depends on. The role also disables a leftover `nftables.service` if it finds one, since both units flush and reload the kernel ruleset.

## Repository state to be aware of

- **Roles present but not wired into `playbook.yml`:** `npm_global`, `permissions`, `pi_extensions`. Dormant, not dead — check before deleting. Note `roles/permissions/tasks/main.yml` does not parse as YAML (nested single quotes on the `line:` at line 31); it is a long-standing bug, harmless only because the role is unwired.
- **`roles/links` is a no-op** as configured: it loops over `regular_links`, which `config.yml` never defines.
- **Username is baked in.** `config.yml` sets `target_user: henning`; `rename.sh` does a repo-wide `git grep | sed` to change it. `roles/tor_proxy/defaults/main.yml` hardcodes `henning` instead of deriving from `target_user` — new roles should use the `target_user | default(...)` preamble.
- **`roles/wireguard` still defaults `wg_dns_provider: auto`**, which installs `openresolv` when `/etc/wireguard/wg0.conf` contains a `DNS=` line. On Quattro, which standardises on systemd-resolved, that may conflict — unverified. Previously the `dns` role removed `openresolv` behind wireguard's back; with that role gone, nothing does.
- **No Ansible Vault.** Nothing here holds secrets: `roles/wireguard` deploys tooling, a killswitch, and `wg-on`/`wg-off` helpers but expects `/etc/wireguard/wg0.conf` to be placed by hand, and only enables `wg-quick@wg0` if that file exists. Keep it that way — do not add credentials to `config.yml`.
- `.gitignore` excludes `.claude/`, so `.claude/settings.local.json` is untracked. It still pre-approves `filesystem`/`ref`/`docker` MCP servers that no longer exist — harmless, but misleading.
