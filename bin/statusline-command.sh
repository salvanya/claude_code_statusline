#!/usr/bin/env bash
# Claude Code statusline
# Muestra: rama git | modelo | esfuerzo | % contexto | % sesión 5h | % semana 7d
#
# Referencia visual:
#   branch = rama git actual del workspace
#   model  = modelo de Claude en uso (+ "fast" si fast mode está activo)
#   effort = nivel de esfuerzo en vivo (effort.level del stdin JSON)
#   ctx    = % de la ventana de contexto usada
#   sess   = % del límite de uso de la sesión 5h + tiempo hasta el reinicio
#   week   = % del límite semanal 7d + tiempo hasta el reinicio (solo si existe)
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

# ---- jq es obligatorio ----
# Sin jq todos los campos quedan vacíos; mejor un aviso claro que una línea rota.
if ! command -v jq >/dev/null 2>&1; then
  printf "%b" "${RD}statusline: falta jq${R} ${D}(winget install jqlang.jq | brew install jq | apt install jq)${R}"
  exit 0
fi

# ---- Campos desde stdin JSON (una sola llamada a jq) ----
# Los campos ausentes o null salen como "" para poder mostrar "--" en vez de un
# 0% engañoso. Separador \x1f (no es whitespace de IFS, así que los campos
# vacíos no se colapsan).
US=$'\x1f'
IFS="$US" read -r cwd model effort fast ctx_pct sess_pct sess_reset week_pct week_reset <<EOF
$(printf '%s' "$input" | jq -r '
  def int(f): f | if type == "number" then floor | tostring else "" end;
  def str(f): f | if type == "string" then gsub("[\u001f\n]"; " ") else "" end;
  [ str(.workspace.current_dir // .cwd),
    str(.model.display_name),
    str(.effort.level),
    (if .fast_mode == true then "1" else "" end),
    int(.context_window.used_percentage),
    int(.rate_limits.five_hour.used_percentage),
    int(.rate_limits.five_hour.resets_at),
    int(.rate_limits.seven_day.used_percentage),
    int(.rate_limits.seven_day.resets_at)
  ] | join("\u001f")' 2>/dev/null)
EOF

[ -z "$model" ]  && model="?"
# effort.level está ausente cuando el modelo no soporta el parámetro de esfuerzo
[ -z "$effort" ] && effort="-"

# ---- Tiempo restante hasta un reinicio (resets_at en segundos Unix) ----
# Vacío -> "--". En el pasado -> "0h00m". >= 1 día -> "XdYYh", si no "XhYYm".
fmt_left() {
  local reset=$1 now remaining
  if [ -z "$reset" ]; then printf "%s" "--"; return; fi
  now=$(date +%s)
  remaining=$(( reset - now ))
  if   [ "$remaining" -le 0 ];     then printf "0h00m"
  elif [ "$remaining" -ge 86400 ]; then printf "%dd%02dh" $(( remaining / 86400 )) $(( (remaining % 86400) / 3600 ))
  else                                  printf "%dh%02dm" $(( remaining / 3600 ))  $(( (remaining % 3600) / 60 ))
  fi
}

# ---- Rama git (desde el dir del workspace, no el cwd del shell) ----
branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && branch="-"

# ---- Constructor de barra de progreso (10 celdas) ----
build_bar() {
  local pct=${1:-0} width=10 filled empty bar=""
  [ "$pct" -gt 100 ] && pct=100
  [ "$pct" -lt 0 ]   && pct=0
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  [ "$filled" -gt 0 ] && printf -v f "%${filled}s" && bar="${f// /█}"
  [ "$empty"  -gt 0 ] && printf -v e "%${empty}s"  && bar="${bar}${e// /░}"
  printf "%s" "$bar"
}

# ---- Color según umbral ----
# Único lugar donde viven los cortes 70 / 90: ctx, sess y week los comparten.
pct_color() {
  local pct=${1:-0}
  if   [ "$pct" -ge 90 ]; then printf "%s" "$RD"
  elif [ "$pct" -ge 70 ]; then printf "%s" "$YL"
  else                         printf "%s" "$GR"
  fi
}

# ---- Segmento barra + porcentaje ("--" si el dato no llegó) ----
pct_segment() {
  local pct=$1
  if [ -z "$pct" ]; then
    printf "%s" "${D}$(build_bar 0)${R} --"
  else
    printf "%s" "$(pct_color "$pct")$(build_bar "$pct")${R} ${pct}%"
  fi
}

# ---- Composición de la línea ----
SEP="  ${GY}│${R}  "
out=""
out+="${D}branch${R} ${BR}${branch}${R}"
out+="${SEP}${D}model${R} ${MD}${model}${R}"
[ -n "$fast" ] && out+=" ${YL}fast${R}"
out+="${SEP}${D}effort${R} ${EF}${effort}${R}"
out+="${SEP}${D}ctx${R} $(pct_segment "$ctx_pct")"
out+="${SEP}${D}sess${R} $(pct_segment "$sess_pct") ${D}($(fmt_left "$sess_reset"))${R}"
# La ventana semanal solo aparece si Claude Code la envía (suscriptores Pro/Max)
[ -n "$week_pct" ] && out+="${SEP}${D}week${R} $(pct_segment "$week_pct") ${D}($(fmt_left "$week_reset"))${R}"

printf "%b" "$out"
