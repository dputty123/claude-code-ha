#!/bin/bash
# Claude Code for Home Assistant - Setup Script
# https://github.com/dputty123/claude-code-ha
#
# Installs dependencies, Claude Code and the CLI tools, and keeps Claude's
# sign-in, settings and history in /config so they survive add-on restarts.
#
# The SSH add-on's root filesystem is rebuilt every time the add-on restarts
# or updates (and on HA OS updates). That removes everything this script puts
# outside /config, so it has to run again afterwards. Either run it by hand,
# or let the add-on run it at startup (Advanced SSH & Web Terminal add-on):
#
#   init_commands:
#     - /config/claude-code-ha/install.sh --boot
#
# Usage: install.sh [--boot]
#   --boot   Startup mode for the add-on's init_commands. Always exits 0 (a
#            failing init command stops the add-on from starting) and writes
#            its output to install.log next to this script.
#
# The script is idempotent - safe to re-run any time.

set -e
set -o pipefail

export HOME="${HOME:-/root}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOOT=0
for arg in "$@"; do
    case "$arg" in
        --boot) BOOT=1 ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (try --help)" >&2
            exit 2
            ;;
    esac
done

# Startup mode: run the normal install with output captured to a log, and
# never fail - the add-on must still come up if the network is down.
if [ "$BOOT" = "1" ]; then
    LOG="$SCRIPT_DIR/install.log"
    if bash "$SCRIPT_DIR/install.sh" > "$LOG" 2>&1; then
        echo "claude-code-ha: ready"
    else
        echo "claude-code-ha: setup did not finish - see $LOG, then re-run $SCRIPT_DIR/install.sh"
    fi
    exit 0
fi

# Steps that fail are collected here and reported at the end, so one failure
# (usually the network) doesn't stop the steps that don't depend on it.
FAILED=""
fail() {
    echo "  [failed] $1"
    FAILED="$FAILED\n  - $1"
}

echo "=== Claude Code for Home Assistant Setup ==="
echo ""

# Detect OS
if command -v apk &> /dev/null; then
    PKG_MANAGER="apk"
    INSTALL_CMD="apk add --quiet"
elif command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
    INSTALL_CMD="apt-get install -y"
elif command -v brew &> /dev/null; then
    PKG_MANAGER="brew"
    INSTALL_CMD="brew install"
else
    echo "Warning: Unknown package manager. Please install dependencies manually:"
    echo "  python3, pip, curl, jq, ripgrep"
    PKG_MANAGER="unknown"
fi

# Determine HA config directory (prefer /config as it's the standard HA path).
# HA_CONFIG_DIR overrides the detection (used for testing the script).
ON_HA=1
if [ -n "$HA_CONFIG_DIR" ]; then
    HA_CONFIG="$HA_CONFIG_DIR"
elif [ -d "/config" ]; then
    HA_CONFIG="/config"
elif [ -d "/homeassistant" ]; then
    HA_CONFIG="/homeassistant"
else
    HA_CONFIG="$HOME"
    ON_HA=0
fi

# Determine bin install location
if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    BIN_DIR="/usr/local/bin"
else
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
fi

# ---------------------------------------------------------------------------
# Persistent Claude state
#
# Claude Code keeps its state in two places under the home directory:
#   ~/.claude/        credentials, settings, chat history, memory
#   ~/.claude.json    the sign-in session and per-project state
# Both live in /root, which the add-on wipes on every restart. Losing either
# one means signing in again. Both are kept in $HA_CONFIG/.claude-data
# instead, in two ways that back each other up:
#   - CLAUDE_CONFIG_DIR points Claude Code at that directory (set in
#     /etc/profile.d below, so every login shell has it)
#   - ~/.claude and ~/.claude.json are symlinked there, for shells that
#     don't load the profile
#
# This runs before Claude Code is installed, so the installer never creates
# a fresh, signed-out ~/.claude that would shadow the saved one.
# ---------------------------------------------------------------------------
CLAUDE_HOME="$HOME/.claude"
CLAUDE_STATE="$HOME/.claude.json"

claude_running() {
    pgrep -x claude > /dev/null 2>&1
}

if [ "$ON_HA" = "1" ]; then
    CLAUDE_PERSIST="$HA_CONFIG/.claude-data"
    CLAUDE_STATE_PERSIST="$CLAUDE_PERSIST/.claude.json"

    echo "Setting up persistent Claude state in $CLAUDE_PERSIST..."
    if [ ! -d "$CLAUDE_PERSIST" ]; then
        mkdir -p "$CLAUDE_PERSIST"
        chmod 700 "$CLAUDE_PERSIST"
    fi

    # ~/.claude -> $CLAUDE_PERSIST
    if [ -L "$CLAUDE_HOME" ]; then
        TARGET="$(readlink -f "$CLAUDE_HOME")"
        if [ "$TARGET" = "$(readlink -f "$CLAUDE_PERSIST")" ]; then
            echo "  [ok] $CLAUDE_HOME already linked"
        else
            echo "  [warn] $CLAUDE_HOME is a symlink to $TARGET (not $CLAUDE_PERSIST) - leaving alone"
        fi
    elif [ ! -e "$CLAUDE_HOME" ]; then
        ln -s "$CLAUDE_PERSIST" "$CLAUDE_HOME"
        echo "  [symlink] $CLAUDE_HOME -> $CLAUDE_PERSIST"
    elif claude_running; then
        # A real directory that a running Claude is writing to: can't swap it
        # out from underneath. The CLAUDE_CONFIG_DIR export below still makes
        # new sessions use the persistent copy.
        echo "  [warn] $CLAUDE_HOME is a real directory and Claude is running."
        echo "         Exit Claude and re-run this script to merge it into $CLAUDE_PERSIST."
    else
        # A real directory: first-time setup, or Claude ran in /root after a
        # restart before this script did. Merge it in (newer file wins, so a
        # fresh sign-in replaces a stale one), keep the original aside, link.
        cp -a -u "$CLAUDE_HOME/." "$CLAUDE_PERSIST/"
        ASIDE="$HOME/.claude.replaced-$(date +%Y%m%d%H%M%S)"
        mv "$CLAUDE_HOME" "$ASIDE"
        ln -s "$CLAUDE_PERSIST" "$CLAUDE_HOME"
        echo "  [merged] $CLAUDE_HOME into $CLAUDE_PERSIST (original kept at $ASIDE)"
        echo "  [symlink] $CLAUDE_HOME -> $CLAUDE_PERSIST"
    fi

    # ~/.claude.json -> $CLAUDE_PERSIST/.claude.json (the sign-in session)
    if [ -L "$CLAUDE_STATE" ]; then
        echo "  [ok] $CLAUDE_STATE already linked"
    else
        if [ -f "$CLAUDE_STATE" ]; then
            if [ ! -f "$CLAUDE_STATE_PERSIST" ] || [ "$CLAUDE_STATE" -nt "$CLAUDE_STATE_PERSIST" ]; then
                cp -a "$CLAUDE_STATE" "$CLAUDE_STATE_PERSIST"
                echo "  [saved] sign-in session copied to $CLAUDE_STATE_PERSIST"
            fi
            rm -f "$CLAUDE_STATE"
        fi
        if [ -f "$CLAUDE_STATE_PERSIST" ]; then
            ln -s "$CLAUDE_STATE_PERSIST" "$CLAUDE_STATE"
            echo "  [symlink] $CLAUDE_STATE -> $CLAUDE_STATE_PERSIST"
        else
            echo "  [info] no saved sign-in yet - sign in once and it will be kept"
        fi
    fi

    export CLAUDE_CONFIG_DIR="$CLAUDE_PERSIST"
    echo ""
fi

# Add to PATH and export Claude's environment for every login shell
if [ -d "/etc/profile.d" ] && [ -w "/etc/profile.d" ]; then
    PROFILE_FILE="/etc/profile.d/claude-ha.sh"
    echo "Writing $PROFILE_FILE..."
    cat > "$PROFILE_FILE" << EOF
# Claude Code for Home Assistant
export PATH="\$PATH:$BIN_DIR:$SCRIPT_DIR/bin:\$HOME/.local/bin"
# Use system ripgrep - the bundled glibc binary can't run on Alpine/musl
export USE_BUILTIN_RIPGREP=0
EOF
    if [ "$ON_HA" = "1" ]; then
        cat >> "$PROFILE_FILE" << EOF
# Keep Claude's sign-in, settings and history where add-on restarts can't reach
export CLAUDE_CONFIG_DIR="$CLAUDE_PERSIST"
EOF
    fi
    chmod +x "$PROFILE_FILE"
    echo ""
fi

# Claude Code settings: system ripgrep (Alpine/musl) + stable release channel
# (headless appliance - a week-old release beats debugging a regression over SSH).
# Skipped if settings.json already exists.
if [ "$ON_HA" = "1" ]; then
    SETTINGS_DIR="$CLAUDE_PERSIST"
else
    SETTINGS_DIR="$CLAUDE_HOME"
fi
echo "Configuring Claude Code settings..."
if [ -f "$SETTINGS_DIR/settings.json" ]; then
    echo "  [skipped] $SETTINGS_DIR/settings.json already exists"
    echo "            Recommended contents: {\"autoUpdatesChannel\": \"stable\", \"env\": {\"USE_BUILTIN_RIPGREP\": \"0\"}}"
else
    mkdir -p "$SETTINGS_DIR"
    cat > "$SETTINGS_DIR/settings.json" << 'EOF'
{
  "autoUpdatesChannel": "stable",
  "env": { "USE_BUILTIN_RIPGREP": "0" }
}
EOF
    echo "  [written] $SETTINGS_DIR/settings.json (stable channel + system ripgrep)"
fi
echo ""

# Make scripts executable
chmod +x "$SCRIPT_DIR/bin/"*

# Create symlinks for tools (these get wiped on add-on restart, safe to recreate)
echo "Creating symlinks in $BIN_DIR..."
for script in ha-api ha-ws lovelace-sync; do
    if [ -f "$SCRIPT_DIR/bin/$script" ]; then
        ln -sf "$SCRIPT_DIR/bin/$script" "$BIN_DIR/$script"
        echo "  [symlink] $script -> $SCRIPT_DIR/bin/$script"
    fi
done

# Copy CLAUDE.md to HA config (only if it doesn't exist - won't overwrite customizations)
echo ""
echo "Copying CLAUDE.md to $HA_CONFIG..."
if [ -f "$HA_CONFIG/CLAUDE.md" ]; then
    echo "  [skipped] CLAUDE.md already exists (won't overwrite your customizations)"
    echo "            To update, manually copy from: $SCRIPT_DIR/CLAUDE.md"
else
    cp "$SCRIPT_DIR/CLAUDE.md" "$HA_CONFIG/CLAUDE.md"
    echo "  [copied] CLAUDE.md -> $HA_CONFIG/CLAUDE.md"
fi

# Copy .env.example if .env doesn't exist
if [ ! -f "$HA_CONFIG/.env" ]; then
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$HA_CONFIG/.env"
        chmod 600 "$HA_CONFIG/.env"
        echo "  [copied] .env.example -> $HA_CONFIG/.env (edit this with your token!)"
    fi
else
    echo "  [skipped] .env already exists"
fi

# Disable HA banner (HA OS specific)
if [ -f "/etc/profile.d/homeassistant.sh" ]; then
    echo "Disabling HA banner..."
    sed -i 's/^ha banner/# ha banner/' /etc/profile.d/homeassistant.sh 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Everything below needs the network. Failures are reported, not fatal:
# the links and environment above are already in place.
# ---------------------------------------------------------------------------

# Install system dependencies
# libgcc/libstdc++/ripgrep are required by the Claude Code native binary on
# Alpine/musl (HA OS). See README "Prerequisites".
if [ "$PKG_MANAGER" != "unknown" ]; then
    echo ""
    echo "Installing system packages..."
    case "$PKG_MANAGER" in
        apk)
            $INSTALL_CMD python3 py3-pip curl jq libgcc libstdc++ ripgrep \
                || fail "system packages (apk)"
            ;;
        apt)
            sudo $INSTALL_CMD python3 python3-pip curl jq ripgrep \
                || fail "system packages (apt)"
            ;;
        brew)
            $INSTALL_CMD python3 curl jq ripgrep \
                || fail "system packages (brew)"
            ;;
    esac
fi

# Install Python dependencies
echo "Installing Python websockets..."
if command -v pip3 &> /dev/null; then
    pip3 install websockets --break-system-packages --quiet 2>/dev/null \
        || pip3 install websockets --quiet \
        || fail "Python websockets (needed by ha-ws and lovelace-sync)"
elif command -v pip &> /dev/null; then
    pip install websockets --quiet \
        || fail "Python websockets (needed by ha-ws and lovelace-sync)"
else
    fail "Python websockets - pip not found"
fi

# Install Claude Code (native binary - the npm package is deprecated)
echo "Installing Claude Code..."
if command -v claude &> /dev/null || [ -x "$HOME/.local/bin/claude" ]; then
    echo "  [skipped] Claude Code already installed (it auto-updates itself)"
elif curl -fsSL https://claude.ai/install.sh | bash; then
    echo "  [installed] Claude Code"
else
    fail "Claude Code download (re-run this script when the network is back)"
fi

echo ""
if [ -n "$FAILED" ]; then
    echo "=== Setup finished with problems ==="
    echo -e "These steps failed:$FAILED"
    echo ""
    echo "Re-run $SCRIPT_DIR/install.sh to retry."
    exit 1
fi

echo "=== Setup Complete ==="
echo ""
echo "What was installed:"
echo "  [recreated each run]"
echo "    ha-api, ha-ws, lovelace-sync -> $BIN_DIR/"
if [ "$ON_HA" = "1" ]; then
    echo "    ~/.claude, ~/.claude.json    -> $CLAUDE_PERSIST/"
fi
echo ""
echo "  [copies - only if not present, won't overwrite]"
echo "    CLAUDE.md     -> $HA_CONFIG/"
echo "    .env          -> $HA_CONFIG/"
echo "    settings.json -> $SETTINGS_DIR/"
echo ""
echo "Next steps:"
if [ -f "$HA_CONFIG/.env" ]; then
    if grep -q "your_long_lived_access_token_here" "$HA_CONFIG/.env" 2>/dev/null; then
        echo "  1. Edit $HA_CONFIG/.env and add your HA token"
        echo "  2. Run 'claude' to start Claude Code"
    else
        echo "  1. Run 'claude' to start Claude Code"
    fi
else
    echo "  1. Create $HA_CONFIG/.env with HA_URL and HA_TOKEN"
    echo "  2. Run 'claude' to start Claude Code"
fi
echo ""
echo "Run 'source /etc/profile.d/claude-ha.sh' or start a new shell to use the tools."
if [ "$ON_HA" = "1" ]; then
    echo ""
    echo "To have this run by itself after every add-on restart, add this to the"
    echo "Advanced SSH & Web Terminal add-on configuration:"
    echo "  init_commands:"
    echo "    - $SCRIPT_DIR/install.sh --boot"
fi
