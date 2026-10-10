# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-file bash statusline script (`bin/statusline-command.sh`) that users copy to `~/.claude/statusline-command.sh` and wire up via `~/.claude/settings.json`. There is no build, no dependency install, no test suite — editing the script and verifying output is the entire development loop.

`docs/statusline.md` is a local copy of the upstream Claude Code docs page on statuslines — use it as reference for the stdin JSON contract, not as something to edit. `docs/img.png` is the preview screenshot embedded in the README.

Repo layout:

```
bin/statusline-command.sh   ← the script
docs/statusline.md          ← upstream reference (read-only)
docs/img.png                ← preview screenshot rendered in README
```

## Testing changes

Simulate the stdin JSON Claude Code sends and pipe it through the script:

```bash
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":18,"resets_at":'"$(($(date +%s)+3600))"'},"seven_day":{"used_percentage":41,"resets_at":'"$(($(date +%s)+3*86400))"'}}}' \
  | bash bin/statusline-command.sh
echo
```

Vary `used_percentage` across the 0–69 / 70–89 / 90–100 bands to verify the green/yellow/red threshold logic.

Also cover the degraded inputs Claude Code really sends: `context_window.used_percentage: null` (early session), no `rate_limits` (non-subscribers, or before the first API response), no `effort` (model without effort support), and a run with `jq` off `PATH` (e.g. `PATH=/usr/bin:/bin`) to check the "falta jq" message.

## Architecture notes that aren't obvious from the code

**Effort comes from `effort.level` in stdin JSON — nothing else.** It reflects the live session value, including mid-session `/effort` changes and per-model `modelSettings`. It is absent when the current model doesn't support effort, and the script then shows `-`. Do not fall back to `settings.json` or grep the transcript: earlier versions did that (before Claude Code exposed the field) and it showed stale or invented values.

**All stdin parsing happens in a single `jq` call.** It emits the fields joined by `\x1f` (ASCII unit separator) and `read` splits them. The separator must stay a non-whitespace char: with tab or space, `read` collapses consecutive separators and empty fields shift into the wrong variables. Absent/null values become `""` so the output shows `--` instead of a misleading `0%`. If `jq` is missing, the script prints a short install hint and exits — that was the real cause of the "everything empty, effort medium" breakage when `jq` vanished from `PATH`.

**Git branch is read from `workspace.current_dir`, not the shell's cwd.** The statusline script's cwd is not guaranteed to be the workspace. Always pass `-C "$cwd"` to `git`, and use `--no-optional-locks` to avoid racing with concurrent git operations in the user's editor.

**Threshold colors are shared by `ctx`, `sess` and `week`.** The 70 / 90 cutoffs live only in `pct_color()` ("Color según umbral" section); keep it that way rather than inlining comparisons per segment.

**The `week` segment is conditional, `sess` is not.** `sess` always renders (with `--` when there's no data) because it's the field users look for; `week` only appears when `rate_limits.seven_day` is present, to avoid a permanently empty segment for API-key users. The reset countdown only advances when the script re-runs, so the documented setup uses `refreshInterval: 60`.

**Bar width is 10 cells, hardcoded in `build_bar()`.** Percent-to-cells math is integer division (`pct * width / 100`), so with width=10 each cell = 10%. If you change `width`, the visual granularity changes proportionally.

## Platform constraints

- The script is invoked via `bash` on all platforms (including Windows via Git Bash). Do not use features that require a specific shell beyond bash 3.2+ — macOS still ships bash 3.2.
- Required external binaries: `jq`, `git`, `date`, `printf`. All are expected to be on `PATH`; `jq` is the only one likely to be missing and is the documented failure mode.
- Output uses ANSI 256-color escapes (`\033[38;5;Nm`). Keep `printf "%b"` for the final emit so escape sequences interpolate correctly.
