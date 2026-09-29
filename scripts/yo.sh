# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "yo-nudge-me: could not load lib.sh"; exit 1; }

yo_load_config

usage() {
  cat <<EOF
yo-nudge-me commands
  /yo list                       show sounds and what each event plays
  /yo set approval <sound>       sound for "Claude needs your approval"
  /yo set task_complete <sound>  sound for "Claude finished"
  /yo preview <sound>            play a sound now
  /yo test                       real test: switch windows within 5 seconds
  /yo on | off                   unmute / mute
  /yo volume <0-100>             set volume (default 50)

Add your own: drop a short .wav into
  $YO_DATA/sounds/
and it shows up in /yo list under its filename.
EOF
}

cmd_list() {
  local status="on"
  [ "$YO_MUTED" = true ] && status="OFF (muted, run /yo on)"
  echo "yo-nudge-me  |  sounds: $status  |  volume: $YO_VOLUME"
  echo
  echo "  approval       -> $YO_APPROVAL"
  echo "  task_complete  -> $YO_TASK_COMPLETE"
  echo
  echo "Available sounds:"
  local line n src
  yo_list_sounds | while IFS=$'\t' read -r n src; do
    printf '  %-16s %s\n' "$n" "$src"
  done
  echo
  echo "Your own sounds go in: $YO_DATA/sounds/  (short .wav files)"
}

cmd_set() {
  local target="$1" name="$2"
  case "$target" in
    approval|task_complete) ;;
    *) echo "Usage: /yo set approval <sound>  or  /yo set task_complete <sound>"; return 1 ;;
  esac
  if ! yo_valid_name "$name"; then
    echo "Sound names use letters, digits, - and _ only."; return 1
  fi
  if ! yo_sound_path "$name" >/dev/null; then
    echo "No sound named '$name'. Run /yo list to see what's available."; return 1
  fi
  if [ "$target" = approval ]; then YO_APPROVAL=$name; else YO_TASK_COMPLETE=$name; fi
  yo_save_config || { echo "Could not write $YO_CONFIG"; return 1; }
  echo "$target -> $name"
  yo_play_wait "$(yo_sound_path "$name")" "$YO_VOLUME" >/dev/null 2>&1
}

cmd_preview() {
  local name="$1" file
  [ -z "$name" ] && { echo "Usage: /yo preview <sound>"; return 1; }
  file=$(yo_sound_path "$name") || { echo "No sound named '$name'. Run /yo list."; return 1; }
  if yo_play_wait "$file" "$YO_VOLUME"; then
    echo "Played $name at volume $YO_VOLUME."
  else
    echo "Could not play $name. No audio player found for this OS (see README troubleshooting)."
  fi
}

cmd_test() {
  local a t
  a=$(yo_sound_path "$YO_APPROVAL") || a=$(yo_sound_path "$YO_DEFAULT_APPROVAL")
  t=$(yo_sound_path "$YO_TASK_COMPLETE") || t=$(yo_sound_path "$YO_DEFAULT_TASK_COMPLETE")
  sleep 5
  yo_is_focused; local f=$?
  case $f in
    0)
      echo "Test result: this terminal was FOCUSED, so the hooks stayed quiet (that's the point)."
      echo "Run /yo test again and switch to another app within 5 seconds to hear both sounds."
      ;;
    1|2)
      if [ "$YO_MUTED" = true ]; then
        echo "Test result: you were away, but sounds are muted. Run /yo on."
        return 0
      fi
      yo_play_wait "$a" "$YO_VOLUME" >/dev/null 2>&1; sleep 0.4
      yo_play_wait "$t" "$YO_VOLUME" >/dev/null 2>&1
      if [ $f -eq 1 ]; then
        echo "Test result: you were in another window, so both sounds played: $YO_APPROVAL (approval), then $YO_TASK_COMPLETE (task complete)."
      else
        echo "Test result: focus could not be determined on this system, so yo-nudge-me plays every time. Both sounds played: $YO_APPROVAL, then $YO_TASK_COMPLETE."
        [ "$YO_OS" = linux ] && echo "Tip: install xdotool (X11) to enable focus detection on Linux."
      fi
      ;;
  esac
}

cmd_mute() {
  YO_MUTED=$1
  yo_save_config || { echo "Could not write $YO_CONFIG"; return 1; }
  if [ "$1" = true ]; then echo "Sounds off. Run /yo on to bring Mario back."; else echo "Sounds on."; fi
}

cmd_volume() {
  local v="$1"
  [ -z "$v" ] && { echo "Volume is $YO_VOLUME. Usage: /yo volume <0-100>"; return 0; }
  yo_valid_volume "$v" || { echo "Volume must be a whole number from 0 to 100."; return 1; }
  YO_VOLUME=$v
  yo_save_config || { echo "Could not write $YO_CONFIG"; return 1; }
  echo "Volume -> $v"
  local f; f=$(yo_sound_path "$YO_TASK_COMPLETE") || f=$(yo_sound_path "$YO_DEFAULT_TASK_COMPLETE")
  [ -n "$f" ] && yo_play_wait "$f" "$YO_VOLUME" >/dev/null 2>&1
}

case "${1:-}" in
  ""|list|status) cmd_list ;;
  set)            cmd_set "${2:-}" "${3:-}" ;;
  preview|play)   cmd_preview "${2:-}" ;;
  test)           cmd_test ;;
  on|unmute)      cmd_mute false ;;
  off|mute)       cmd_mute true ;;
  volume|vol)     cmd_volume "${2:-}" ;;
  help|-h|--help) usage ;;
  *)              echo "Unknown command: $1"; echo; usage; exit 1 ;;
esac
