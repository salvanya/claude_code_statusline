# Claude Code — Statusline personalizada

Una barra de estado compacta para Claude Code con 5 campos y referencias visuales:

```
branch main  │  model Opus 4.6  │  effort max  │  ctx ████░░░░░░ 42%  │  sess █░░░░░░░░░ 18%
```

## Qué muestra

| Campo    | Color    | Fuente                                    |
|----------|----------|-------------------------------------------|
| `branch` | azul     | rama git actual del workspace             |
| `model`  | naranja  | `model.display_name` del JSON del stdin   |
| `effort` | violeta  | último `/effort` de la sesión (transcripción) o `effortLevel` de `settings.json` |
| `ctx`    | bar+%    | `context_window.used_percentage`          |
| `sess`   | bar+%    | `rate_limits.five_hour.used_percentage`   |

Las barras son de 10 celdas (`█` llenas / `░` vacías) y cambian de color por umbral:
- **verde** si `<70%`
- **amarillo** si `70–89%`
- **rojo** si `≥90%`

Los labels (`branch`, `model`, `effort`, `ctx`, `sess`) aparecen en gris atenuado para servir de referencia visual sin competir con los valores.

## Dependencias

- **`bash`** — nativo en macOS/Linux. En Windows viene con [Git for Windows](https://git-scm.com/download/win) (Git Bash).
- **`jq`** — parser JSON de línea de comandos. Es lo único que puede faltar:
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt install jq`
  - Windows: `winget install jqlang.jq` *(o `choco install jq`)*
- **`git`** — ya instalado si usás Claude Code.
- **Terminal con UTF-8 + ANSI 256-color** — Windows Terminal, iTerm2, gnome-terminal, mintty. Todos los modernos.

## Instalación

### 1. Copiar el script

Copiar `statusline-command.sh` a `~/.claude/statusline-command.sh`:

**macOS / Linux:**
```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

**Windows (Git Bash):**
```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
```
*(En Windows no hace falta `chmod` porque el script se invoca con `bash` explícitamente.)*

### 2. Configurar `settings.json`

Editar `~/.claude/settings.json` (o crearlo si no existe) y agregar el bloque `statusLine`. El valor de `command` cambia según el SO:

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

Reemplazá `<USERNAME>` por tu usuario real. La ruta `/c/Users/...` es el formato MSYS/Git Bash para `C:\Users\...` — Claude Code invoca el comando vía Git Bash y `~` a veces no se expande bien en ese contexto.

**Si `settings.json` ya existe** con otros campos (`model`, `effortLevel`, etc.), solo agregá el bloque `statusLine` manteniendo el resto:

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

### 3. Reiniciar Claude Code

La statusline se refresca tras cada respuesta del asistente. Al reiniciar Claude Code ya debería verse.

## Probarlo antes de confiar

Para verificar que `jq`, `git` y el script funcionan sin errores, simulá el JSON que Claude Code envía por stdin:

```bash
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":18}}}' \
  | bash ~/.claude/statusline-command.sh
echo
```

Salida esperada (con colores reales en terminal):
```
branch main  │  model Opus 4.6  │  effort medium  │  ctx ████░░░░░░ 42%  │  sess █░░░░░░░░░ 18%
```

Si ves códigos crudos tipo `\033[38;5;39m`, el terminal no interpreta ANSI (improbable en 2026, pero posible en `cmd.exe` clásico).

## Sobre el campo `effort`

Claude Code **no expone** el nivel de esfuerzo en el JSON que recibe el statusline, y el comando `/effort max` aplica "this session only" sin escribir a `settings.json`. Para reflejar el valor real el script usa esta cadena de resolución:

1. **Transcripción de la sesión.** El JSON de stdin incluye `transcript_path`. El script busca en ese archivo el último mensaje de usuario con `<command-name>/effort</command-name>` y extrae su `<command-args>`. Así captura tanto `/effort max` (session-only) como `/effort high|low|medium` (persistente).
2. **`settings.json` (`effortLevel`).** Si no hay ningún `/effort` en la transcripción (sesión recién abierta), cae a este valor.
3. **`"medium"`.** Default si ninguno de los dos anteriores aplica.

El grep usa el prefijo exacto `"content":"<command-name>/effort</command-name>` para matchear solo mensajes reales del usuario, descartando `tool_results` que pudieran contener referencias históricas al mismo texto (importante si el propio script termina grepeando el transcript en un turno anterior).

**Costo:** un `grep -F` sobre un jsonl de ~1 MB corre en pocos ms, despreciable frente al costo de las llamadas a `jq`.

## Troubleshooting

| Síntoma | Causa | Solución |
|---|---|---|
| Statusline vacía | `jq` no instalado | Instalá `jq` con el gestor del SO |
| `statusline skipped · restart to fix` | Workspace no confiado | Reiniciá Claude Code y aceptá el diálogo de confianza |
| Muestra `branch -` | El cwd no es un repo git | Normal fuera de repos; no es un error |
| `sess` siempre en 0% | No sos suscriptor Claude.ai Pro/Max, o es el primer turno antes del primer API call | `rate_limits` solo aparece para suscriptores tras la primera respuesta |
| Códigos ANSI crudos visibles | Terminal no interpreta escape sequences | Usar un terminal moderno (Windows Terminal, iTerm2, etc.) |
| `effort` siempre `medium` | Sesión recién abierta sin `/effort` previo Y `effortLevel` ausente en `settings.json` | Ejecutar cualquier `/effort <valor>` en la sesión o agregar `"effortLevel": "..."` a `settings.json` |

## Personalización

Los códigos de color están definidos al inicio del script. Para cambiarlos, editá estas líneas:

```bash
BR='\033[38;5;39m'   # blue   — branch
MD='\033[38;5;208m'  # orange — model
EF='\033[38;5;135m'  # purple — effort
```

Los códigos `\033[38;5;N m` son 256-color (N = 0-255). Tabla de referencia: [256 color cheatsheet](https://www.ditig.com/256-colors-cheat-sheet).

Para cambiar el ancho de las barras, modificá `width=10` dentro de `build_bar()`.

Para cambiar los umbrales verde/amarillo/rojo, editá los `-ge 90` / `-ge 70` en la sección "Color según umbral".

## Archivos en este directorio

```
statusbar/
├── README.md               ← este archivo
└── statusline-command.sh   ← el script a copiar a ~/.claude/
```
