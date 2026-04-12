# Claude Code — Custom Statusline

A compact statusline for Claude Code with 5 fields and visual references:

```
branch main  │  model Opus 4.6  │  effort max  │  ctx ████░░░░░░ 42%  │  sess █░░░░░░░░░ 18%
```

## What it shows

| Field    | Color   | Source                                                                         |
|----------|---------|--------------------------------------------------------------------------------|
| `branch` | blue    | current git branch of the workspace                                            |
| `model`  | orange  | `model.display_name` from stdin JSON                                           |
| `effort` | purple  | last `/effort` of the session (transcript) or `effortLevel` from `settings.json` |
| `ctx`    | bar+%   | `context_window.used_percentage`                                               |
| `sess`   | bar+%   | `rate_limits.five_hour.used_percentage`                                        |

Bars are 10 cells wide (`█` filled / `░` empty) and change color by threshold:
- **green** if `<70%`
- **yellow** if `70–89%`
- **red** if `≥90%`

Labels (`branch`, `model`, `effort`, `ctx`, `sess`) are rendered in dim grey so they serve as visual references without competing with the values.

## Dependencies

- **`bash`** — native on macOS/Linux. On Windows it ships with [Git for Windows](https://git-scm.com/download/win) (Git Bash).
- **`jq`** — command-line JSON parser. The only thing likely to be missing:
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt install jq`
  - Windows: `winget install jqlang.jq` *(or `choco install jq`)*
- **`git`** — already installed if you are using Claude Code.
- **Terminal with UTF-8 + ANSI 256-color** — Windows Terminal, iTerm2, gnome-terminal, mintty. Any modern terminal works.

## Installation

### 1. Copy the script

Copy `statusline-command.sh` to `~/.claude/statusline-command.sh`:

**macOS / Linux:**
```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

**Windows (Git Bash):**
```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
```
*(On Windows you don't need `chmod` because the script is invoked via `bash` explicitly.)*

### 2. Configure `settings.json`

Edit `~/.claude/settings.json` (or create it if it doesn't exist) and add the `statusLine` block. The `command` value changes depending on the OS:

**macOS / Linux:**
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

**Windows (Git Bash):**
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /c/Users/<USERNAME>/.claude/statusline-command.sh"
  }
}
```

Replace `<USERNAME>` with your actual user. The `/c/Users/...` path is the MSYS/Git Bash format for `C:\Users\...` — Claude Code invokes the command via Git Bash and `~` sometimes doesn't expand correctly in that context.

**If `settings.json` already exists** with other fields (`model`, `effortLevel`, etc.), just add the `statusLine` block while keeping the rest:

```json
{
  "model": "opus",
  "effortLevel": "medium",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

### 3. Restart Claude Code

The statusline refreshes after every assistant response. Once you restart Claude Code it should already be visible.

## Try it before trusting it

To verify that `jq`, `git` and the script work without errors, simulate the JSON that Claude Code sends over stdin:

```bash
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":18}}}' \
  | bash ~/.claude/statusline-command.sh
echo
```

Expected output (with real colors in a terminal):
```
branch main  │  model Opus 4.6  │  effort medium  │  ctx ████░░░░░░ 42%  │  sess █░░░░░░░░░ 18%
```

If you see raw codes like `\033[38;5;39m`, the terminal isn't interpreting ANSI (unlikely in 2026, but possible in legacy `cmd.exe`).

## About the `effort` field

Claude Code **does not expose** the effort level in the JSON the statusline receives, and the `/effort max` command applies "this session only" without writing to `settings.json`. To reflect the real value the script uses this resolution chain:

1. **Session transcript.** The stdin JSON includes `transcript_path`. The script searches that file for the last user message containing `<command-name>/effort</command-name>` and extracts its `<command-args>`. This captures both `/effort max` (session-only) and `/effort high|low|medium` (persistent).
2. **`settings.json` (`effortLevel`).** If no `/effort` is found in the transcript (freshly opened session), it falls back to this value.
3. **`"medium"`.** Default if neither of the above applies.

The grep uses the exact prefix `"content":"<command-name>/effort</command-name>` to match only real user messages, discarding `tool_results` that might contain historical references to the same text (important if the script itself ends up grepping the transcript on a previous turn).

**Cost:** a `grep -F` over a ~1 MB jsonl runs in a few ms, negligible compared to the cost of the `jq` calls.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Empty statusline | `jq` not installed | Install `jq` with your OS package manager |
| `statusline skipped · restart to fix` | Workspace not trusted | Restart Claude Code and accept the trust dialog |
| Shows `branch -` | The cwd is not a git repo | Normal outside of repos; not an error |
| `sess` always at 0% | Not a Claude.ai Pro/Max subscriber, or it's the first turn before the first API call | `rate_limits` only appears for subscribers after the first response |
| Raw ANSI codes visible | Terminal isn't interpreting escape sequences | Use a modern terminal (Windows Terminal, iTerm2, etc.) |
| `effort` always `medium` | Freshly opened session with no prior `/effort` AND `effortLevel` missing from `settings.json` | Run any `/effort <value>` in the session or add `"effortLevel": "..."` to `settings.json` |

## Customization

Color codes are defined at the top of the script. To change them, edit these lines:

```bash
BR='\033[38;5;39m'   # blue   — branch
MD='\033[38;5;208m'  # orange — model
EF='\033[38;5;135m'  # purple — effort
```

The `\033[38;5;N m` codes are 256-color (N = 0-255). Reference table: [256 color cheatsheet](https://www.ditig.com/256-colors-cheat-sheet).

To change the bar width, modify `width=10` inside `build_bar()`.

To change the green/yellow/red thresholds, edit the `-ge 90` / `-ge 70` checks in the "Color según umbral" section.

## Files in this directory

```
statusbar/
├── README.md               ← this file
└── statusline-command.sh   ← the script to copy to ~/.claude/
```
