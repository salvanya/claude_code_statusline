#!/usr/bin/env bash
# Claude Code statusline
# Muestra: rama git | modelo | esfuerzo | % contexto | % sesión 5h
#
# Referencia visual:
#   branch = rama git actual del workspace
#   model  = modelo de Claude en uso
#   effort = último /effort de la sesión, con fallback a effortLevel en settings.json
#   ctx    = % de la ventana de contexto usada
#   sess   = % del límite de uso de la sesión 5h
#
# Barras ASCII (10 celdas):
#   █ = celda ocupada    ░ = celda libre
# Colores: verde <70%  |  amarillo 70-89%  |  rojo >=90%

input=$(cat)

# ---- Colores ANSI ----
R='\033[0m'          # reset
D='\033[2m'          # dim  (labels de referencia)
BR='\033[38;5;39m'   # blue   — branch
MD='\033[38;5;208m'  # orange — model
EF='\033[38;5;135m'  # purple — effort
GR='\033[32m'        # green  — % bajo
YL='\033[33m'        # yellow — % medio
RD='\033[31m'        # red    — % alto
GY='\033[90m'        # gray   — separador

# ---- Campos desde stdin JSON ----
cwd=$(echo        "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo      "$input" | jq -r '.model.display_name // "?"')
ctx_pct=$(echo    "$input" | jq -r '(.context_window.used_percentage // 0) | floor')
sess_pct=$(echo   "$input" | jq -r '(.rate_limits.five_hour.used_percentage // 0) | floor')
sess_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
transcript=$(echo "$input" | jq -r '.transcript_path // ""')

# ---- Tiempo restante hasta el reinicio de la ventana de 5h ----
# resets_at viene en segundos Unix. Si está ausente o en el pasado, mostramos "--".
sess_left="--"
if [ "$sess_reset" -gt 0 ]; then
  now=$(date +%s)
  remaining=$(( sess_reset - now ))
  if [ "$remaining" -gt 0 ]; then
    h=$(( remaining / 3600 ))
    m=$(( (remaining % 3600) / 60 ))
    sess_left=$(printf "%dh%02dm" "$h" "$m")
  else
    sess_left="0h00m"
  fi
fi

# ---- Rama git (desde el dir del workspace, no el cwd del shell) ----
branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && branch="-"

# ---- Nivel de esfuerzo ----
# /effort max aplica "this session only" y NO se escribe a settings.json, así
# que buscamos el último /effort real en la transcripción de la sesión actual.
# El prefijo "content":" filtra solo mensajes reales del usuario, excluyendo
# tool_results que pudieran embeber comandos de effort históricos.
effort=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  effort=$(grep -F '"content":"<command-name>/effort</command-name>' "$transcript" 2>/dev/null \
           | tail -1 \
           | sed -n 's|.*<command-args>\([a-z]*\)</command-args>.*|\1|p')
fi
# Fallback a settings.json si no hay ningún /effort en la transcripción
if [ -z "$effort" ]; then
  effort=$(jq -r '.effortLevel // "medium"' "$HOME/.claude/settings.json" 2>/dev/null)
  case "$effort" in ""|null) effort="medium" ;; esac
fi

# ---- Constructor de barra de progreso (10 celdas) ----
build_bar() {
  local pct=$1 width=10 filled empty bar=""
  [ "$pct" -gt 100 ] && pct=100
  [ "$pct" -lt 0 ]   && pct=0
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  [ "$filled" -gt 0 ] && printf -v f "%${filled}s" && bar="${f// /█}"
  [ "$empty"  -gt 0 ] && printf -v e "%${empty}s"  && bar="${bar}${e// /░}"
  printf "%s" "$bar"
}

# ---- Color según umbral ----
if   [ "$ctx_pct"  -ge 90 ]; then ctx_clr=$RD
elif [ "$ctx_pct"  -ge 70 ]; then ctx_clr=$YL
else                              ctx_clr=$GR
fi
if   [ "$sess_pct" -ge 90 ]; then sess_clr=$RD
elif [ "$sess_pct" -ge 70 ]; then sess_clr=$YL
else                              sess_clr=$GR
fi

ctx_bar=$(build_bar  "$ctx_pct")
sess_bar=$(build_bar "$sess_pct")

# ---- Composición de la línea ----
SEP="  ${GY}│${R}  "
out=""
out+="${D}branch${R} ${BR}${branch}${R}"
out+="${SEP}${D}model${R} ${MD}${model}${R}"
out+="${SEP}${D}effort${R} ${EF}${effort}${R}"
out+="${SEP}${D}ctx${R} ${ctx_clr}${ctx_bar}${R} ${ctx_pct}%"
out+="${SEP}${D}sess${R} ${sess_clr}${sess_bar}${R} ${sess_pct}% ${D}(${sess_left})${R}"

printf "%b" "$out"
