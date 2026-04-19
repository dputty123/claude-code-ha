# Claude Code for Home Assistant

CLI tools and configuration for using [Claude Code](https://claude.com/claude-code) with Home Assistant OS.

> Fork of [danbuhler/claude-code-ha](https://github.com/danbuhler/claude-code-ha), updated for Claude Code's native installer (Anthropic deprecated the npm package in favor of native binaries with auto-update).

## What's Included

| File | Description |
|------|-------------|
| `bin/ha-api` | REST API CLI for quick state/service operations |
| `bin/ha-ws` | WebSocket CLI for registry management and detailed lookups |
| `bin/lovelace-sync` | Push dashboard changes to HA without restart |
| `install.sh` | Setup script for HA OS (re-run after HA updates) |
| `CLAUDE.md` | Instructions file that Claude Code reads automatically |

## Prerequisites

### Terminal & SSH Add-on Setup

Install the "Terminal & SSH" add-on from the Home Assistant Add-on Store, then configure it with the required packages:

1. Go to **Settings → Add-ons → Terminal & SSH → Configuration**
2. Add these packages to the configuration:

```yaml
apks:
  - gcompat
  - libgcc
  - libstdc++
  - curl
  - jq
  - ripgrep
  - procps
  - coreutils
  - tar
  - bash
  - python3
  - py3-pip
  - fzf
```

> **Note on Alpine/musl:** `libgcc`, `libstdc++`, and `ripgrep` are required for the Claude Code native binary to run on Home Assistant OS (which is Alpine-based). See [official docs](https://code.claude.com/docs/en/setup).

3. Save and restart the add-on

## Installation

### Getting a Long-Lived Access Token

1. Go to your Home Assistant profile (click your name in sidebar)
2. Switch to the **Security** tab
3. Scroll to "Long-Lived Access Tokens"
4. Click "Create Token"
5. Save the token for the next step

### On Home Assistant OS

```bash
# SSH into your HA OS instance
cd /config

# Clone this repo
git clone https://github.com/dputty123/claude-code-ha.git

# Run setup (installs dependencies + Claude Code native binary)
cd claude-code-ha
./install.sh

# Edit /config/.env and add your long-lived access token
nano /config/.env
```

Then authenticate Claude Code:

```bash
source /etc/profile.d/claude-ha.sh  # or start a new shell
claude                              # follow browser login prompts
```

### Manual Installation (what install.sh does for you)

```bash
# Install system dependencies (Alpine/HA OS)
apk add python3 py3-pip curl jq libgcc libstdc++ ripgrep
pip3 install websockets --break-system-packages

# Install Claude Code (native binary, auto-updates)
curl -fsSL https://claude.ai/install.sh | bash

# Configure Claude Code to use system ripgrep (Alpine/musl requirement)
mkdir -p ~/.claude
cat > ~/.claude/settings.json <<'EOF'
{ "env": { "USE_BUILTIN_RIPGREP": "0" } }
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
HA_URL=https://172.30.32.1:8128   # Internal HA API URL (HA OS default)
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

## After Home Assistant OS Updates

HA OS updates reset the root filesystem. This removes installed `apk` packages, `pip` packages, anything in `/usr/local/bin`, and PATH modifications in `/etc/profile.d`. **Re-run `install.sh` after each HA OS update** to put everything back.

### Quick version

```bash
cd /config/claude-code-ha
git pull                   # optional: grab any repo updates first
./install.sh
source /etc/profile.d/claude-ha.sh
```

That's it. The script is idempotent — safe to re-run any time.

### Full walkthrough

```bash
# 1. SSH in (or open the Terminal add-on)

# 2. Re-run the installer
cd /config/claude-code-ha
./install.sh

# 3. Reload your shell environment (PATH + USE_BUILTIN_RIPGREP)
source /etc/profile.d/claude-ha.sh
#    ...or just close the terminal and open a new one

# 4. Verify everything works
which claude               # -> /root/.local/bin/claude (or /usr/local/bin/claude)
claude --version           # prints a version number
ha-api states | head       # HA CLI still works

# 5. Start Claude Code
claude
```

If you also want to pull the latest repo changes before reinstalling:

```bash
cd /config/claude-code-ha
git pull origin main
./install.sh
```

### What install.sh Does

| Item | Action | On Re-run |
|------|--------|-----------|
| System packages (python3, libgcc, libstdc++, ripgrep, etc.) | Installs via apk | Reinstalls (needed after HA update) |
| Python websockets | pip install | Reinstalls (needed after HA update) |
| Claude Code (native binary) | curl installer | Skips if already installed (auto-updates itself) |
| `~/.claude/settings.json` | Writes `USE_BUILTIN_RIPGREP=0` (Alpine/musl) | Skips if exists |
| `ha-api`, `ha-ws`, `lovelace-sync` | **Symlinks** to repo's `bin/` | Recreates (safe) |
| `CLAUDE.md` | **Copies** to `/config/` | Skips if exists (preserves customizations) |
| `.env` | **Copies** template to `/config/.env` | Skips if exists (preserves your token) |
| PATH in `/etc/profile.d/` | Creates | Recreates (needed after HA update) |

**Symlinks** point to the scripts in the repo - updates to the repo are immediately available.

**Copies** are only made on first run. If you've customized `CLAUDE.md`, it won't be overwritten. To get updates, manually copy from the repo.

### What Persists Across HA Updates

These survive in `/config` (it's on the data partition, not the root filesystem):
- The cloned repo itself
- Your `.env` file (with your token)
- Your customized `CLAUDE.md`
- `/root/.local/bin/claude` (the Claude Code binary) — usually survives, but not guaranteed across major HA OS upgrades

Re-running `install.sh` is idempotent either way: if the binary is there, it skips; if it's gone, it reinstalls.

### Troubleshooting

**`claude: command not found` after re-running install.sh**
Your PATH didn't reload. Run `source /etc/profile.d/claude-ha.sh` or open a new shell.

**`Error: ripgrep failed to execute` or similar musl/glibc error**
The bundled ripgrep binary (glibc) can't run on Alpine (musl). Check that:
1. `apk info ripgrep` shows it's installed (`install.sh` does this)
2. `~/.claude/settings.json` contains `"USE_BUILTIN_RIPGREP": "0"` — if not, add it:
   ```bash
   mkdir -p ~/.claude
   cat > ~/.claude/settings.json <<'EOF'
   { "env": { "USE_BUILTIN_RIPGREP": "0" } }
   EOF
   ```
3. `echo $USE_BUILTIN_RIPGREP` returns `0` in your current shell. If not, `source /etc/profile.d/claude-ha.sh`.

**`pip3: command not found` during install.sh**
The Terminal & SSH add-on's `apks:` list is missing `python3` and `py3-pip`. Add them (see [Prerequisites](#terminal--ssh-add-on-setup)) and restart the add-on.

**`ha-api` or `ha-ws` fails with auth errors**
Your `/config/.env` file is missing or has a stale token. HA tokens don't expire, but if you've revoked one or never set it, regenerate from your HA profile's Security tab and update `/config/.env`.

**Claude Code says "not authenticated"**
Auth state is in `~/.claude/` and usually persists, but a full HA OS reflash wipes it. Run `claude` and go through the browser login flow again.

## Requirements

- Home Assistant OS (or any installation with shell access)
- Python 3 with `websockets` package
- `curl`, `jq`, `ripgrep` for the CLI tools and Claude Code
- `libgcc`, `libstdc++` (Alpine/musl only, required by Claude Code native binary)
- A paid Claude account (Pro/Max/Team/Enterprise/Console) for Claude Code access

## License

MIT License - See [LICENSE](LICENSE)
