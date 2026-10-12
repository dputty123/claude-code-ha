# Claude Code for Home Assistant

CLI tools and configuration for using [Claude Code](https://claude.com/claude-code) with Home Assistant OS.

> Fork of [danbuhler/claude-code-ha](https://github.com/danbuhler/claude-code-ha), updated for Claude Code's native installer (Anthropic deprecated the npm package in favor of native binaries with auto-update).

## What's Included

| File | Description |
|------|-------------|
| `bin/ha-api` | REST API CLI for quick state/service operations |
| `bin/ha-ws` | WebSocket CLI for registry management and detailed lookups |
| `bin/lovelace-sync` | Push dashboard changes to HA without restart |
| `install.sh` | Setup script for HA OS; `--boot` lets the SSH add-on run it at every start |
| `CLAUDE.md` | Instructions file that Claude Code reads automatically |

## Prerequisites

An SSH add-on from the Home Assistant Add-on Store. Either works; the first one is the one to pick if you don't want to think about this again.

| Add-on | Runs `install.sh` by itself after a restart | Package option |
|--------|---------------------------------------------|----------------|
| **Advanced SSH & Web Terminal** (community) | Yes, through `init_commands` | `packages:` |
| **Terminal & SSH** (official) | No — one command after each restart | `apks:` |

`install.sh` installs the packages Claude Code needs (`libgcc`, `libstdc++`, `ripgrep`, `python3`, `py3-pip`, `curl`, `jq`) itself, so the add-on's package list is only for extras you want in every session (`fzf`, `procps`, `coreutils`, ...).

> **Note on Alpine/musl:** `libgcc`, `libstdc++`, and `ripgrep` are required for the Claude Code native binary to run on Home Assistant OS (which is Alpine-based). See [official docs](https://code.claude.com/docs/en/setup).

## Installation

### 1. Get a long-lived access token

1. Go to your Home Assistant profile (click your name in sidebar)
2. Switch to the **Security** tab
3. Scroll to "Long-Lived Access Tokens"
4. Click "Create Token"
5. Save the token for the next step

### 2. Clone and run

In the add-on's terminal:

```bash
cd /config
git clone https://github.com/dputty123/claude-code-ha.git
./claude-code-ha/install.sh

nano /config/.env                   # paste your long-lived access token
source /etc/profile.d/claude-ha.sh  # or open a new terminal
claude                              # sign in once (browser prompt)
```

### 3. Make it automatic

**Advanced SSH & Web Terminal:** go to **Settings → Add-ons → Advanced SSH & Web Terminal → Configuration** and add:

```yaml
init_commands:
  - /config/claude-code-ha/install.sh --boot
```

Save and restart the add-on. From then on the add-on puts everything back each time it starts, and you stay signed in — see [After Add-on Restarts and HA OS Updates](#after-add-on-restarts-and-ha-os-updates).

**Terminal & SSH (official):** there is no startup hook. After a restart, run `/config/claude-code-ha/install.sh` once; you stay signed in either way.

### Manual Installation (what install.sh does for you)

```bash
# Install system dependencies (Alpine/HA OS)
apk add python3 py3-pip curl jq libgcc libstdc++ ripgrep
pip3 install websockets --break-system-packages

# Keep Claude's sign-in, settings and history in /config (the add-on wipes /root)
mkdir -p /config/.claude-data && chmod 700 /config/.claude-data
ln -s /config/.claude-data ~/.claude
export CLAUDE_CONFIG_DIR=/config/.claude-data   # install.sh puts this in /etc/profile.d

# Install Claude Code (native binary, auto-updates)
curl -fsSL https://claude.ai/install.sh | bash

# Configure Claude Code: system ripgrep (Alpine/musl requirement) + stable
# release channel (runs ~a week behind, skips releases with known regressions —
# the right trade-off for a headless box you don't babysit)
mkdir -p ~/.claude
cat > ~/.claude/settings.json <<'EOF'
{
  "autoUpdatesChannel": "stable",
  "env": { "USE_BUILTIN_RIPGREP": "0" }
}
EOF

# Symlink our CLI tools into PATH
ln -sf "$PWD/bin/ha-api" /usr/local/bin/ha-api
ln -sf "$PWD/bin/ha-ws" /usr/local/bin/ha-ws
ln -sf "$PWD/bin/lovelace-sync" /usr/local/bin/lovelace-sync

# Copy CLAUDE.md and .env to your HA config directory
cp CLAUDE.md /config/
cp .env.example /config/.env
nano /config/.env  # Add your token
```

## Why Native Installer?

As of early 2026, Anthropic [deprecated the npm package](https://code.claude.com/docs/en/setup) (`@anthropic-ai/claude-code`) in favor of a native binary installer:

- **No Node.js/npm required** — one less moving part on HA OS
- **Auto-updates in the background** — stays current without re-running install
- **Same binary** — the npm package was just a wrapper around this binary anyway

The npm path still works if you need it, but this repo standardizes on the native installer.

> **Why not `apk add claude-code`?** Anthropic does publish a [signed apk repository](https://code.claude.com/docs/en/setup) for Alpine. We deliberately don't use it here: apk-installed packages live on the root filesystem, so they're wiped on every HA OS update, and the apk build doesn't self-update. The native installer's binary lands in `/root/.local/bin` and auto-updates itself — one less thing to reinstall.

## Usage

### ha-api - REST API CLI

Fast lookups and service calls:

```bash
ha-api states                    # List all entities
ha-api states light              # Filter by domain
ha-api state light.kitchen       # Get specific entity state
ha-api attr sensor.temperature   # Show attributes
ha-api devices motion            # Find by device_class
ha-api search bedroom            # Search entity IDs
ha-api call light turn_on        # Call a service
ha-api history sensor.temp 48    # Get 48h history
```

### ha-ws - WebSocket CLI

Registry management and detailed entity/device info:

```bash
# Entity operations
ha-ws entity list light          # List light entities
ha-ws entity get light.kitchen   # Full entity details + related items
ha-ws entity update light.old new_entity_id=light.new  # Rename

# Device operations
ha-ws device list                # List all devices
ha-ws device get <device_id>     # Device details + all entities

# Area management
ha-ws area list                  # List areas
ha-ws area create "Guest Room"   # Create area

# Service calls
ha-ws call light.turn_on entity_id=light.kitchen brightness=255

# Raw WebSocket
ha-ws raw config/entity_registry/list
```

### lovelace-sync - Dashboard Sync

Edit `.storage/lovelace` directly, then push to HA:

```bash
# 1. Edit the lovelace file
# 2. Push changes (no restart needed)
lovelace-sync
# 3. Refresh browser to see changes
```

**Note:** Changes made in the HA web interface will overwrite any unpushed local edits. Always run `lovelace-sync` before making changes in the UI.

## Claude Code Integration

The `CLAUDE.md` file provides Claude Code with context about:
- These CLI tools and how to use them
- Home Assistant YAML configuration patterns
- Best practices for automation/template syntax

Copy `CLAUDE.md` to your HA config directory. Claude Code automatically reads it when working there.

### Example Session

```
> claude

You: "Turn on the kitchen lights"
Claude: *uses ha-api call light turn_on*

You: "What motion sensors do I have?"
Claude: *uses ha-api devices motion*

You: "Rename light.old_lamp to light.bedroom_lamp"
Claude: *uses ha-ws entity update*
```

## Configuration

### Environment Variables

The install script creates `/config/.env` from the template. Edit it with your token:

```bash
# /config/.env
HA_URL=http://172.30.32.1:8123    # Internal HA API URL (HA OS default; use https:// only if you've configured SSL in HA)
HA_TOKEN=your_token_here          # Long-lived access token
```

The scripts search for `.env` in order:
1. `$HA_ENV_FILE` (if set)
2. `/config/.env` (standard location)
3. `/homeassistant/.env`
4. Current directory
5. `~/.ha-cli.env`

### For External Access

If running Claude Code from outside HA OS:

```bash
HA_URL=https://your-ha-domain.com:8123
HA_TOKEN=your_token_here
```

## After Add-on Restarts and HA OS Updates

The SSH add-on runs in a container whose root filesystem is rebuilt every time the add-on restarts or updates, and on every HA OS update. That removes installed `apk` and `pip` packages, the Claude Code binary in `/root/.local`, anything in `/usr/local/bin`, and `/etc/profile.d/claude-ha.sh`. Only `/config` survives.

`install.sh` puts all of it back, and your Claude sign-in, settings and chat history come back with it because they are kept in `/config/.claude-data/`.

- **With the `init_commands` line** from [Installation](#3-make-it-automatic): nothing to do. The add-on runs `install.sh --boot` each time it starts. Open the terminal and run `claude`.
- **Without it** (or on the official Terminal & SSH add-on, which has no startup commands):

  ```bash
  /config/claude-code-ha/install.sh
  source /etc/profile.d/claude-ha.sh   # or open a new terminal
  ```

To pick up repo changes first: `cd /config/claude-code-ha && git pull`.

The script is idempotent — safe to re-run any time.

### What install.sh Does

| Item | Action | On Re-run |
|------|--------|-----------|
| `~/.claude` and `~/.claude.json` | **Symlinks** into `/config/.claude-data/` | Recreates; merges in anything Claude wrote to `/root` in the meantime (newer file wins, original kept aside) |
| `/etc/profile.d/claude-ha.sh` | Writes PATH, `USE_BUILTIN_RIPGREP=0`, `CLAUDE_CONFIG_DIR=/config/.claude-data` | Recreates |
| `settings.json` in `/config/.claude-data/` | Writes stable update channel + `USE_BUILTIN_RIPGREP=0` (Alpine/musl) | Skips if exists |
| `ha-api`, `ha-ws`, `lovelace-sync` | **Symlinks** to repo's `bin/` | Recreates (safe) |
| `CLAUDE.md` | **Copies** to `/config/` | Skips if exists (preserves customizations) |
| `.env` | **Copies** template to `/config/.env` | Skips if exists (preserves your token) |
| System packages (python3, libgcc, libstdc++, ripgrep, etc.) | Installs via apk | Reinstalls |
| Python websockets | pip install | Reinstalls |
| Claude Code (native binary) | curl installer | Skips if already installed (auto-updates itself) |

The steps that need the network run last. If one fails, the script says which, exits non-zero, and everything above it is already in place — re-run when the network is back.

**`--boot`** is for the add-on's `init_commands`: same steps, output goes to `install.log` in the repo folder, and it always exits 0, because a failing init command stops the add-on from starting.

**Symlinks** point to the scripts in the repo - updates to the repo are immediately available.

**Copies** are only made on first run. If you've customized `CLAUDE.md`, it won't be overwritten. To get updates, manually copy from the repo.

### What Persists

These survive in `/config` (it's on the data partition, not the add-on's filesystem):
- The cloned repo itself
- Your `.env` file (with your HA token)
- Your customized `CLAUDE.md`
- `/config/.claude-data/` — Claude Code's sign-in (`.credentials.json`, `.claude.json`), `settings.json`, chat history and memory

The Claude Code binary itself is **not** kept: it's a large file that would be copied into every Home Assistant backup. `install.sh` downloads it again after a restart, so the add-on needs network access when it starts.

> **Backups contain your sign-in.** `/config/.claude-data/` and `/config/.env` are part of every Home Assistant backup. Treat backups that leave the house (cloud, shared drives) as holding a Claude login and an HA admin token.

### Troubleshooting

**First move when anything's off:** run `claude doctor`. It prints install health, settings-file validation errors, and warnings with suggested fixes — without starting a session. Run it before digging into anything below, especially after an HA OS update.

**`claude: command not found` after re-running install.sh**
Your PATH didn't reload. Run `source /etc/profile.d/claude-ha.sh` or open a new shell.

**`Error: ripgrep failed to execute` or similar musl/glibc error**
The bundled ripgrep binary (glibc) can't run on Alpine (musl). Check that:
1. `apk info ripgrep` shows it's installed (`install.sh` does this)
2. `~/.claude/settings.json` contains `"USE_BUILTIN_RIPGREP": "0"` — if not, add it:
   ```bash
   mkdir -p ~/.claude
   cat > ~/.claude/settings.json <<'EOF'
   {
     "autoUpdatesChannel": "stable",
     "env": { "USE_BUILTIN_RIPGREP": "0" }
   }
   EOF
   ```
3. `echo $USE_BUILTIN_RIPGREP` returns `0` in your current shell. If not, `source /etc/profile.d/claude-ha.sh`.

**`pip3: command not found` during install.sh**
`install.sh` installs `python3` and `py3-pip` through `apk` before it needs them, so this means the package step failed — usually no network. Check the top of the output (or `install.log`), then re-run `install.sh`.

**`ha-api` or `ha-ws` fails with auth errors**
Your `/config/.env` file is missing or has a stale token. HA tokens don't expire, but if you've revoked one or never set it, regenerate from your HA profile's Security tab and update `/config/.env`.

**Claude Code asks you to sign in again after an add-on restart**
Your sign-in lives in `/config/.claude-data/` (`.credentials.json` and `.claude.json`) and is found through `CLAUDE_CONFIG_DIR`, which `install.sh` exports from `/etc/profile.d/claude-ha.sh`. Check, in this order:
1. `install.sh` has run since the restart: `ls -l ~/.claude ~/.claude.json` should show two links into `/config/.claude-data/`. If not, run `/config/claude-code-ha/install.sh` (and add the `init_commands` line from [Installation](#3-make-it-automatic) so it runs by itself).
2. `echo $CLAUDE_CONFIG_DIR` prints `/config/.claude-data`. If it's empty, open a new terminal or `source /etc/profile.d/claude-ha.sh`.
3. If the add-on was started with `--boot`, read `/config/claude-code-ha/install.log`.

A sign-in made *before* this was set up isn't saved, so expect to sign in one last time.

## Requirements

- Home Assistant OS (or any installation with shell access)
- Python 3 with `websockets` package
- `curl`, `jq`, `ripgrep` for the CLI tools and Claude Code
- `libgcc`, `libstdc++` (Alpine/musl only, required by Claude Code native binary)
- A paid Claude account (Pro/Max/Team/Enterprise/Console) for Claude Code access

## License

MIT License - See [LICENSE](LICENSE)
