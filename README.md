# vscode-gdrive-sessions-mcp

An MCP (Model Context Protocol) server that bridges **Claude Code in VSCode** with **Google Drive** — letting you list, export, save, and retrieve your chat sessions and snippets directly from any Claude Code conversation.

---

## Who This Is For and What It's Worth

This is an honest assessment of the value this MCP provides, so you can decide whether it's worth setting up for your situation.

### What you could do without it

Claude Code already has filesystem access. A determined user could ask Claude to parse `~/.claude/projects/` directly, write an inline JSONL extractor, and read session files. For Drive access, there is no equivalent — Claude Code has no built-in Drive integration at all.

### What this MCP actually gives you

**At minimum: convenience.** Session listing and reading are purpose-built tools with consistent, clean output — no scaffolding required each time. The JSONL format is noisy (tool calls, system entries, metadata), and this MCP pre-filters it to just the human conversation. That scaffolding cost adds up across daily use.

**The real value: Google Drive as offline memory.** The integration work for Drive auth, upload, download, and append is done. You can export a session — or a summary of one — to Drive in a single natural-language request. That Drive file then becomes accessible to anything else: a phone, a voice assistant, another LLM, a different machine. A concrete example: export a summary of a deep coding thread before leaving work, then have a voice-capable LLM on your phone read it back during the commute. You arrive at the next session already re-oriented.

**Token economics matter at scale.** A typical coding session runs 40,000–100,000 tokens of raw JSONL. Every time you read that back into Claude's context, you pay those tokens again. Exporting a summary once — using a local model like Ollama at zero cost — and reading the 2,000-token summary later instead saves the difference on every subsequent recall. Across multiple ongoing threads, this compounds.

**Multi-thread and multi-project work.** Technical work — whether coding or operational IT — rarely stays in one thread. This MCP gives Claude a practical way to recall what was decided in a previous session, what was left unfinished, or what approach was taken for a problem that looks similar to the current one. Without persistent memory across sessions, you re-explain context each time. With exported summaries readable from Drive, Claude can be briefed in seconds.

### What it does not do

It does not give Claude Code persistent memory on its own — session export and re-import is a deliberate manual step, not automatic. It does not replace a proper knowledge base or RAG system for large corpora. The session listing and reading tools are convenience wrappers; a power user who knows the file paths and JSONL structure could replicate them through prompting.

---

## What It Does

The server exposes five tools to Claude Code chat:

| Tool | Requires agent-mcp? | Purpose |
|------|---------------------|---------|
| `claude_sessions_list` | No | List all local Claude Code sessions on this machine |
| `claude_sessions_read` | For summary mode | Read session content into context — no Drive write |
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
      ├─ claude_sessions_read ──────► agent-mcp /vscode/sessions/read  (summary mode)
      │                               └─ fallback: local JSONL read (full mode or agent-mcp offline)
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

**agent-mcp** (separate repo) is a self-hosted HTTP API server that acts as a multi-model LLM gateway and tool dispatcher. It manages a registry of language models (cloud APIs, local GGUF models via llama.cpp, Ollama, etc.), routes chat messages through them, and exposes a set of HTTP endpoints and LangChain tools for operations like Drive I/O, database queries, and VSCode session access. When reachable, it handles Drive operations and LLM summarization for this MCP server. When unreachable, `drive.py` in this repo provides a direct fallback for all operations except LLM-based `summary` and `extract` modes.

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

Drive credentials are required for two things: all `gdrive_*` operations when agent-mcp is not running, and always for `gdrive_sessions_export` (which writes directly regardless of agent-mcp status).

#### What `drive.py` supports today

`drive.py` implements **OAuth 2.0 Desktop (Installed App) flow** only — the standard flow for a script running on your own machine, accessing your own Google Drive. This is what most personal/developer setups need.

**Step 1 — Enable the Drive API**

Go to [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Library → search "Google Drive API" → Enable.

**Step 2 — Create OAuth credentials**

APIs & Services → Credentials → Create Credentials → **OAuth 2.0 Client ID** → Application type: **Desktop app** → name it anything → Create.

Download the JSON file. Rename it `credentials.json` (or keep the generated name and set `DRIVE_CREDS_FILE` in `.env`).

**Step 3 — Set your Drive folder ID**

In Google Drive, open the folder you want to use. Copy the folder ID from the URL:
```
https://drive.google.com/drive/folders/19uJiJIrgy7ZW1gF3INfBIOBa2FSVt6PL
                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                        this is your FOLDER_ID
```

Set it in `.env`:
```bash
FOLDER_ID=19uJiJIrgy7ZW1gF3INfBIOBa2FSVt6PL
DRIVE_CREDS_FILE=/path/to/credentials.json
```

**Step 4 — First run: browser consent**

The first time a Drive operation runs, a browser window opens asking you to sign into your Google account and grant access. After approval, a `token.json` is written next to `credentials.json` and reused silently on all subsequent runs. Token refresh is automatic.

---

#### Other credential methods — what would need to change

Google Drive supports several other authentication approaches. None are implemented in `drive.py` today, but here is what a third party would need to do to add each:

**Service Account** — best for automation with no user present. Instead of OAuth consent, you create a service account in Cloud Console, download its JSON key, and share your Drive folder with the service account's email address (`name@project.iam.gserviceaccount.com`). To integrate: replace `InstalledAppFlow` / `Credentials.from_authorized_user_file` in `_get_drive_service()` with `google.oauth2.service_account.Credentials.from_service_account_file(key_path, scopes=DRIVE_SCOPES)`. Add `DRIVE_SERVICE_ACCOUNT_FILE` to `.env`. No `token.json` is needed — service accounts use short-lived tokens minted on-the-fly from the key.

**Application Default Credentials (ADC)** — best for code that runs in multiple environments (local, CI, Google Cloud). Call `google.auth.default(scopes=DRIVE_SCOPES)` instead of the current flow; the library finds credentials automatically from `GOOGLE_APPLICATION_CREDENTIALS`, `gcloud auth application-default login`, or the compute metadata server. No file path configuration needed — just set the env var to point at whichever credential file applies to the environment.

**Workload Identity Federation** — best for CI/CD pipelines (GitHub Actions, GitLab, AWS) that should never hold a long-lived key file. A short-lived token from the CI provider (e.g. GitHub's OIDC token) is exchanged for a Google access token via Google's Security Token Service. To integrate: generate a WIF credential configuration file from Cloud Console, set `GOOGLE_APPLICATION_CREDENTIALS` to it, and use ADC as above — no other code change required since the Google libraries handle the exchange transparently.

**`gcloud auth application-default login`** — easiest for local development if you already have the Google Cloud SDK installed. Run `gcloud auth application-default login` once; the resulting credentials in `~/.config/gcloud/application_default_credentials.json` are picked up automatically by ADC. No `credentials.json` or `token.json` needed. Note: Google discourages this for production use since the credentials are tied to your personal account.

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
  "claude-sessions": {
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

Claude Code reads `~/.claude.json` on startup. When it finds the `"claude-sessions"` entry under `"mcpServers"`, it launches:

```bash
python3 /path/to/vscode_gdrive_sessions/claude_vscode_sessions_mcp.py
```

The server runs as a **stdio MCP server** — it communicates with Claude Code via stdin/stdout using the MCP protocol. It is not an HTTP server; it has no port. It runs for as long as VSCode is open and is restarted automatically if it crashes.

On startup the server:
1. Loads `.env` from its own directory
2. Reads `AGENT_MCP_URL`, `AGENT_MCP_TOKEN` from environment
3. Imports `drive.py` lazily — only when agent-mcp is unreachable (so missing Google libs won't prevent startup)
4. Registers six tools and waits for Claude Code to call them

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

  [2026-02-20] agent-mcp                        ID: a1b2c3d4...   142kB  "debug the plugin loader crash"
  [2026-02-22] vscode_gdrive_sessions           ID: e5f6g7h8...    38kB  "pre-release steps"
  [2026-02-24] kaliLinuxNWScripts               ID: i9j0k1l2...    12kB  "scan local network with nmap"
```

Session IDs (full UUID or 8-char prefix) are used by `claude_sessions_read` and `gdrive_sessions_export`. Run `claude_sessions_list` first to find them.

---

### `claude_sessions_read`

Read one or more local Claude Code sessions directly into the current chat context. **Nothing is written to Drive.**

Use this to review, summarize, or reason over past sessions inline — without saving anywhere.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_ids` | array of strings | **Yes** | Session UUIDs or 8-char prefixes from `claude_sessions_list` |
| `mode` | string | No | `full` (default/preferred) or `summary` |
| `model` | string | No | agent-mcp model key for `mode='summary'`. Empty = agent-mcp default |

**Modes:**
- `full` — returns raw user+assistant text; Claude Code summarizes in-context (preferred, no extra API call)
- `summary` — delegates to agent-mcp LLM for pre-summarization before returning; use only if the session is too large to fit in context

**Example chat invocations:**
- *"Read today's agent-mcp session and tell me what was accomplished"* → Claude calls `claude_sessions_read(session_ids=["a1b2c3d4"], mode="full")`
- *"Summarize yesterday's vscode_gdrive_sessions work using nuc11Localtokens"* → Claude calls `claude_sessions_read(session_ids=["e5f6g7h8"], mode="summary", model="nuc11Localtokens")`

**Fallback behavior (agent-mcp offline):** `mode="summary"` falls back to returning full text with a warning prepended.

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

#### Read a session into context (no Drive write)

```
"What did I work on in the agent-mcp project yesterday?"
"Summarize today's vscode_gdrive_sessions session using nuc11Localtokens"
"Read session a1b2c3d4 and tell me what decisions were made"
```
→ `claude_sessions_list(project="agent-mcp", date="2026-02-24")` then `claude_sessions_read(session_ids=["a1b2c3d4"], mode="full")`

Content appears directly in this chat. No Drive write. For `mode="full"`, Claude reads the raw text in-context and summarizes itself (zero extra API calls). For `mode="summary"`, agent-mcp's LLM pre-summarizes (one extra API call, saves VSCode context tokens for very large sessions).

---

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
- Verify `~/.claude.json` contains the `"claude-sessions"` entry under `"mcpServers"`
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

---

## Summarizing Sessions Without agent-mcp

Without agent-mcp, `mode="summary"` is unavailable. The tools that still work fully are `claude_sessions_list`, `claude_sessions_read` (full mode), and all Drive operations via the OAuth2 fallback. You can still get summaries — you just bring your own model.

### Option 1 — Manual: copy-paste into any LLM

The session files are plain JSONL at `~/.claude/projects/<project-dir>/<session-uuid>.jsonl`. To read one as human-readable text:

```bash
# Find the file
ls ~/.claude/projects/

# Extract just the user+assistant turns
python3 - <<'EOF'
import json, sys
for line in open(sys.argv[1]):
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if obj.get("type") not in ("user", "assistant"):
        continue
    role = obj.get("message", {}).get("role", "").upper()
    content = obj.get("message", {}).get("content", [])
    text = content if isinstance(content, str) else \
           " ".join(c["text"] for c in content if isinstance(c, dict) and c.get("type") == "text")
    if text.strip():
        print(f"\n[{role}]\n{text.strip()}")
EOF ~/.claude/projects/<project-dir>/<session-uuid>.jsonl
```

Paste the output into ChatGPT, Claude.ai, Gemini, or any web UI with a prompt like:

> Summarize this Claude Code session. Preserve specific commands, config values, and technical decisions verbatim. Organize by topic.

### Option 2 — Programmatic: pipe to a local Ollama model

If you have [Ollama](https://ollama.com/) running locally, you can pipe the extracted session text straight to it:

```bash
# Install and start Ollama (one-time)
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5:7b
```

Then summarize a session in one command:

```bash
SESSION=~/.claude/projects/<project-dir>/<session-uuid>.jsonl

python3 - <<'EOF' | ollama run qwen2.5:7b "Summarize this Claude Code session. Preserve commands and technical details verbatim. Organize by topic.\n$(cat)"
import json, sys
for line in open(sys.argv[1]):
    try: obj = json.loads(line)
    except: continue
    if obj.get("type") not in ("user", "assistant"): continue
    role = obj.get("message", {}).get("role", "").upper()
    content = obj.get("message", {}).get("content", [])
    text = content if isinstance(content, str) else \
           " ".join(c["text"] for c in content if isinstance(c, dict) and c.get("type") == "text")
    if text.strip(): print(f"\n[{role}]\n{text.strip()}")
EOF "$SESSION"
```

Or more cleanly, using Ollama's REST API directly:

```bash
SESSION_TEXT=$(python3 extract_session.py ~/.claude/projects/<project-dir>/<session-uuid>.jsonl)

curl http://localhost:11434/api/generate -s -d @- <<EOF | python3 -c "import sys,json; [print(json.loads(l).get('response',''),end='') for l in sys.stdin]"
{
  "model": "qwen2.5:7b",
  "prompt": "Summarize this Claude Code session. Preserve commands and technical details verbatim.\n\n$SESSION_TEXT",
  "stream": true
}
EOF
```

Save `extract_session.py` with the extraction logic from Option 1 for reuse.

### Finding session files

`claude_sessions_list` (via this MCP server in VSCode) is the easiest way to find the right session UUID and project directory. Alternatively, sort by modification time from the shell:

```bash
ls -lt ~/.claude/projects/**/*.jsonl | head -10
```
