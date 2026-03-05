#!/usr/bin/env bash
# setup.sh — one-time setup for vscode-gdrive-sessions-mcp on a new machine
# Run from the project root: bash setup.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$SCRIPT_DIR"

echo "=== Claude setup for vscode-gdrive-sessions-mcp setup ==="
echo ""

# 1. Create venv (using python3.11 if available, else python3) and install dependencies
echo "[1/3] Installing Python dependencies..."
VENV_DIR="$MCP_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    PYTHON_BIN=$(command -v python3.11 || command -v python3)
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    echo "      Created venv at $VENV_DIR using $PYTHON_BIN"
fi
"$VENV_DIR/bin/pip" install -r "$MCP_DIR/requirements.txt" --quiet
PYTHON_CMD="$VENV_DIR/bin/python3"
echo "      Done."

# 2. Create .env from example if missing
if [ ! -f "$MCP_DIR/.env" ]; then
    cp "$MCP_DIR/.env.example" "$MCP_DIR/.env"
    echo "[2/3] Created .env from .env.example"
    echo "      Edit it to set AGENT_MCP_URL and AGENT_MCP_TOKEN before use."
else
    echo "[2/3] .env already exists — skipping."
fi

# 3. Register MCP server in ~/.claude.json
CLAUDE_JSON="$HOME/.claude.json"
SERVER_NAME="claude-sessions"
SERVER_ENTRY=$(cat <<EOF
{
  "type": "stdio",
  "command": "$PYTHON_CMD",
  "args": ["$MCP_DIR/claude_vscode_sessions_mcp.py"]
}
EOF
)

echo "[3/3] Registering MCP server in $CLAUDE_JSON..."

if [ ! -f "$CLAUDE_JSON" ]; then
    echo "{}" > "$CLAUDE_JSON"
fi

# Use python3 to safely merge into existing JSON
"$PYTHON_CMD" - "$CLAUDE_JSON" "$SERVER_NAME" "$MCP_DIR/claude_vscode_sessions_mcp.py" "$PYTHON_CMD" <<'PYEOF'
import sys, json

claude_json_path = sys.argv[1]
server_name      = sys.argv[2]
server_script    = sys.argv[3]
python_cmd       = sys.argv[4]

with open(claude_json_path) as f:
    data = json.load(f)

data.setdefault("mcpServers", {})[server_name] = {
    "type": "stdio",
    "command": python_cmd,
    "args": [server_script]
}

with open(claude_json_path, "w") as f:
    json.dump(data, f, indent=2)

print(f"      Registered '{server_name}' MCP server.")
PYEOF

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env  — set AGENT_MCP_URL and AGENT_MCP_TOKEN"
echo "  2. Restart VSCode / Claude Code"
echo "  3. In any VSCode chat, ask Claude to run 'claude_sessions_list' to verify"
