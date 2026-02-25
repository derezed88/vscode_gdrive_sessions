# vscode-gdrive-sessions-mcp

An MCP (Model Context Protocol) server that bridges **Claude Code in VSCode** with **Google Drive** — letting you list, export, save, and retrieve your chat sessions and snippets directly from any Claude Code conversation.

---

## What It Does

The server exposes five tools to Claude Code chat:

| Tool | Requires agent-mcp? | Purpose |
|------|---------------------|---------|
| `claude_sessions_list` | No | List all local Claude Code sessions on this machine |
| `gdrive_list` | Preferred | List files in a Google Drive folder |
| `gdrive_read` | For summary/extract modes | Read a Drive file (verbatim, summarized, or extracted) |
| `gdrive_snippet_save` | Preferred | Save/append text content to a Drive file |
| `gdrive_sessions_export` | For summary mode | Export selected sessions to Drive |

"Preferred" means: the tool works without agent-mcp via a direct Google Drive API fallback, but `summary` and `extract` modes require agent-mcp's LLM dispatch.

---

## Architecture

```
VSCode / Claude Code
      │  MCP protocol (stdio)
      ▼
claude_vscode_sessions_mcp.py          ← this repo
      │
      ├─ claude_sessions_list ──────► ~/.claude/projects/ (local JSONL files, no network)
      │
      ├─ gdrive_list   ─────────────┐
      ├─ gdrive_read                ├──► agent-mcp HTTP API  (primary path)
      ├─ gdrive_snippet_save        │       POST /vscode/drive/list
      │                             │       POST /vscode/drive/read
      │                             │       POST /vscode/drive/snippet/save
      │                             │
      └─ (ConnectError fallback) ───┘──► Google Drive API directly (OAuth2)
                                              drive.py

      gdrive_sessions_export ──────────► Local JSONL → combined text → Drive API (always direct)
                                          (agent-mcp used only for summary mode LLM call)
```

**agent-mcp** (separate repo) is an HTTP API server. When reachable, it handles Drive operations and LLM summarization. When unreachable, `drive.py` in this repo provides a direct fallback for all operations except LLM-based `summary` and `extract` modes.

---

## File Structure

```
vscode_gdrive_sessions/
├── claude-vscode-setup.sh          # One-time setup: installs deps, registers MCP server
├── claude_vscode_sessions_mcp.py   # Main MCP server — tool definitions and dispatch
├── drive.py                        # Direct Google Drive API fallback (no agent-mcp needed)
├── requirements.txt                # Python dependencies
├── .env.example                    # Configuration template
└── .gitignore                      # Excludes .env, credentials.json, token.json, venv/
```

---

## Requirements

### Python

Python **3.11+** is required (the repo ships a `.python-version` file pinned to 3.11.10).

### System

- **VSCode** with the **Claude Code extension** installed and signed in
- **pip** (or a virtual environment manager)

### Python Packages

Installed automatically by `claude-vscode-setup.sh`:

```
mcp>=1.0.0                      # MCP protocol implementation
httpx>=0.27.0                   # Async HTTP client (agent-mcp calls)
python-dotenv>=1.0.0            # .env file loading
google-auth>=2.0.0              # Google OAuth2
google-auth-oauthlib>=1.0.0     # OAuth2 browser flow
google-api-python-client>=2.0.0 # Google Drive API client
```

### Google Drive API Credentials

Required for direct Drive access (fallback mode, and always for `gdrive_sessions_export`):

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials
2. Create an **OAuth 2.0 Client ID** (application type: Desktop app)
3. Download `credentials.json`
4. Place it on your machine and note the path; set `DRIVE_CREDS_FILE` in `.env`

The first time a Drive operation runs, a browser window opens for OAuth consent. A `token.json` file is written automatically and reused on subsequent runs.

### agent-mcp (Optional but Recommended)

The **agent-mcp** service (separate repository) provides:
- Proxied Drive operations (`/vscode/drive/*` endpoints)
- LLM-based `summary` and `extract` modes for `gdrive_read` and `gdrive_sessions_export`

Without agent-mcp, all tools still work except `summary`/`extract` modes fall back to returning full content with a warning.

---

## Installation

### 1. Clone this repository

```bash
git clone <repo-url> ~/projects/vscode_gdrive_sessions
cd ~/projects/vscode_gdrive_sessions
```

### 2. Run the setup script

```bash
bash claude-vscode-setup.sh
```

This script does three things:

**Step 1 — Install Python dependencies:**
```bash
pip install -r requirements.txt --quiet
```

**Step 2 — Create `.env` from template** (if `.env` doesn't already exist):
```bash
cp .env.example .env
```

**Step 3 — Register the MCP server in `~/.claude.json`:**

The script uses Python to safely merge the following entry into `~/.claude.json` under the `"mcpServers"` key, without overwriting any existing servers:

```json
"mcpServers": {
  "gdrive": {
    "type": "stdio",
    "command": "python3",
    "args": ["/path/to/vscode_gdrive_sessions/claude_vscode_sessions_mcp.py"]
  }
}
```

This is the only change made to your VSCode/Claude Code configuration. No VSCode workspace settings, launch configurations, or extension settings are modified.

### 3. Edit `.env`

```bash
# URL of your running agent-mcp API server
# Local: http://localhost:8767
# Remote via Pinggy/ngrok tunnel: https://xxxx.a.pinggy.link
AGENT_MCP_URL=http://localhost:8767

# Bearer token — must match API_KEY set in agent-mcp/.env
# Leave empty if agent-mcp has no API_KEY configured
AGENT_MCP_TOKEN=

# Required for direct Drive fallback and gdrive_sessions_export
FOLDER_ID=your-google-drive-folder-id
DRIVE_CREDS_FILE=/path/to/credentials.json
DRIVE_TOKEN_FILE=/path/to/token.json   # auto-created after first OAuth login
```

### 4. Restart VSCode

After restarting, Claude Code automatically launches the MCP server as a child process via stdio. You can verify by asking Claude: *"Run claude_sessions_list"* — it should return a list of your local sessions.

---

## How the Server Starts

Claude Code reads `~/.claude.json` on startup. When it finds the `"gdrive"` entry under `"mcpServers"`, it launches:

```bash
python3 /path/to/vscode_gdrive_sessions/claude_vscode_sessions_mcp.py
```

The server runs as a **stdio MCP server** — it communicates with Claude Code via stdin/stdout using the MCP protocol. It is not an HTTP server; it has no port. It runs for as long as VSCode is open and is restarted automatically if it crashes.

On startup the server:
1. Loads `.env` from its own directory
2. Reads `AGENT_MCP_URL`, `AGENT_MCP_TOKEN` from environment
3. Imports `drive.py` lazily — only when agent-mcp is unreachable (so missing Google libs won't prevent startup)
4. Registers five tools and waits for Claude Code to call them

---

## Tool Reference

### `claude_sessions_list`

List all Claude Code chat sessions stored locally on this machine.

**Always runs locally — no agent-mcp, no network required.**

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `date` | string | No | Filter by date prefix, e.g. `"2026-02-24"` |
| `project` | string | No | Filter by partial project path, e.g. `"agent-mcp"` |

**Example chat invocations:**
- *"List my sessions from today"* → Claude calls `claude_sessions_list(date="2026-02-24")`
- *"Show sessions for the agent-mcp project"* → Claude calls `claude_sessions_list(project="agent-mcp")`
- *"List all my Claude Code sessions"* → Claude calls `claude_sessions_list()`

**Output format:**
```
Found 3 session(s):

  [2026-02-20] agent-mcp                        ID: a1b2c3d4...  "debug the plugin loader crash"
  [2026-02-22] vscode_gdrive_sessions           ID: e5f6g7h8...  "pre-release steps"
  [2026-02-24] kaliLinuxNWScripts               ID: i9j0k1l2...  "scan local network with nmap"
```

Session IDs (full UUID) are needed for `gdrive_sessions_export`. Run `claude_sessions_list` first to find them.

---

### `gdrive_list`

List files and folders inside a Google Drive folder.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `folder_id` | string | No | Drive folder ID. Defaults to `FOLDER_ID` from `.env` |

**Example chat invocations:**
- *"List my Drive files"* → Claude calls `gdrive_list()`
- *"What's in Drive folder 19uJi...?"* → Claude calls `gdrive_list(folder_id="19uJi...")`

**Output format:**
```
Contents of folder 19uJiJIrgy7ZW1gF3INfBIOBa2FSVt6PL:
  [FILE] snippet-linux-networking.txt  (id: 1ABCdef...)
  [FILE] claude-sessions-2026-02-24.txt  (id: 2GHIjkl...)
  [DIR]  archive  (id: 3MNOpqr...)
```

---

### `gdrive_read`

Read a file from Google Drive into the current chat context.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_id` | string | **Yes** | Drive file ID (from `gdrive_list`) |
| `mode` | string | No | `full` (default), `summary`, or `extract` |
| `extract_prompt` | string | Required if mode=`extract` | What to extract, e.g. `"only iptables commands"` |

**Modes:**
- `full` — returns all content verbatim; works with and without agent-mcp
- `summary` — LLM-generated summary preserving technical details; **requires agent-mcp**
- `extract` — returns only content matching your prompt; **requires agent-mcp**

**Example chat invocations:**
- *"Read Drive file 1ABCdef and summarize it"* → Claude calls `gdrive_read(file_id="1ABCdef", mode="summary")`
- *"Extract just the iptables commands from file 2GHIjkl"* → Claude calls `gdrive_read(file_id="2GHIjkl", mode="extract", extract_prompt="iptables commands only")`
- *"Show me the full contents of my networking notes"* → Claude calls `gdrive_read(file_id="...", mode="full")`

**Fallback behavior (no agent-mcp):** Returns full content regardless of mode, with a warning prepended if `summary` or `extract` was requested.

---

### `gdrive_snippet_save`

Save verbatim text content to Google Drive — create a new topic file or append to an existing one.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `content` | string | **Yes** | The text to save |
| `topic` | string | No | Topic name used as filename: `snippet-<topic>.txt` |
| `file_id` | string | No | Existing Drive file ID to append to |
| `folder_id` | string | No | Override the default Drive folder |

**Example chat invocations:**
- *"Save these iptables rules to Drive under 'firewall'"* → Claude calls `gdrive_snippet_save(content="...", topic="firewall")`
- *"Append this config snippet to file 1ABCdef"* → Claude calls `gdrive_snippet_save(content="...", file_id="1ABCdef")`

**Output:**
```
Created Drive file: snippet-firewall.txt — Created 'snippet-firewall.txt' — id: 3XYZabc...
```
or
```
Appended to Drive file ID 1ABCdef — Appended to file id: 1ABCdef
```

---

### `gdrive_sessions_export`

Export one or more local Claude Code sessions to a single file in Google Drive.

**Always reads directly from local JSONL files. Drive upload is always direct (no agent-mcp endpoint). agent-mcp is used only if `mode="summary"` to call an LLM for summarization.**

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_ids` | array of strings | **Yes** | Full session UUIDs from `claude_sessions_list` |
| `mode` | string | No | `full` (default) or `summary` |
| `summarizer` | string | No | `claude` (default) or `agent` — who performs summarization |
| `model` | string | No | agent-mcp model key when `summarizer=agent`, e.g. `nuc11Local` |
| `filename` | string | No | Drive filename. Defaults to `claude-sessions-YYYY-MM-DD.txt` |
| `folder_id` | string | No | Override the default Drive folder |

**Mode + summarizer combinations:**

| `mode` | `summarizer` | What happens | VSCode tokens |
|--------|-------------|--------------|---------------|
| `full` | (n/a) | Raw user+assistant text written to Drive directly | Zero |
| `summary` | `claude` | Full text returned to Claude in VSCode; Claude summarizes in-context before Drive write | Full session cost |
| `summary` | `agent` | agent-mcp LLM summarizes off-context; only confirmation returned to VSCode | Zero |

**Example chat invocations:**
- *"Export today's agent-mcp sessions to Drive"* → `gdrive_sessions_export(session_ids=["uuid1", "uuid2"])`
- *"Export and summarize using the local LLM"* → `gdrive_sessions_export(session_ids=[...], mode="summary", summarizer="agent", model="nuc11Local")`
- *"Summarize this session yourself and save it"* → `gdrive_sessions_export(session_ids=[...], mode="summary", summarizer="claude")`

**Output:**
```
Exported 2 session(s) to Drive: claude-sessions-2026-02-24.txt — Created 'claude-sessions-2026-02-24.txt' — id: 4LMNopq...
```

**Exported file format:**
```
======================================================================
Session: debug the plugin loader crash
Project: /home/user/projects/agent-mcp
Date:    2026-02-20T14:32:11.000Z
ID:      a1b2c3d4-...
======================================================================

[USER]
The plugin loader is crashing on import. Here's the traceback: ...

[ASSISTANT]
The issue is in the import order. Let me check ...

======================================================================
Session: pre-release steps
...
```

---

## Workflows

### Claude Code in VSCode Workflows

All five tools are available in any VSCode chat. Claude decides which tool to call based on natural language. The session ID shown by `claude_sessions_list` is the full UUID needed by `gdrive_sessions_export`.

#### List sessions

```
"Show me my Claude Code sessions from today"
"List sessions for the agent-mcp project"
"Show all my sessions"
```
→ `claude_sessions_list(date="2026-02-24")` — runs locally, no network

#### Export full session to Drive (no tokens consumed)

```
"Export session ee159cbc-64e8-44d8-9451-13d91886f1f9 to Drive"
"Save today's vscode_gdrive_sessions session to Drive as a full log"
```
→ `gdrive_sessions_export(session_ids=["ee159cbc-..."], mode="full")`
Raw text written directly to Drive. Zero VSCode tokens spent on session content.

#### Export and summarize via local LLM through agent-mcp (no VSCode tokens)

```
"Summarize session ee159cbc using the local LLM and save to Drive"
"Export and summarize these sessions using nuc11Local — save as context-2026-02-25.txt"
```
→ `gdrive_sessions_export(session_ids=["ee159cbc-..."], mode="summary", summarizer="agent", model="nuc11Local", filename="context-2026-02-25.txt")`
agent-mcp's `llm_call()` runs summarization. Only the confirmation returns to VSCode. Zero VSCode tokens spent on session content.

#### Export and summarize with Claude in VSCode (Claude-quality summary, in-context)

```
"Summarize this session yourself and save it to Drive"
```
→ `gdrive_sessions_export(session_ids=["ee159cbc-..."], mode="summary", summarizer="claude")`
Full session text is returned to Claude Code. Claude summarizes it in-context, then writes the result to Drive. Consumes VSCode tokens proportional to session size.

#### Save a snippet during a session

```
"Save this nginx config to Drive under 'nginx'"
"Append these iptables rules to my firewall notes file"
```
→ `gdrive_snippet_save(content="...", topic="nginx")`
→ `gdrive_snippet_save(content="...", file_id="1ABCdef...")`

#### Read a Drive file back into context

```
"Read my nginx notes from Drive"
"Load my networking context file and summarize it"
```
→ `gdrive_list()` then `gdrive_read(file_id="...", mode="full")`

#### List Drive folder contents

```
"What files are in my Drive folder?"
"List my Drive context files"
```
→ `gdrive_list()`

---

### Prompting an LLM to Pull VSCode Session Data Autonomously

When the `vscode` toolset is bound to a model in `llm-tools.json` and `llm-models.json`, the LLM can call `vscode_sessions_list` and `vscode_sessions_read` as tools on its own — no `!vscode` command needed.

> **Note:** `vscode_sessions_list` and `vscode_sessions_read` read from `~/.claude/projects/` on the machine where agent-mcp is running. If agent-mcp is on a remote machine, it sees that machine's sessions. In the typical setup (agent-mcp and VSCode on the same host), all sessions are visible.

#### Prerequisites

1. `llm-tools.json` must include the `vscode` toolset (added in the sync):
   ```json
   "vscode": ["vscode_sessions_list", "vscode_sessions_read"]
   ```

2. The model's `llm_tools` array in `llm-models.json` must include `"vscode"`:
   ```json
   "gemini25fl": {
     "llm_tools": ["core", "db", "search", "drive", "vscode", "extract"]
   }
   ```

3. The `plugin_claude_vscode_sessions` plugin must be enabled in `plugins-enabled.json`.

#### How to prompt it

The LLM needs enough context to know what to look for. Give it a project name, date, or topic — not just "my sessions":

```
What progress did I make on the agent-mcp gate system last week?
```
→ LLM calls `vscode_sessions_list(project="agent-mcp", date="2026-02-")`, then `vscode_sessions_read(session_ids="a1b2c3d4", mode="full")`

```
Summarize what I built yesterday in the vscode_gdrive_sessions project.
```
→ LLM calls `vscode_sessions_list(date="2026-02-24", project="vscode_gdrive_sessions")`, then `vscode_sessions_read(session_ids="...", mode="summary")`

```
Look at my recent agent-mcp sessions and tell me what's left to implement.
```
→ LLM lists sessions, reads the most recent ones, then reasons over the content.

```
Pull the session where I fixed the 404 fallback bug and summarize it using gemini25fl.
```
→ LLM calls `vscode_sessions_list(project="vscode_gdrive_sessions")` to find candidate sessions, then `vscode_sessions_read(session_ids="...", mode="summary", model="gemini25fl")`

#### Prompting tips

- **Name the project**: "my agent-mcp sessions" works better than "my sessions" — the LLM filters by project path.
- **Give a date or recency hint**: "yesterday", "last week", or `date=2026-02-24` narrows the list and avoids reading irrelevant sessions.
- **Specify `mode=summary` for large sessions**: Raw sessions can be 40k+ tokens. Ask the LLM to summarize rather than read verbatim when you just want the gist.
- **Specify `model=` for off-context summarization**: If you want summarization done by a local or cheap model rather than the active one, say so: *"use gemini25fl to summarize"*.
- **Chaining works naturally**: After the LLM reads a session, follow up in the same turn — the content is already in its context window.

#### What the tools return

`vscode_sessions_list` returns a compact list:
```
Found 3 session(s):

  [2026-02-24] agent-mcp          ID: a1b2c3d4...  "debug plugin loader crash"
  [2026-02-24] agent-mcp          ID: e5f6g7h8...  "pre-release checklist"
  [2026-02-24] vscode_gdrive_ses  ID: ee159cbc...  "claude_vscode_sessions_mcp pre-release"
```

`vscode_sessions_read` returns user+assistant turns (tool calls and results stripped), prefixed with a session header. The LLM receives this as a tool result and can reason over it immediately.

#### Token cost

| Prompt style | Tokens on session content |
|---|---|
| `mode=full` on a large session | ~40k tokens (raw) |
| `mode=summary` with active model | Full session cost once, ~2k summary retained |
| `mode=summary, model=gemini25fl` | Off-context summarization — only ~2k summary enters the active context |

---

### agent-mcp Client Workflows (Slack, shell.py, API)

These commands work in any agent-mcp chat client. The `!vscode` command is wired directly into routes.py alongside `!config`, `!limits`, and other built-in commands.

#### List local VSCode sessions from Slack/shell

```
!vscode list
!vscode list date=2026-02-24
!vscode list project=agent-mcp
!vscode list date=2026-02-24 project=agent-mcp
```
Returns session IDs and titles. The 8-char prefix shown is enough for the `read` subcommand (prefix matching is supported).

**Example Slack output:**
```
Found 3 session(s):

  [2026-02-24] agent-mcp          ID: a1b2c3d4...  "debug plugin loader crash"
  [2026-02-24] agent-mcp          ID: e5f6g7h8...  "pre-release checklist"
  [2026-02-24] vscode_gdrive_ses  ID: ee159cbc...  "claude_vscode_sessions_mcp pre-release"
```

#### Pull full session text into agent-mcp chat context

```
!vscode read a1b2c3d4
!vscode read a1b2c3d4,e5f6g7h8
```
Session text is streamed into the chat. Follow with a plain-text message and the LLM sees it as context:

```
!vscode read a1b2c3d4

What are the key decisions made in that session?
```

#### Pull session as summary via agent-mcp LLM

```
!vscode read a1b2c3d4 mode=summary
!vscode read a1b2c3d4,e5f6g7h8 mode=summary model=nuc11Local
!vscode read ee159cbc mode=summary model=gemini25fl
```
`llm_call()` is invoked with the summarization prompt. The selected model (`model=` key from `llm-models.json`) performs the summarization. If `model=` is omitted, the agent-mcp default model is used.

**Example full Slack workflow:**
```
You:    !vscode list project=agent-mcp date=2026-02-24

Bot:    Found 2 session(s):
          [2026-02-24] agent-mcp   ID: a1b2c3d4...  "debug plugin loader crash"
          [2026-02-24] agent-mcp   ID: e5f6g7h8...  "pre-release checklist"

You:    !vscode read a1b2c3d4,e5f6g7h8 mode=summary model=nuc11Local

Bot:    [llm_call ▶] nuc11Local [text sp=none hist=none]: Summarize this Claude Code...
        ======================================================================
        Session: debug plugin loader crash
        ...
        Topics: import ordering fix, asyncio.to_thread pattern, ...
        ======================================================================
        Session: pre-release checklist
        ...
        Topics: setup.sh script bug, README structure, Drive fallback fix...

You:    Given that context, what's the remaining work before we push to GitHub?

Bot:    Based on the two sessions, the remaining items are...
```

#### Push to Drive from any agent-mcp client

Drive operations use the built-in `!google_drive` command (agent-mcp's own Drive plugin):

```
!google_drive list
!google_drive read <file_id>
!google_drive create my-notes.txt This is the content of my file.
!google_drive append <file_id> Additional content to append.
```

The LLM can also call the `google_drive` tool autonomously during conversation if it is in the active toolset.

---

## agent-mcp Integration Details

### Session API Endpoints

These HTTP endpoints are available on the agent-mcp server for any HTTP client:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/vscode/sessions/list` | GET | List local sessions with metadata |
| `/vscode/sessions/read` | GET | Return assembled session text |

**`/vscode/sessions/read` query params:**
- `session_ids` — comma-separated UUIDs
- `mode` — `full` (default) or `summary`
- `model` — agent-mcp model key for summarization (e.g. `nuc11Local`, `gemini25fl`)

### LLM Summarization

When `mode=summary` is requested (via `/vscode/sessions/read`, `!vscode read`, or `gdrive_sessions_export` with `summarizer=agent`), agent-mcp calls `llm_call()` with:

```
Summarize this Claude Code chat session.
Preserve specific commands, syntax, config values, and technical details verbatim.
Organize into clearly labeled topic sections.

---
[session text]
---
```

The model is selected from `llm-models.json`. A locally-hosted model (e.g. `localModel` pointing to `http://localhost:8000/v1`) costs nothing per token.

### Token Savings

| Approach | VSCode tokens on session content | Summary quality |
|----------|----------------------------------|-----------------|
| `mode=full` export + `gdrive_read(full)` later | Full session cost each read | N/A |
| `mode=summary, summarizer=claude` | Full session cost once | Claude-quality |
| `mode=summary, summarizer=agent, model=nuc11Local` | **Zero** | Local LLM quality |
| `mode=summary, summarizer=agent, model=gemini25fl` | **Zero** | Gemini quality |

A typical 60-message session is ~40,000 tokens raw. After summarization it is ~2,000–4,000 tokens. Reading it back from Drive later costs 2,000 tokens instead of 40,000. The savings compound across sessions and repeated reads.

---

## Security Notes

- `.env`, `credentials.json`, and `token.json` are in `.gitignore` and must never be committed
- `AGENT_MCP_TOKEN` must match `API_KEY` in agent-mcp's `.env`
- `drive.py` rejects hallucinated `folder_id` values (e.g. `<placeholder>`, `root`, `your-folder-id`) and falls back to the configured `FOLDER_ID`
- Google Drive access uses the full `drive` scope; restrict to `drive.file` if you want to limit access to only files this app creates

---

## Troubleshooting

**MCP server doesn't appear in Claude Code:**
- Verify `~/.claude.json` contains the `"gdrive"` entry under `"mcpServers"`
- Restart VSCode after running the setup script
- Check that `python3` is in your PATH as seen by VSCode's shell

**`claude_sessions_list` returns no sessions:**
- Confirm `~/.claude/projects/` exists and contains `.jsonl` files
- Sessions with zero messages (orphaned snapshots) are filtered out automatically

**Drive operations fail with "Configuration Error: FOLDER_ID not set":**
- Add `FOLDER_ID=<your-google-drive-folder-id>` to `.env`
- The folder ID is the long alphanumeric string at the end of your Drive folder's URL

**First Drive operation opens a browser:**
- This is expected — complete the Google OAuth consent flow
- After approval, `token.json` is written and subsequent operations are silent

**`summary`/`extract` modes return full content with a warning:**
- agent-mcp is not running or not reachable at `AGENT_MCP_URL`
- Start agent-mcp and verify `AGENT_MCP_URL` in `.env` is correct

**agent-mcp returns 401:**
- `AGENT_MCP_TOKEN` in `.env` must match `API_KEY` in agent-mcp's `.env`

**`!vscode` not recognized in Slack/shell:**
- Restart agent-mcp so it picks up the updated `routes.py` and `plugin_claude_vscode_sessions.py`
