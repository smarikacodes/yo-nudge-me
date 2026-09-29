# shared helpers 

# Root of the installed plugin (changes on update) and the persistent data dir (survives updates).
YO_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YO_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/yo-nudge-me}"

yo_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo mac ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    Linux) echo linux ;;
    *) echo other ;;
  esac
}
YO_OS=$(yo_os)

# On Windows (Git Bash) the plugin paths arrive as C:\... strings. Convert for bash use,
# and convert back when handing a path to a Windows program.
yo_upath() {
  if [ "$YO_OS" = windows ] && command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}
yo_wpath() {
  if [ "$YO_OS" = windows ] && command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

YO_ROOT_U=$(yo_upath "$YO_ROOT")
YO_DATA_U=$(yo_upath "$YO_DATA")
YO_CONFIG="$YO_DATA_U/config.json"
YO_USER_SOUNDS="$YO_DATA_U/sounds"
YO_BUILTIN_SOUNDS="$YO_ROOT_U/sounds"

# ---------- defaults ----------

YO_DEFAULT_APPROVAL=letsgo
YO_DEFAULT_TASK_COMPLETE=yahoo
YO_DEFAULT_VOLUME=50

# ---------- tiny JSON readers ----------
# jq when available (macOS ships it, most Linux distros have it), sed fallback for flat fields.

yo_have_jq() { command -v jq >/dev/null 2>&1; }

# yo_json_get JSON KEY -> prints the value of a top-level key (string, number, or bool), or nothing.
yo_json_get() {
  local json="$1" key="$2"
  if yo_have_jq; then
    printf '%s' "$json" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$json" | tr -d '\n' | sed -n \
      -e "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
      -e "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([a-z0-9.][a-z0-9.]*\).*/\1/p" | head -n 1
  fi
}

# yo_json_has JSON KEY -> exit 0 if the key exists at the top level.
yo_json_has() {
  local json="$1" key="$2"
  if yo_have_jq; then
    printf '%s' "$json" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1
  else
    printf '%s' "$json" | grep -q "\"$key\"[[:space:]]*:"
  fi
}

# yo_json_escape STRING -> string safe to embed inside JSON double quotes.
yo_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ---------- config ----------

yo_valid_name() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'; }
yo_valid_volume() { printf '%s' "$1" | grep -Eq '^[0-9]+$' && [ "$1" -ge 0 ] && [ "$1" -le 100 ]; }

# Populates YO_APPROVAL, YO_TASK_COMPLETE, YO_VOLUME, YO_MUTED. Missing or invalid values fall back to defaults.
yo_load_config() {
  YO_APPROVAL=$YO_DEFAULT_APPROVAL
  YO_TASK_COMPLETE=$YO_DEFAULT_TASK_COMPLETE
  YO_VOLUME=$YO_DEFAULT_VOLUME
  YO_MUTED=false
  [ -r "$YO_CONFIG" ] || return 0
  local json v
  json=$(cat "$YO_CONFIG" 2>/dev/null) || return 0
  v=$(yo_json_get "$json" approval);      yo_valid_name "$v"   && YO_APPROVAL=$v
  v=$(yo_json_get "$json" task_complete); yo_valid_name "$v"   && YO_TASK_COMPLETE=$v
  v=$(yo_json_get "$json" volume);        yo_valid_volume "$v" && YO_VOLUME=$v
  v=$(yo_json_get "$json" muted);         [ "$v" = true ]      && YO_MUTED=true
  return 0
}

yo_save_config() {
  mkdir -p "$YO_DATA_U" 2>/dev/null || return 1
  local tmp="$YO_CONFIG.tmp.$$"
  printf '{\n  "approval": "%s",\n  "task_complete": "%s",\n  "volume": %s,\n  "muted": %s\n}\n' \
    "$YO_APPROVAL" "$YO_TASK_COMPLETE" "$YO_VOLUME" "$YO_MUTED" > "$tmp" && mv -f "$tmp" "$YO_CONFIG"
}

# ---------- sounds ----------

# yo_sound_path NAME -> prints the wav path. User sounds win over built-in ones. Exit 1 if not found.
yo_sound_path() {
  local name="$1"
  yo_valid_name "$name" || return 1
  if [ -r "$YO_USER_SOUNDS/$name.wav" ]; then printf '%s' "$YO_USER_SOUNDS/$name.wav"; return 0; fi
  if [ -r "$YO_BUILTIN_SOUNDS/$name.wav" ]; then printf '%s' "$YO_BUILTIN_SOUNDS/$name.wav"; return 0; fi
  return 1
}

# yo_list_sounds -> one "name<TAB>source" per line, user sounds first, deduped.
yo_list_sounds() {
  local f n
  for f in "$YO_USER_SOUNDS"/*.wav; do
    [ -r "$f" ] || continue
    n=$(basename "$f" .wav); yo_valid_name "$n" && printf '%s\tyours\n' "$n"
  done
  for f in "$YO_BUILTIN_SOUNDS"/*.wav; do
    [ -r "$f" ] || continue
    n=$(basename "$f" .wav)
    yo_valid_name "$n" || continue
    [ -r "$YO_USER_SOUNDS/$n.wav" ] && continue
    printf '%s\tbuilt-in\n' "$n"
  done
}

# ---------- focus detection ----------
# 0 = our session is focused, 1 = something else is, 2 = unknown, 3 = headless (Windows only).
# Finds the frontmost window's PID and checks it against our own ancestor chain.

yo_pid_is_ancestor() {
  local target="$1" p=$$ n=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ $n -lt 40 ]; do
    [ "$p" = "$target" ] && return 0
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    n=$((n + 1))
  done
  return 1
}

# yo_ancestor_pids -> prints our ancestor chain, one PID per line, nearest first (stops at PID 1).
yo_ancestor_pids() {
  local p=$$ n=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ $n -lt 40 ]; do
    printf '%s\n' "$p"
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    n=$((n + 1))
  done
}

# yo_has_ui_ancestor: 0 = an ancestor has a real window (human may be waiting), 1 = no such
# ancestor (spawned by a daemon/SDK worker, nobody waiting), 2 = unknown.
yo_has_ui_ancestor() {
  local p
  case "$YO_OS" in
    mac)
      local ids
      ids=$(osascript -e 'tell application "System Events" to get unix id of every application process' 2>/dev/null) || return 2
      [ -n "$ids" ] || return 2
      ids=",$(printf '%s' "$ids" | tr -d ' '),"
      for p in $(yo_ancestor_pids); do
        case "$ids" in *",$p,"*) return 0 ;; esac
      done
      return 1
      ;;
    linux)
      local tty
      for p in $(yo_ancestor_pids); do
        tty=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
        [ -n "$tty" ] && [ "$tty" != "?" ] && [ "$tty" != "??" ] && return 0
        if command -v xdotool >/dev/null 2>&1; then
          [ -n "$(xdotool search --pid "$p" 2>/dev/null)" ] && return 0
        fi
      done
      command -v xdotool >/dev/null 2>&1 && return 1
      return 2
      ;;
    windows)
      # focus.ps1 reports "headless" when no ancestor owns a window; handled in yo_is_focused.
      return 2
      ;;
    *) return 2 ;;
  esac
}

yo_powershell() {
  if command -v pwsh.exe >/dev/null 2>&1; then echo pwsh.exe
  elif command -v powershell.exe >/dev/null 2>&1; then echo powershell.exe
  else return 1; fi
}

yo_is_focused() {
  local front
  case "$YO_OS" in
    mac)
      front=$(osascript -e 'tell application "System Events" to get unix id of first application process whose frontmost is true' 2>/dev/null) || return 2
      printf '%s' "$front" | grep -Eq '^[0-9]+$' || return 2
      yo_pid_is_ancestor "$front" && return 0
      return 1
      ;;
    linux)
      command -v xdotool >/dev/null 2>&1 || return 2
      front=$(xdotool getactivewindow getwindowpid 2>/dev/null) || return 2
      printf '%s' "$front" | grep -Eq '^[0-9]+$' || return 2
      yo_pid_is_ancestor "$front" && return 0
      return 1
      ;;
    windows)
      local ps; ps=$(yo_powershell) || return 2
      local out
      out=$("$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(yo_wpath "$YO_ROOT_U/scripts/win/focus.ps1")" 2>/dev/null | tr -d '\r\n')
      case "$out" in
        focused) return 0 ;;
        unfocused) return 1 ;;
        headless) return 3 ;;
        *) return 2 ;;
      esac
      ;;
    *) return 2 ;;
  esac
}

# ---------- playback ----------
# yo_play FILE VOLUME(0-100). Detached so the calling hook returns immediately.

# 0-100 -> 0.00-1.00 (kept in a function: bash 3.2 mis-parses escaped quotes inside "$(...)")
yo_frac() { awk -v v="$1" 'BEGIN { printf "%.2f", v / 100 }'; }

yo_play() {
  local file="$1" vol="${2:-$YO_DEFAULT_VOLUME}"
  [ -r "$file" ] || return 1
  yo_valid_volume "$vol" || vol=$YO_DEFAULT_VOLUME
  case "$YO_OS" in
    mac)
      # afplay volume is 0.0 to 1.0
      nohup afplay -v "$(yo_frac "$vol")" "$file" >/dev/null 2>&1 </dev/null &
      ;;
    linux)
      if command -v paplay >/dev/null 2>&1; then
        nohup paplay --volume="$((vol * 65536 / 100))" "$file" >/dev/null 2>&1 </dev/null &
      elif command -v pw-play >/dev/null 2>&1; then
        nohup pw-play --volume="$(yo_frac "$vol")" "$file" >/dev/null 2>&1 </dev/null &
      elif command -v ffplay >/dev/null 2>&1; then
        nohup ffplay -nodisp -autoexit -loglevel quiet -volume "$vol" "$file" >/dev/null 2>&1 </dev/null &
      elif command -v aplay >/dev/null 2>&1; then
        nohup aplay -q "$file" >/dev/null 2>&1 </dev/null &
      else
        return 1
      fi
      ;;
    windows)
      local ps; ps=$(yo_powershell) || return 1
      nohup "$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$(yo_wpath "$YO_ROOT_U/scripts/win/play.ps1")" \
        -Path "$(yo_wpath "$file")" -Volume "$(yo_frac "$vol")" \
        >/dev/null 2>&1 </dev/null &
      ;;
    *) return 1 ;;
  esac
  return 0
}

# Same as yo_play but waits for the clip to finish. Used by preview/test so output arrives after the sound.
yo_play_wait() {
  yo_play "$@" || return 1
  wait 2>/dev/null
  return 0
}
