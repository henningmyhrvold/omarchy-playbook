# PLAN.md — Migrating this playbook to Omarchy 4 "Quattro"

**Status:** planning only. No files other than this one have been changed.

**Baseline:** this laptop runs Omarchy **3.8.4** (`~/.local/share/omarchy/version`, git `v3.8.4-4-gedce5809`).
**Target:** Omarchy **4.0.0.alpha** (`quattro` branch `version` file), now in beta.

**Decisions taken** (from review of the four questions):

| # | Decision |
|---|---|
| 1 | **Hard-cut to Quattro.** No version gating; `bootstrap.sh` refuses to run on Omarchy < 4. |
| 2 | **Split agent ownership:** mise (Omarchy) owns agent *binaries*; Ansible keeps *config* — skills symlinks, settings files, extensions. |
| 3 | **Adopt ufw, drop the `nftables` role.** |
| 4 | **Retire the `dns` role.** |

---

## 1. How this was verified

Claims below are grounded in the actual Quattro sources, not release notes. Method:

- Full `quattro` file tree via the GitHub API (1,394 blobs) — used to diff `bin/` and locate new `etc/` files.
- Raw file fetches via the jsDelivr GitHub mirror (`raw.githubusercontent.com` returns 403 here).
- Package manifests diffed against this machine's live Omarchy 3.8.4 lists in `~/.local/share/omarchy/install/`.
- The `[omarchy]` pacman repo databases for the `stable` and `edge` channels, fetched from `https://pkgs.omarchy.org/<channel>/x86_64/omarchy.db` and decompressed (zstd), to check package *availability* rather than default-install status.

That last check mattered — see §2.1.

**Sources:** [Quattro PR #6231](https://github.com/basecamp/omarchy/pull/6231) · [basecamp/omarchy @ quattro](https://github.com/basecamp/omarchy/tree/quattro) · [Omarchy 4 is a bigger change than I expected](https://www.pbjorklund.com/articles/omarchy-4-quattro/) · [Releases](https://github.com/basecamp/omarchy/releases) · [The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual)

---

## 2. What Quattro changes that actually touches this repo

Quattro rewrites ~1,225 files, but most of it (Quickshell bar, Lua Hyprland configs, theme engine) is invisible to us because this repo deliberately does not manage the desktop surface. The changes that *do* reach us:

### 2.1 Omarchy becomes package-backed; `~/.local/share/omarchy` becomes a symlink

`omarchy-upgrade-to-quattro` replaces the git checkout with `ln -sfn /usr/share/omarchy ~/.local/share/omarchy`. `OMARCHY_PATH` is now `/usr/share/omarchy` and the commands ship as `/usr/bin/omarchy-*` from the `omarchy` package. Channels are `stable`/`rc`/`edge` at `https://pkgs.omarchy.org/<channel>/$arch`; the upgrade also installs `omarchy-keyring` and `omarchy-settings`.

**Consequence for us: almost none.** `bootstrap.sh:9` uses `[ ! -d "$HOME/.local/share/omarchy" ]`, and `-d` follows symlinks, so the guard still passes. It should still be tightened (§3.1) because it no longer proves anything about the *version*.

**Correction worth recording:** `claude-code` is **absent from Quattro's `omarchy-base.packages`**, which on its own looks like `roles/claude_code/tasks/main.yml:9` is broken. It is not. Querying the repo databases shows `claude-code` is **still present in `[omarchy]` in both `stable` and `edge`**. It is simply no longer installed by default. `pacman -S claude-code` continues to work on Quattro. Do not "fix" that task.

### 2.2 Coding agents move to mise

Quattro's `install/user/mise.sh` provisions `codex`, `claude`, `crush`, `gemini`, `gh`, `copilot`, `opencode`, `pi`, `omp`, `grok`, `playwright`, `ghui`, `hunk` — all through `omarchy-mise-install`. `mise` is in `omarchy-base.packages`.

`omarchy-mise-install` does **not** eagerly install. It writes a lazy wrapper to `~/.local/bin/<command>`:

```bash
#!/bin/bash
mise use -g "<package>" || exit 1
exec mise x "<package>" -- "<bin>" "$@"
```

`omarchy-default-agent <name>` then runs `mise use -g <package>` and records the choice in `~/.config/omarchy/defaults/agent`.

**PATH order is the whole ballgame here**, and it currently resolves against us:

- Quattro *appends* `~/.local/bin` (`default/bash/envs`: `export PATH="$PATH:$HOME/.local/bin"`).
- `default/bash/init` runs `eval "$(mise activate bash)"`, which prepends the mise shim dir.
- `roles/pi_coding_agent/tasks/main.yml:67` and `roles/gemini_cli/tasks/main.yml:67` append `export PATH="$HOME/.npm-global/bin:$PATH"` to the **end** of `~/.bashrc`, so it runs last and **prepends** — shadowing both the mise shims and the `~/.local/bin` wrappers.

So today's roles would win, silently, and you would be running npm-pinned agents while believing Omarchy manages them.

**Pre-existing bug found along the way:** both roles write that PATH line to `~/.bashrc` only, but `roles/zsh` makes zsh the interactive shell (via the terminal, not `chsh`). In zsh the line never applies at all. This is already broken on 3.8.4.

### 2.3 Quattro now ships `/etc/docker/daemon.json`

New file in Quattro (`etc/docker/daemon.json`):

```json
{
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "5" },
    "dns": ["172.17.0.1"],
    "bip": "172.17.0.1/16"
}
```

These values are **load-bearing**, not cosmetic. They pair with `etc/systemd/resolved.conf.d/20-docker-dns.conf` (`DNSStubListenerExtra=172.17.0.1`) and with ufw rules in `install/config/firewall.sh` that allow container→host DNS on `172.17.0.1:53`.

`roles/docker_engine/tasks/main.yml:59-85` slurps that file, merges `features.buildkit`, and writes it back. The merge is `combine(recursive=True)`, so Omarchy's keys **do** survive the write. The damage is subtler: the file is now package-owned, so once we modify it, future `omarchy-settings` updates land as `/etc/docker/daemon.json.pacnew` and are silently ignored. Omarchy's future Docker DNS/bip changes would never reach the running system.

Separately, `features.buildkit` is **obsolete** — BuildKit has been the default builder since Docker 23, and Arch ships 28.x.

### 2.4 NetworkManager replaces iwd, and Omarchy owns DNS

Package diff (v3.8.4 base → Quattro base): **added** `networkmanager`, **removed** `iwd`, `impala`.

This flips a dormant branch in our `dns` role into an active one. `roles/dns/tasks/main.yml:93-103` is guarded by `when: nm_installed`. On Omarchy 3 there is no NetworkManager, so it never ran. On Quattro it *will* run, writing `/etc/NetworkManager/conf.d/99-dns.conf` with `[main] dns=systemd-resolved` and firing the `restart NetworkManager` handler **mid-play**.

Meanwhile Quattro ships `omarchy-dns`, which manages `/etc/NetworkManager/conf.d/20-omarchy-dns.conf` and **overwrites `/etc/systemd/resolved.conf` wholesale** with `tee` for each provider (Cloudflare/Google/DHCP/Custom).

The two do not collide on the same key (`[main] dns=` vs `[global-dns-domain-*] servers=`), and `99-` sorts after `20-`, but we would be changing NetworkManager's resolver *plugin mode* underneath a tool that assumes it owns the stack — and restarting NM from inside a playbook run.

Also note `omarchy-upgrade-to-quattro` already does `ln -snf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf`, which is exactly what our role's resolv.conf task does. Redundant.

### 2.5 ufw remains the firewall, and Docker DNS depends on it

Quattro base still ships `ufw` and `ufw-docker`; `nftables` is **not** in the manifest. `install/config/firewall.sh` sets default-deny inbound, opens LocalSend (53317/tcp+udp), installs the `ufw-docker` `after.rules` block, and adds the container→host DNS allowances.

`roles/nftables/tasks/main.yml:16-18` enables `nftables.service`. Running both `ufw.service` and `nftables.service` means whichever starts last flushes and reloads the ruleset. This conflict already exists on Omarchy 3 — Quattro just raises the cost, because Docker's DNS now breaks if the ufw rules are not in force.

### 2.6 Omarchy now themes Claude Code and Pi

New: `omarchy-theme-set-claude` writes `~/.claude/themes/omarchy.json` and, with `--activate`, `jq '.theme = "custom:omarchy"'` into `~/.claude/settings.json`. `omarchy-theme-set-pi` does the same for `~/.pi/agent/themes/omarchy-system.json` and `~/.pi/agent/settings.json`.

`roles/skills/tasks/main.yml` performs a slurp → `combine(recursive=True)` → full rewrite of `~/.pi/agent/settings.json`. Both sides merge rather than clobber, so **no data loss in either order** — but this is now a shared file with two writers, which is worth knowing before either side changes strategy.

### 2.7 Theme state moved

`~/.config/omarchy/current` → `~/.local/state/omarchy/current`. **This repo never references it**; grep is clean. Flagged only because the companion dotfiles repo may (§6).

### 2.8 Desktop surface changes (informational)

Waybar → Quickshell; Walker → unified menu on `Super+Space`; Alacritty → **foot** as default terminal; Hyprland `.conf` → **Lua**; Mako/SwayOSD/hyprlock/hypridle/swaybg/polkit-gnome removed as separate configs. New first-party apps `omawrite`, `omacut`, `omacalc`; `tensaku` replaces `satty`. New `omarchy-plugin-*` system as the supported extension point.

None of this touches the playbook — `config.yml:94` already records that those directories were handed to Omarchy. It does affect the dotfiles repo (§6) and makes several comments in this repo wrong (§5.1).

---

## 3. Required changes (blocking — the playbook misbehaves on Quattro without these)

### 3.1 `bootstrap.sh` — hard-gate on Omarchy 4

Replace the directory check at `bootstrap.sh:9` with a version assertion. Per decision #1 this should **fail**, not warn, on Omarchy 3.

```bash
if ! pacman -Q omarchy &>/dev/null; then
    echo "Error: Omarchy 4+ not detected (package 'omarchy' missing)."
    echo "Run: omarchy-upgrade-to-quattro"
    exit 1
fi
```

Rationale for keying on the *package* rather than the `version` file: on Quattro the version file lives behind the `/usr/share/omarchy` symlink and the package is the thing that actually defines the layout. Keep a `version`-file fallback read if you want the number in the log line.

**Note:** this makes the playbook unrunnable on this laptop until it is upgraded. That is the accepted consequence of decision #1.

### 3.2 Retire `roles/dns`

Per decision #4. Remove `- { role: dns, ... }` from `playbook.yml:30` and delete `roles/dns/`.

Everything the role still does is now either done by Quattro's upgrade (the `resolv.conf` stub symlink) or owned by `omarchy-dns` (resolver config, NM DNS). The `systemd-resolvconf` install and `openresolv` removal are the only remaining unique behaviours, and both are better handled as a one-line package assertion if you find you need them.

Delete `roles/dns/handlers/main.yml` with it — the `restart NetworkManager` handler is the specific thing we want to stop being able to fire.

**Watch out:** `roles/wireguard` has `wg_dns_provider: auto`, which installs `openresolv`, while the `dns` role removed it (`dns_remove_conflicts: true`). Because `dns` runs before `wireguard` in `playbook.yml`, this is an order-dependent fight that exists today. Removing `dns` **resolves** it in wireguard's favour. Confirm `openresolv` coexists acceptably with Quattro's resolved setup, or set `wg_dns_provider: systemd-resolved`.

### 3.3 Stop managing `/etc/docker/daemon.json`

Set in `config.yml`:

```yaml
docker_manage_daemon_json: false
```

This is a one-line change; the role already gates every daemon.json task on that variable, and it leaves the merge machinery intact should you ever need it back.

Reasons, in order of importance: (a) the file is package-owned now, so our writes create a permanent `.pacnew` blind spot; (b) Omarchy's `dns`/`bip` values are coupled to resolved and ufw config we do not control; (c) the only thing we were adding — `features.buildkit` — is obsolete.

If you later need genuinely custom Docker settings, prefer a **separate drop-in** the package does not own rather than editing `daemon.json`.

Also drop `docker`, `docker-compose`, `docker-buildx` from `docker_pacman_packages` (§4) — Quattro ships all three.

### 3.4 Replace `roles/nftables` with ufw rules

Per decision #3. Remove `- { role: nftables, ... }` from `playbook.yml:31` and delete `roles/nftables/`.

Port the intent of `nftables_allowed_tcp_ports: [22]` to ufw. `community.general.ufw` is already available via the `community.general` collection in `requirements.yml`, so no new dependency:

```yaml
- name: Allow inbound SSH
  community.general.ufw:
    rule: allow
    port: "22"
    proto: tcp
```

**Do not** run `ufw --force reset` or set global defaults from Ansible — Quattro's `install/config/firewall.sh` has already established default-deny-in/allow-out, the LocalSend ports, the docker-DNS allowances, and the `ufw-docker` `after.rules` block. Add rules only; let Omarchy own the baseline.

A small `roles/firewall` that adds your specific allowances is the natural replacement. Keep the existing `nftables_allowed_tcp_ports` / `nftables_allowed_udp_ports` shape as `firewall_allowed_*` so `config.yml` stays declarative.

### 3.5 Split agent ownership: mise for binaries, Ansible for config

Per decision #2. This is the largest change and the one with the most room to get subtly wrong, because of the PATH shadowing in §2.2.

**Remove from `roles/pi_coding_agent` and `roles/gemini_cli`:**
- the `community.general.npm` global install tasks,
- the `nodejs`/`npm` pacman installs (Quattro ships neither by default; mise provides the runtimes it needs),
- the `npm config set prefix` tasks,
- **critically, the `.bashrc` PATH lines** (`roles/pi_coding_agent/tasks/main.yml:67`, `roles/gemini_cli/tasks/main.yml:67`). Leaving these in place is what would silently shadow Omarchy's shims.

Also add a cleanup task to remove any stale `~/.npm-global/bin/{pi,gemini}` from a previous run, otherwise the old binaries linger on PATH via the line you just removed from `.bashrc` — but which is still present in the *existing* `.bashrc` on this machine. Removing the line from the role does not remove it from the file; use `lineinfile: state=absent` for one release cycle.

**`roles/openai_codex`:** it installs the `openai-codex` pacman package. Note the `[omarchy]` repo carries `openai-codex-bin` and Quattro's mise list uses `codex`. Pick one; do not run both.

**`roles/claude_code`:** keep the `claude-code` pacman install (§2.1 — it still resolves). Be aware Omarchy's own default path is `mise use -g claude`, so if you ever run `omarchy-default-agent claude` you will have two Claude Code installs. Decide which is authoritative and stick to it.

**Keep in Ansible:** `roles/skills` in full (it is config, not binaries), pi extensions, and any settings-file management.

**Ordering caveat:** with the binaries lazily installed by shim, `pi`/`gemini` may not exist on disk when Ansible runs. Any role step that shells out to `pi install <ext>` (`roles/pi_coding_agent/tasks/main.yml`, extensions block) must either invoke the `~/.local/bin/pi` wrapper — which triggers the mise install on first call — or be made tolerant of absence. The existing `failed_when: false` on that task means it will *appear* to succeed while doing nothing, which is worse than failing. Make this explicit.

---

## 4. Redundancies to remove

Packages Quattro now ships that this repo installs anyway. Removing them shortens runs and stops us fighting Omarchy over versions.

**From `config.yml` `pacman_installed_packages`:**

| Package | Line | Note |
|---|---|---|
| `jq` | `config.yml:47` | In Quattro base. Already listed in the "removed because Omarchy has it" comment at `config.yml:40`, then re-added below — a standing inconsistency. |
| `bat` | `config.yml:50` | Same as above: named in the comment, still in the list. |
| `pacman-contrib` | `config.yml:56` | **Newly** in Quattro base (was not in 3.8.4). |

**From `config.yml` `aur_installed_packages`:**

| Package | Line | Note |
|---|---|---|
| `lazydocker` | `config.yml:86` | In Quattro base as a repo package. Installing from AUR is strictly worse — slower and a rebuild risk. |

**From role defaults:**

| Package | Role | Note |
|---|---|---|
| `docker`, `docker-compose`, `docker-buildx` | `docker_engine` | All three in Quattro base. |
| `git` | `go` role (`go_pacman_packages`) | Moved into Quattro's **base** manifest (was in `other` on 3.8.4). |
| `nodejs`, `npm` | `pi_coding_agent`, `gemini_cli` | Removed as part of §3.5 regardless. |

**Whole roles that become redundant:**

- **`roles/omarchy_monitor_settings`** (already commented out at `playbook.yml:49`) — **delete it**. Quattro ships `omarchy-hyprland-monitor-scaling`, `omarchy-monitor-state`, `omarchy-hw-display`, and a Display panel with unified text scaling across shell/GTK/terminals. The third-party `ryanyogan/omarchy-monitor-settings` tool is fully superseded.
- **`roles/vscode`** — not redundant, but overlaps Quattro's `omarchy-install-editor-vscode`. Keep it (it does far more: extensions, settings.json, keybindings, Wayland flags) but be aware of the duplicate install path. Its trick of hiding the original `.desktop` with `NoDisplay=true` is XDG-standard and should still work with the new unified menu — **verify**, since the menu is a Quickshell reimplementation rather than Walker.

**Vestigial config, unrelated to Quattro but worth clearing while you are in here:**

- `config.yml:105` `~/.config/mcp` and `config.yml:106` `~/.config/Claude` — leftovers from the deleted MCP roles and the long-gone `claude_desktop_wayland` role.
- The MCP probe/registration block in `roles/claude_code/tasks/main.yml:32-119` has been dead since commit `4d3e6e7` deleted the container roles. It currently writes an empty `mcpServers` block and runs `claude mcp add` commands that can never fire. Either restore container roles or strip the block.

---

## 5. Documentation and comment fixes

### 5.1 Stale comments that will actively mislead on Quattro

| Location | Problem |
|---|---|
| `config.yml:5` | "Omarchy owns: Hyprland, Waybar, Walker, Mako, Neovim, fonts, audio, SDDM, Ghostty theming" — Waybar, Walker and Mako are gone; terminal is foot. |
| `config.yml:94` | Lists `hypr, waybar, wofi, dunst, ...` as Omarchy-managed. Update to the Quickshell reality. |
| `playbook.yml:3` | "never modifies `~/.local/share/omarchy/`" — still the right *rule*, but that path is now a symlink to `/usr/share/omarchy`. Reword so the intent survives. |
| `roles/zsh/tasks/main.yml:4,84` and `roles/zsh/defaults/main.yml:4` | "Ghostty launches zsh via its config". Already wrong on 3.8.4 (base ships **alacritty**, not ghostty); on Quattro the default terminal is **foot**. |
| `roles/aur/tasks/main.yml:14` | Says to run `omarchy-update` — still a valid command on Quattro, so this one is fine. No change needed. |

### 5.2 README

`README.md` is already substantially stale (documented in `CLAUDE.md`): its role table lists ~9 roles that no longer exist and references `paru` where the repo uses `yay`. Quattro makes it worse — the "Sets up Hyprland (Wayland compositor), Waybar, Wofi" line at `README.md:26` is now wrong twice over. Rewrite the table from `playbook.yml` after the changes above land.

---

## 6. Cross-repo work: `omarchy-dotfiles`

Out of scope for this repo but **blocking for a working desktop**, since `roles/dotfiles` and `roles/zsh` only symlink what that repo provides. Track separately:

1. **Terminal config.** The no-`chsh` design depends on the terminal launching zsh. With foot as Quattro's default, add a foot config that does so, or reconsider and just `chsh`.
2. **Theme state path.** Anything referencing `~/.config/omarchy/current` must move to `~/.local/state/omarchy/current`.
3. **Hyprland configs.** If the repo ships any `.conf` fragments, they must be rewritten as Lua for Hyprland 0.56.
4. **Waybar/Walker/Mako configs.** Delete; superseded by Quickshell + `shell.json` and the unified menu.
5. **`.zshrc` PATH.** If it hardcodes `~/.npm-global/bin`, remove it as part of §3.5 or it re-creates the shadowing problem from the zsh side.

---

## 7. Suggested execution order

Sequenced so nothing is deleted before its replacement exists, and so the risky steps happen while you can still see the machine.

| Step | Work | Depends on |
|---|---|---|
| 1 | Comment/doc fixes (§5) and redundancy removals (§4) — safe, no behaviour change on v3 or v4 | — |
| 2 | Delete `roles/omarchy_monitor_settings`; strip dead MCP block; drop vestigial folders | 1 |
| 3 | Write `roles/firewall` (ufw) alongside the existing `nftables` role, not yet in `playbook.yml` | — |
| 4 | **Upgrade the laptop:** `omarchy-upgrade-to-quattro`, reboot | — |
| 5 | Set `docker_manage_daemon_json: false`; drop docker packages from role defaults | 4 |
| 6 | Remove `dns` and `nftables` from `playbook.yml`; enable `firewall`; delete both role dirs | 3, 4 |
| 7 | Rework agent roles per §3.5, including the `lineinfile: state=absent` PATH cleanup | 4 |
| 8 | Hard-gate `bootstrap.sh` on Omarchy 4 | 4 |
| 9 | Dotfiles repo work (§6) | 4 |

Steps 1–3 are safe to do **now**, on 3.8.4, before any upgrade. Everything from step 5 assumes Quattro is live.

---

## 8. Verification checklist

Run after step 8. There is no test suite, so these are the checks that stand in for one.

```bash
# Playbook still parses and the tag map is what you expect
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-tags

# Dry run — read the diff, do not trust the exit code
ansible-playbook playbook.yml --check --diff --ask-become-pass
```

Then confirm, on the box:

- [ ] `pacman -Q omarchy omarchy-settings` — both installed; `bootstrap.sh` gate passes.
- [ ] `pacman -Qo /etc/docker/daemon.json` — still package-owned; **no `.pacnew` beside it**.
- [ ] `systemctl is-enabled ufw` → enabled; `systemctl is-enabled nftables` → not-found/disabled.
- [ ] `sudo ufw status verbose` — default deny in, LocalSend 53317, the two docker-DNS rules, plus your port 22.
- [ ] `docker run --rm alpine nslookup archlinux.org` — proves the daemon.json `dns`/`bip` + ufw + resolved chain survived.
- [ ] `ls -l /etc/NetworkManager/conf.d/` — `20-omarchy-dns.conf` may exist; **`99-dns.conf` must be gone**.
- [ ] `readlink /etc/resolv.conf` → `../run/systemd/resolve/stub-resolv.conf`.
- [ ] `type -a claude gemini pi codex` in **both bash and zsh** — resolves to `~/.local/bin` shims or mise, **never** `~/.npm-global/bin`.
- [ ] `grep npm-global ~/.bashrc ~/.zshrc` — no hits.
- [ ] `ls -l ~/.claude/skills/ ~/.pi/agent/skills/` — symlinks intact, no stale entries.
- [ ] `jq . ~/.pi/agent/settings.json` — valid JSON containing **both** your `skills` paths and Omarchy's `theme` key (proves the two writers coexist, §2.6).

---

## 9. Open questions

1. **Quattro is beta.** `version` reads `4.0.0.alpha` on the branch even though the release is announced as beta, and the branch is moving. Do you want to pin against the `stable` channel at upgrade time, or track `edge`? This changes whether §3 should be implemented against a moving target or re-verified at release.
2. **Codex duplication (§3.5).** Three candidate sources: `openai-codex` (Arch extra, current role), `openai-codex-bin` (`[omarchy]` repo), `codex` (mise). Which is authoritative?
3. **Claude Code duplication (§3.5).** Keep the pacman `claude-code` package, or move it to mise with the other agents for consistency? The split decision points toward mise, but pacman is currently working and verified available.
4. **`roles/permissions`** grants passwordless `/sbin/reboot` and is not wired into `playbook.yml`. Quattro ships its own `/etc/sudoers.d/omarchy-*` files. Delete the role, or wire it up as a `sudoers.d` drop-in consistent with Omarchy's convention?
5. **`roles/aur_packages` sudoers handling.** It still edits `/etc/sudoers` directly with a backup copy, unlike every other role's `sudoers.d` temp-rule pattern. Quattro's use of `/etc/sudoers.d/` and its new `etc/security/faillock.conf` make this a good moment to convert it. In scope for this migration, or separate cleanup?
6. **`roles/links`** is a no-op — `regular_links` is never defined in `config.yml`. Delete, or was something intended to go there?
