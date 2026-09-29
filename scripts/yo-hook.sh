event="${1:-}"
input=$(cat 2>/dev/null)

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 0

yo_load_config

# Decide whether to play sound. Returns 0 to play, 1 to stay quiet.
should_play() {
  [ "$YO_MUTED" = true ] && return 1

  if [ "$event" = task_complete ]; then
    # A subagent finishing is not something the user needs to act on.
    yo_json_has "$input" agent_id && return 1
    # Another hook is forcing Claude to continue; this is not a real stop.
    [ "$(yo_json_get "$input" stop_hook_active)" = true ] && return 1
    # Claude is paused waiting for background work that will wake it again. Not done yet.
    if yo_have_jq; then
      local waking
      waking=$(printf '%s' "$input" | jq -r '[.background_tasks[]? | select(.status=="running") | .type | select(. != "shell")] | length' 2>/dev/null)
      [ -n "$waking" ] && [ "$waking" != 0 ] && return 1
    else
      if printf '%s' "$input" | grep -q '"status"[[:space:]]*:[[:space:]]*"running"' \
        && printf '%s' "$input" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"(subagent|monitor|workflow|teammate|cloud session|MCP task)"'; then
        return 1
      fi
    fi
  fi

  # Headless: a session spawned by a daemon or SDK worker (for example claude-mem's summarizer)
  # has no terminal or editor above it. Nobody is waiting, so stay quiet. Unknown falls through.
  yo_has_ui_ancestor
  [ $? -eq 1 ] && return 1

  # Focus: 0 = user is looking at this session, 1 = not looking, 2 = unknown (fail open), 3 = headless.
  yo_is_focused
  case $? in
    0|3) return 1 ;;
    *) return 0 ;;
  esac
}

case "$event" in
  approval)
    should_play || exit 0
    file=$(yo_sound_path "$YO_APPROVAL") || file=$(yo_sound_path "$YO_DEFAULT_APPROVAL") || exit 0
    yo_play "$file" "$YO_VOLUME"
    ;;
  task_complete)
    should_play || exit 0
    file=$(yo_sound_path "$YO_TASK_COMPLETE") || file=$(yo_sound_path "$YO_DEFAULT_TASK_COMPLETE") || exit 0
    yo_play "$file" "$YO_VOLUME"
    ;;
  hello)
    marker="$YO_DATA_U/.hello-done"
    [ -e "$marker" ] && exit 0
    mkdir -p "$YO_DATA_U" 2>/dev/null && : > "$marker"
    if file=$(yo_sound_path "$YO_TASK_COMPLETE") || file=$(yo_sound_path "$YO_DEFAULT_TASK_COMPLETE"); then
      yo_play "$file" "$YO_VOLUME"
    fi
    printf '{"systemMessage":"yo-nudge-me is on. Mario will yell when Claude needs you and you are in another window. Try /yo list or /yo test."}\n'
    ;;
esac
exit 0
