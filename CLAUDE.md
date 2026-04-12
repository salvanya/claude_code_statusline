# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-file bash statusline script (`statusline-command.sh`) that users copy to `~/.claude/statusline-command.sh` and wire up via `~/.claude/settings.json`. There is no build, no dependency install, no test suite — editing the script and verifying output is the entire development loop.

`statusline.md` is a local copy of the upstream Claude Code docs page on statuslines — use it as reference for the stdin JSON contract, not as something to edit.

## Testing changes

Simulate the stdin JSON Claude Code sends and pipe it through the script:

```bash
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":18,"resets_at":'"$(($(date +%s)+3600))"'}}}' \
  | bash statusline-command.sh
echo
```

Vary `used_percentage` across the 0–69 / 70–89 / 90–100 bands to verify the green/yellow/red threshold logic.

To test the `/effort` resolution path, point `transcript_path` at a real session jsonl (or a crafted one containing a line with `"content":"<command-name>/effort</command-name>...<command-args>max</command-args>`).

## Architecture notes that aren't obvious from the code

**Effort resolution is deliberately grep-based, not jq-based.** Claude Code does not expose the current effort level in stdin JSON, and `/effort max` applies "this session only" without writing to `settings.json`. The script therefore greps the session transcript (`transcript_path`) for the last user-issued `/effort` command, falling back to `effortLevel` in `settings.json`, then to `"medium"`. The `grep -F '"content":"<command-name>/effort</command-name>'` prefix is intentional: it matches only real user messages and excludes `tool_result` blocks that could embed historical `/effort` strings — including from prior turns where this script itself grepped the transcript. Do not loosen that pattern.

**Git branch is read from `workspace.current_dir`, not the shell's cwd.** The statusline script's cwd is not guaranteed to be the workspace. Always pass `-C "$cwd"` to `git`, and use `--no-optional-locks` to avoid racing with concurrent git operations in the user's editor.

**Threshold colors must stay synchronized between `ctx` and `sess`.** Both bars use the same 70 / 90 cutoffs; changing one without the other will produce confusing UX. The thresholds live in the "Color según umbral" section.

**Bar width is 10 cells, hardcoded in `build_bar()`.** Percent-to-cells math is integer division (`pct * width / 100`), so with width=10 each cell = 10%. If you change `width`, the visual granularity changes proportionally.

## Platform constraints

- The script is invoked via `bash` on all platforms (including Windows via Git Bash). Do not use features that require a specific shell beyond bash 3.2+ — macOS still ships bash 3.2.
- Required external binaries: `jq`, `git`, `date`, `grep`, `sed`, `tail`, `printf`. All are expected to be on `PATH`; `jq` is the only one likely to be missing and is the documented failure mode.
- Output uses ANSI 256-color escapes (`\033[38;5;Nm`). Keep `printf "%b"` for the final emit so escape sequences interpolate correctly.
